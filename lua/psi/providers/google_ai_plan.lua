-- Gemini Interactions for Google AI Ultra, based on Pi PR #12614.
local auth = require("psi.providers.oauth_google_ai_plan")
local registry = require("psi.api_registry")
local image_policy = require("psi.image_policy")
local loop = require("psi.provider_loop")
local prelude = require("psi.prelude")
local session_manager = require("psi.session_manager")
local stream = require("psi.stream_parser")
local transform = require("psi.transform_messages")
local tools = require("psi.tools")
local sched = require("psi.sched")
local M = { has_auth = auth.has_credentials }
local provider, api = "google-ai-plan", "google-interactions"
local url = "https://generativelanguage.googleapis.com/v1beta/interactions"

local function resolve_model(model)
  return registry.resolve_model(provider, model and (model:gsub("^google%-ai%-plan/", "")))
end

local function text_block(text)
  return { type = "text", text = prelude.sanitize_surrogates(text or "") }
end

local function content_blocks(content)
  if type(content) == "string" then
    return prelude.as_array({ text_block(content) })
  end
  local out = prelude.as_array({})
  for _, block in ipairs(content or {}) do
    if block.type == "text" then
      out[#out + 1] = text_block(block.text)
    elseif block.type == "image" then
      if image_policy.blocked() then
        out[#out + 1] = text_block(image_policy.DISABLED_TEXT)
      else
        out[#out + 1] = { type = "image", mime_type = block.mimeType, data = block.data }
      end
    end
  end
  return out
end

local function build_messages(session, _, _, model)
  local out = prelude.as_array({})
  local function add(step)
    out[#out + 1] = step
  end
  local function user(content)
    local blocks = content_blocks(content)
    if #blocks > 0 then
      add({ type = "user_input", content = blocks })
    end
  end
  local function result(id, name, value, failed)
    return {
      type = "function_result",
      call_id = id,
      name = name,
      result = value,
      is_error = failed or nil,
    }
  end
  transform.replay_session(session, {
    user = function(message)
      user(message.content)
    end,
    assistant = function(message)
      local calls, signed = {}, false
      for _, block in ipairs(message.content or {}) do
        if block.type == "text" and block.text ~= "" then
          add({ type = "model_output", content = content_blocks(block.text) })
        elseif
          block.type == "thinking"
          and message.provider == provider
          and message.model == model
        then
          add({
            type = "thought",
            signature = block.thinkingSignature,
            summary = block.thinking ~= "" and content_blocks(block.thinking) or nil,
          })
          signed = signed or block.thinkingSignature ~= nil
        elseif block.type == "toolCall" and type(block.id) == "string" and block.id ~= "" then
          if not signed then
            add({ type = "thought", signature = "skip_thought_signature_validator" })
            signed = true
          end
          calls[#calls + 1] = { id = block.id, name = block.name }
          add({
            type = "function_call",
            id = block.id,
            name = block.name,
            arguments = block.arguments or {},
          })
        end
      end
      return calls
    end,
    tool_result = function(message)
      local blocks, chunks, image = content_blocks(message.content), {}, false
      for _, block in ipairs(blocks) do
        if block.type == "image" then
          image = true
        else
          chunks[#chunks + 1] = block.text
        end
      end
      return message.toolCallId,
        result(
          message.toolCallId,
          message.toolName,
          image and blocks or table.concat(chunks, "\n"),
          message.isError
        )
    end,
    tool_results = function(results)
      for _, item in ipairs(results) do
        add(item)
      end
    end,
    synthetic_tool_results = function(calls)
      for _, call in ipairs(calls) do
        add(result(call.id, call.name, "No result provided", true))
      end
    end,
    compaction_summary = user,
    branch_summary = user,
    custom_message = function(message)
      user(message.content)
    end,
  })
  return out
end

local function tool_specs(text)
  return tools.select_specs(text or "")
end

local function request_body(args)
  local level = args.thinking_level or args.reasoning_effort
  if level == "minimal" then
    level = "low"
  end
  if level == "xhigh" and args.model ~= "gemini-4-hydrogen" and args.model ~= "gemini-4-neon" then
    level = "high"
  end
  if level ~= "low" and level ~= "medium" and level ~= "high" and level ~= "xhigh" then
    level = nil
  end
  local body = { model = args.model, store = false, stream = true, input = args.messages }
  if args.system_prompt and args.system_prompt ~= "" then
    body.system_instruction = prelude.sanitize_surrogates(args.system_prompt)
  end
  if level or args.max_tokens then
    body.generation_config = {
      thinking_level = level,
      max_output_tokens = args.max_tokens,
      thinking_summaries = level and "auto" or nil,
    }
  end
  if args.tool_specs and #args.tool_specs > 0 then
    body.tools = prelude.as_array({})
    for _, spec in ipairs(args.tool_specs) do
      body.tools[#body.tools + 1] = {
        type = "function",
        name = spec.name,
        description = spec.description,
        parameters = spec.input_schema or spec.parameters,
      }
    end
  end
  return body
end

local function new_state()
  return { blocks = {}, by_index = {} }
end

local function handle_event(event, state, observer)
  local kind = event.event_type
  if kind == "step.start" and type(event.step) == "table" and type(event.index) == "number" then
    local step = event.step
    local block = {
      kind = step.type,
      chunks = {},
      signature = step.signature,
      id = step.id,
      name = step.name,
      arguments = step.arguments,
    }
    state.blocks[#state.blocks + 1] = block
    state.by_index[event.index] = block
  elseif kind == "step.delta" and type(event.delta) == "table" then
    local block, delta = state.by_index[event.index], event.delta
    if not block then
      return
    end
    local chunk, notify
    if block.kind == "model_output" and delta.type == "text" then
      chunk, notify = delta.text, observer.on_assistant_text_delta
    elseif
      block.kind == "thought"
      and delta.type == "thought_summary"
      and type(delta.content) == "table"
    then
      chunk, notify = delta.content.text, observer.on_thinking_delta
    elseif block.kind == "thought" and delta.type == "thought_signature" then
      block.signature = delta.signature
    elseif block.kind == "function_call" and delta.type == "arguments_delta" then
      chunk = delta.arguments
    end
    if type(chunk) == "string" then
      block.chunks[#block.chunks + 1] = chunk
      if notify then
        notify(chunk)
      end
    end
  elseif kind == "interaction.completed" and type(event.interaction) == "table" then
    local interaction = event.interaction
    state.stop_reason = (
      { completed = "stop", requires_action = "tool_use", incomplete = "length" }
    )[interaction.status]
    local u = interaction.usage
    if type(u) == "table" then
      local cached = tonumber(u.total_cached_tokens) or 0
      state.usage = {
        input_tokens = math.max(0, (tonumber(u.total_input_tokens) or 0) - cached),
        cache_read_input_tokens = cached,
        output_tokens = (tonumber(u.total_output_tokens) or 0)
          + (tonumber(u.total_thought_tokens) or 0),
      }
    end
  elseif kind == "error" then
    state.error = "Google Interactions reported a stream error"
  end
end

local function parser_push(parser, chunk, state, observer)
  stream.push_sse(parser, chunk, {
    on_event = function(_, data)
      local event = prelude.safe_json_decode(data, nil)
      if type(event) == "table" then
        handle_event(event, state, observer)
      end
    end,
  })
end

local function state_text(state)
  local text = {}
  for _, block in ipairs(state.blocks) do
    if block.kind == "model_output" then
      text[#text + 1] = table.concat(block.chunks)
    end
  end
  return table.concat(text)
end

local function finalize(state)
  local blocks, calls = prelude.as_array({}), {}
  for _, block in ipairs(state.blocks) do
    local text = table.concat(block.chunks)
    if block.kind == "thought" then
      blocks[#blocks + 1] = { type = "thinking", thinking = text, signature = block.signature }
    elseif block.kind == "model_output" then
      blocks[#blocks + 1] = text_block(text)
    elseif block.kind == "function_call" then
      local args = block.arguments or {}
      if text ~= "" then
        args = text:match("^%s*{") and prelude.safe_json_decode(text, nil) or nil
      end
      if
        type(args) ~= "table"
        or type(block.id) ~= "string"
        or block.id == ""
        or type(block.name) ~= "string"
        or block.name == ""
      then
        state.error = "Google Interactions returned a malformed tool call"
      else
        blocks[#blocks + 1] = { type = "tool_use", id = block.id, name = block.name, input = args }
        calls[#calls + 1] = { id = block.id, name = block.name, arguments = args }
      end
    end
  end
  if not state.stop_reason and not state.error then
    state.error = "Google stream ended without a successful interaction.completed"
  end
  if state.stop_reason == "tool_use" and #calls == 0 then
    state.error = "Google requested tools without a tool call"
  end
  if state.stop_reason == "length" or state.error then
    calls = {}
  end
  return blocks, calls
end

local function persist(state, model, blocks, _, stop, err)
  session_manager.append_assistant(state_text(state), blocks, {
    usage = state.usage,
    stop_reason = stop or state.stop_reason,
    error_message = err,
    model = model,
    provider = provider,
    api = api,
  })
end

local function http_error(status, _)
  if status == 401 then
    return "Google AI Ultra sign-in failed. Run /login google-ai-plan again."
  end
  if status == 403 then
    return "Google denied access. Check the Psi OAuth client approval and your Google AI Ultra entitlement."
  end
  if status == 429 then
    return "Google AI Ultra rate or plan quota limit reached."
  end
  return "Google Interactions request failed (HTTP " .. tostring(status) .. ")."
end

local function headers(entry)
  return {
    "Authorization: Bearer " .. entry.access,
    "Content-Type: application/json",
    "Accept: text/event-stream",
  }
end

function M.run_turn(opts)
  local entry, err = auth.credentials()
  if not entry then
    return false, err
  end
  opts.model = resolve_model(opts.model)
  return loop.run_turn(opts, {
    provider_name = provider,
    api_name = api,
    url = url,
    headers = headers(entry),
    tool_specs = tool_specs,
    build_messages = build_messages,
    request_body = request_body,
    parser_new = stream.sse_parser,
    parser_push = parser_push,
    new_state = new_state,
    finalize = finalize,
    persist = persist,
    classify_http_error = http_error,
    text = state_text,
    stream_error = function(state)
      return state.error
    end,
  })
end

function M.complete_text(opts)
  local entry, err = auth.credentials()
  if not entry then
    return false, err
  end
  local body = request_body({
    model = resolve_model(opts.model),
    system_prompt = opts.system_prompt,
    messages = prelude.as_array({
      { type = "user_input", content = content_blocks(opts.user_text or "") },
    }),
    max_tokens = opts.max_tokens,
  })
  local handle, begin_err = psi.http_stream_begin(url, headers(entry), psi.json_encode(body))
  if not handle then
    return false, begin_err
  end
  local parser, state = stream.sse_parser(), new_state()
  repeat
    local chunk, done = sched.http_poll(handle, 50)
    if chunk then
      parser_push(parser, chunk, state, {})
    end
    if done then
      break
    end
    if opts.abort_check and opts.abort_check() then
      psi.http_stream_finish(handle)
      return false, "aborted"
    end
  until false
  local status, transport_error = psi.http_stream_finish(handle)
  if status < 0 then
    return false, transport_error
  end
  if status < 200 or status >= 300 then
    return false, http_error(status)
  end
  finalize(state)
  if state.error then
    return false, state.error
  end
  return true, state_text(state)
end

M._debug = {
  build_messages = build_messages,
  request_body = request_body,
  new_state = new_state,
  parser_push = parser_push,
  finalize = finalize,
  text = state_text,
}
return M

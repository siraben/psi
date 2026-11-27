-- Radius transport for Pi's pi-messages wire protocol.
local auth = require("psi.providers.oauth_radius")
local storage = require("psi.auth_storage")
local prelude = require("psi.prelude")
local prompt = require("psi.transform_messages")
local image_policy = require("psi.image_policy")
local loop = require("psi.provider_loop")
local session_manager = require("psi.session_manager")
local sse = require("psi.stream_parser")
local sched = require("psi.sched")
local tools = require("psi.tools")
local registry = require("psi.api_registry")
local compat = require("psi.providers.openai_compat")
local M = {}
local url = "https://radius.pi.dev/v1/messages"

local function text(value)
  return { type = "text", text = prelude.sanitize_surrogates(value or "") }
end

local function content(blocks)
  if type(blocks) == "string" then
    return prelude.as_array({ text(blocks) })
  end
  local out = prelude.as_array({})
  for _, block in ipairs(blocks or {}) do
    if block.type == "text" then
      out[#out + 1] = text(block.text)
    elseif block.type == "image" then
      out[#out + 1] = image_policy.blocked() and text(image_policy.DISABLED_TEXT)
        or { type = "image", mimeType = block.mimeType, data = block.data }
    end
  end
  return out
end

local function now()
  return os.time() * 1000
end

local function empty_usage()
  return {
    input = 0,
    output = 0,
    cacheRead = 0,
    cacheWrite = 0,
    totalTokens = 0,
    cost = { input = 0, output = 0, cacheRead = 0, cacheWrite = 0, total = 0 },
  }
end

local function build_messages(session, _, _, model)
  local out = prelude.as_array({})
  local function user(blocks, timestamp)
    out[#out + 1] = {
      role = "user",
      content = content(blocks),
      timestamp = type(timestamp) == "number" and timestamp or now(),
    }
  end
  local function result(id, name, blocks, failed, timestamp)
    return {
      role = "toolResult",
      toolCallId = id,
      toolName = name,
      content = content(blocks),
      isError = failed == true,
      timestamp = timestamp or now(),
    }
  end
  prompt.replay_session(session, {
    user = function(message)
      user(message.content, message.timestamp)
    end,
    assistant = function(message)
      local blocks, tools_called = prelude.as_array({}), {}
      for _, block in ipairs(message.content or {}) do
        if block.type == "text" then
          local item = text(block.text)
          if message.provider == "radius" and message.model == model then
            item.textSignature = block.textSignature
          end
          blocks[#blocks + 1] = item
        elseif
          block.type == "thinking"
          and message.provider == "radius"
          and message.model == model
        then
          blocks[#blocks + 1] = {
            type = "thinking",
            thinking = text(block.thinking).text,
            thinkingSignature = block.thinkingSignature,
            redacted = block.redacted,
          }
        elseif block.type == "toolCall" and block.id and block.name then
          blocks[#blocks + 1] = {
            type = "toolCall",
            id = block.id,
            name = block.name,
            arguments = block.arguments or {},
          }
          tools_called[#tools_called + 1] = { id = block.id, name = block.name }
        end
      end
      if #blocks > 0 then
        out[#out + 1] = {
          role = "assistant",
          content = blocks,
          provider = "radius",
          api = "pi-messages",
          model = model,
          stopReason = #tools_called > 0 and "toolUse" or "stop",
          usage = empty_usage(),
          timestamp = message.timestamp or now(),
        }
      end
      return tools_called
    end,
    tool_result = function(message)
      return message.toolCallId,
        result(
          message.toolCallId,
          message.toolName,
          message.content,
          message.isError,
          message.timestamp
        )
    end,
    tool_results = function(items)
      for _, item in ipairs(items) do
        out[#out + 1] = item
      end
    end,
    synthetic_tool_results = function(calls)
      for _, call in ipairs(calls) do
        out[#out + 1] = result(call.id, call.name, "No result provided", true)
      end
    end,
    compaction_summary = user,
    branch_summary = user,
    custom_message = function(message)
      user(message.content, message.timestamp)
    end,
  })
  return out
end

local function request(args)
  local messages, definitions = prelude.as_array({}), prelude.as_array({})
  for _, tool in ipairs(args.tool_specs or {}) do
    definitions[#definitions + 1] = {
      name = tool.name,
      description = tool.description,
      parameters = tool.input_schema or tool.parameters,
    }
  end
  if #definitions > 0 or (args.system_prompt and args.system_prompt ~= "") then
    messages[1] = {
      role = "system",
      content = text(args.system_prompt).text,
      toolsAdded = #definitions > 0 and definitions or nil,
      timestamp = now(),
    }
  end
  for _, msg in ipairs(args.messages) do
    messages[#messages + 1] = msg
  end
  local effort = args.thinking_level or args.reasoning_effort
  local allowed = { minimal = true, low = true, medium = true, high = true, xhigh = true }
  return {
    model = args.model,
    context = { messages = messages },
    options = {
      maxTokens = args.max_tokens,
      reasoning = allowed[effort] and effort or nil,
      cacheRetention = "none",
    },
  }
end

local function new_state()
  return { order = {}, by_index = {} }
end

local stop_reasons = { stop = "stop", length = "length", toolUse = "tool_use" }
local starts = { text_start = "text", thinking_start = "thinking", toolcall_start = "tool" }

local function arguments_object(value)
  if type(value) ~= "table" then
    return false
  end
  local mt = getmetatable(value)
  if type(mt) == "table" and mt.__jsontype == "array" then
    return false
  end
  for key in pairs(value) do
    if type(key) ~= "string" then
      return false
    end
  end
  return true
end

local function consume(event, state, observer)
  if state.stop_reason or state.error then
    return
  end
  local kind, idx = event.type, event.contentIndex
  if kind == "error" then
    state.error = type(event.errorMessage) == "string" and event.errorMessage
      or "Radius returned a stream error"
  elseif kind == "done" then
    state.stop_reason = stop_reasons[event.reason]
    state.response_id = event.responseId
    if type(event.usage) == "table" then
      local u = event.usage
      state.usage = {
        input_tokens = tonumber(u.input) or 0,
        output_tokens = tonumber(u.output) or 0,
        cache_read_input_tokens = tonumber(u.cacheRead) or 0,
        cache_creation_input_tokens = tonumber(u.cacheWrite) or 0,
      }
    end
  elseif type(idx) == "number" and idx >= 0 and idx % 1 == 0 then
    if starts[kind] and not state.by_index[idx] then
      local slot = { kind = starts[kind], parts = {}, id = event.id, name = event.toolName }
      state.by_index[idx] = slot
      state.order[#state.order + 1] = slot
    end
    local slot = state.by_index[idx]
    if not slot then
      return
    end
    local notify
    if kind == "text_delta" and slot.kind == "text" then
      notify = observer.on_assistant_text_delta
    elseif kind == "thinking_delta" and slot.kind == "thinking" then
      notify = observer.on_thinking_delta
    end
    if type(event.delta) == "string" and (kind == "text_delta" or kind == "thinking_delta") then
      slot.parts[#slot.parts + 1] = event.delta
      if notify then
        notify(event.delta)
      end
    elseif (kind == "text_end" or kind == "thinking_end") and type(event.content) == "string" then
      slot.value, slot.signature, slot.redacted =
        event.content, event.contentSignature, event.redacted
    elseif kind == "toolcall_end" and slot.kind == "tool" then
      local call = event.toolCall
      if
        type(call) == "table"
        and type(call.id) == "string"
        and call.id ~= ""
        and type(call.name) == "string"
        and call.name ~= ""
        and arguments_object(call.arguments)
        and call.id == slot.id
        and call.name == slot.name
      then
        slot.call = { id = call.id, name = call.name, arguments = call.arguments }
      end
    end
  end
end

local function parser_push(parser, chunk, state, observer)
  sse.push_sse(parser, chunk, {
    on_event = function(_, raw)
      local event = prelude.safe_json_decode(raw, nil)
      if type(event) == "table" then
        consume(event, state, observer)
      end
    end,
  })
end

local function state_text(state)
  local parts = {}
  for _, slot in ipairs(state.order) do
    if slot.kind == "text" then
      parts[#parts + 1] = slot.value or table.concat(slot.parts)
    end
  end
  return table.concat(parts)
end

local function finalize(state)
  local blocks, calls = prelude.as_array({}), {}
  for _, slot in ipairs(state.order) do
    if slot.kind == "text" then
      blocks[#blocks + 1] = {
        type = "text",
        text = slot.value or table.concat(slot.parts),
        textSignature = slot.signature,
      }
    elseif slot.kind == "thinking" then
      blocks[#blocks + 1] = {
        type = "thinking",
        thinking = slot.value or table.concat(slot.parts),
        signature = slot.signature,
        redacted = slot.redacted,
      }
    elseif slot.call then
      local call = slot.call
      blocks[#blocks + 1] =
        { type = "tool_use", id = call.id, name = call.name, input = call.arguments }
      calls[#calls + 1] = call
    elseif state.stop_reason == "tool_use" then
      state.error = state.error or "Radius returned an incomplete tool call"
    end
  end
  if not state.stop_reason and not state.error then
    state.error = "Radius stream ended without a terminal event"
  end
  if state.stop_reason == "tool_use" and #calls == 0 then
    state.error = state.error or "Radius requested tool use without a complete call"
  end
  return blocks, not state.error and state.stop_reason == "tool_use" and calls or {}
end

local function persist(state, model, blocks, _, stop, err)
  session_manager.append_assistant(
    state_text(state),
    blocks,
    {
      provider = "radius",
      api = "pi-messages",
      model = model,
      response_id = state.response_id,
      usage = state.usage,
      stop_reason = stop or state.stop_reason,
      error_message = err,
    }
  )
end

local function headers()
  local key, err = storage.resolve_api_key("radius", "RADIUS_API_KEY")
  if not key then
    key, err = auth.access_token()
  end
  if not key or key:find("[%c%s]") then
    return nil, err or "Invalid Radius credential"
  end
  return {
    "Authorization: Bearer " .. key,
    "Content-Type: application/json",
    "Accept: text/event-stream",
  }
end

function M.has_auth()
  return storage.has_api_key("radius", "RADIUS_API_KEY") or auth.has_credentials()
end

function M.run_turn(opts)
  local hdr, err = headers()
  if not hdr then
    return false, err
  end
  opts.model = registry.resolve_model("radius", opts.model)
  return loop.run_turn(opts, {
    provider_name = "radius",
    api_name = "pi-messages",
    url = url,
    headers = hdr,
    include_response_id = true,
    tool_specs = tools.select_specs,
    build_messages = build_messages,
    request_body = request,
    parser_new = sse.sse_parser,
    parser_push = parser_push,
    new_state = new_state,
    finalize = finalize,
    persist = persist,
    text = state_text,
    classify_http_error = compat.classify_http_error,
    stream_error = function(state)
      return state.error
    end,
  })
end

function M.complete_text(opts)
  local hdr, err = headers()
  if not hdr then
    return false, err
  end
  local body = request({
    model = registry.resolve_model("radius", opts.model),
    system_prompt = opts.system_prompt,
    max_tokens = opts.max_tokens,
    messages = { { role = "user", content = content(opts.user_text or ""), timestamp = now() } },
  })
  local handle, begin_err = psi.http_stream_begin(url, hdr, psi.json_encode(body))
  if not handle then
    return false, begin_err
  end
  local parser, state = sse.sse_parser(), new_state()
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
    return false, compat.classify_http_error(status, "", "radius")
  end
  finalize(state)
  if state.error then
    return false, state.error
  end
  return true, state_text(state)
end

M._debug =
  { request = request, new_state = new_state, parser_push = parser_push, finalize = finalize }
return M

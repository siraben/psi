--[==[psi-test
expect = "ok"
]==]
local registry = require("psi.api_registry")
local p = require("psi.providers.google_ai_plan")._debug
local auth = require("psi.providers.oauth_google_ai_plan")
local spec, model = registry.resolve_route("google-ai-plan/gemini-4-neon")
assert(spec.api == "google-interactions" and model == "gemini-4-neon")
assert(not auth.has_credentials())
local login, err = auth.begin_login()
assert(not login and err:find("PSI_GOOGLE_AI_PLAN_CLIENT_ID", 1, true))
local body = p.request_body({
  model = model,
  system_prompt = "test",
  messages = {},
  thinking_level = "xhigh",
  tool_specs = { { name = "read", input_schema = { type = "object" } } },
})
assert(body.stream and body.store == false and body.system_instruction == "test")
assert(
  body.tools[1].parameters.type == "object" and body.generation_config.thinking_level == "xhigh"
)

local sse = require("psi.stream_parser").sse_parser()
local s = p.new_state()
local function event(e)
  p.parser_push(sse, "data: " .. psi.json_encode(e) .. "\n\n", s, {})
end
local function step(index, descriptor, delta)
  event({ event_type = "step.start", index = index, step = descriptor })
  event({ event_type = "step.delta", index = index, delta = delta })
end
step(0, { type = "thought" }, { type = "thought_signature", signature = "abc" })
step(1, { type = "model_output" }, { type = "text", text = "Reading" })
step(
  2,
  { type = "function_call", name = "read", id = "call_1" },
  { type = "arguments_delta", arguments = '{"path":' }
)
event({
  event_type = "step.delta",
  index = 2,
  delta = { type = "arguments_delta", arguments = '"a"}' },
})
event({ event_type = "interaction.completed", interaction = { status = "requires_action" } })
local blocks, calls = p.finalize(s)
assert(not s.error and s.stop_reason == "tool_use" and p.text(s) == "Reading")
assert(blocks[1].signature == "abc" and calls[1].arguments.path == "a")
local partial = p.new_state()
p.finalize(partial)
assert(partial.error)
return "ok"

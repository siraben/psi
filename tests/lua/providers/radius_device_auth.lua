--[==[psi-test
expect = "ok"
env = { PSI_AUTH_FILE = "{TMP}/auth.json", RADIUS_API_KEY = "" }
]==]
local auth = require("psi.providers.oauth_radius")
local radius = require("psi.providers.radius")
local storage = require("psi.auth_storage")
local now = 1000
local getenv = os.getenv
os.getenv = function(name)
  if name == "PSI_RADIUS_OAUTH_CLIENT_ID" then
    return "psi-radius"
  end
  return getenv(name)
end
os.time = function()
  return now
end
psi.http_post = function(url, _, body)
  assert(body:find("client_id=psi%-radius"))
  if url == "https://radius.pi.dev/v1/oauth/device" then
    return 200,
      '{"device_code":"private","user_code":"PUBLIC","verification_uri":"https://radius.pi.dev/activate","expires_in":900}'
  end
  assert(url == "https://radius.pi.dev/v1/oauth/token")
  if body:find("grant_type=refresh_token", 1, true) then
    assert(body:find("refresh_token=keep", 1, true))
    return 200, '{"access_token":"refreshed","expires_in":1800}'
  end
  return 200, '{"access_token":"first","refresh_token":"keep","expires_in":1800}'
end
assert(auth.begin_login().user_code == "PUBLIC")
now = 1005
assert(auth.finish_login("check") and auth.has_credentials())
assert(auth.access_token() == "first")
now = 2600
assert(auth.access_token() == "refreshed" and storage.get("radius").refresh == "keep")
require("psi.provider_loop").run_turn = function(opts, cfg)
  assert(opts.model == "balanced" and cfg.url == "https://radius.pi.dev/v1/messages")
  assert(cfg.headers[1] == "Authorization: Bearer refreshed")
  local body = cfg.request_body({
    model = opts.model,
    system_prompt = "test",
    messages = { { role = "user", content = "hello" } },
    tool_specs = { { name = "read", input_schema = { type = "object" } } },
    max_tokens = 500,
  })
  assert(body.options.maxTokens == 500 and body.model == "balanced")
  assert(
    body.context.messages[1].toolsAdded[1].name == "read"
      and body.context.messages[2].role == "user"
  )
  return true
end
assert(radius.run_turn({}))
local p = radius._debug
local wire = require("psi.stream_parser").sse_parser()
local state = p.new_state()
local function feed(e)
  p.parser_push(wire, "data: " .. psi.json_encode(e) .. "\n\n", state, {})
end
feed({ type = "text_start", contentIndex = 0 })
feed({ type = "text_delta", contentIndex = 0, delta = "read it" })
feed({ type = "toolcall_start", contentIndex = 1, id = "call_1", toolName = "read" })
feed({
  type = "toolcall_end",
  contentIndex = 1,
  toolCall = { id = "call_1", name = "read", arguments = { path = "/tmp/test" } },
})
feed({ type = "done", reason = "toolUse", usage = { input = 13, output = 7, cacheRead = 2 } })
local blocks, calls = p.finalize(state)
assert(not state.error and blocks[1].text == "read it" and calls[1].arguments.path == "/tmp/test")
assert(state.usage.cache_read_input_tokens == 2)
local interrupted = p.new_state()
p.finalize(interrupted)
assert(interrupted.error)
return "ok"

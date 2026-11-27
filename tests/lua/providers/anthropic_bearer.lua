--[==[psi-test
expect = "ok"
]==]
local provider = require("psi.providers.anthropic")
local storage = require("psi.auth_storage")
local env, stored = { ANTHROPIC_AUTH_TOKEN = "temporary", ANTHROPIC_API_KEY = "env-key" }, nil
os.getenv = function(name)
  return env[name]
end
storage.resolve_api_key = function()
  return stored
end
storage.has_api_key_entry = function()
  return stored ~= nil
end
require("psi.provider_loop").run_turn = function(_, cfg)
  return cfg.headers[3]
end

assert(provider.has_auth())
assert(provider.run_turn({}) == "Authorization: Bearer temporary")
stored = "saved-key"
assert(provider.run_turn({}) == "x-api-key: saved-key")
stored = nil
env.ANTHROPIC_AUTH_TOKEN = "bad\nheader"
assert(provider.run_turn({}) == "x-api-key: env-key")
env.ANTHROPIC_API_KEY = nil
assert(not provider.has_auth())
return "ok"

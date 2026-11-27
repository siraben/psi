--[==[psi-test
expect = "ok"
]==]
local storage = require("psi.auth_storage")
local entry, read_error, refreshes = nil, nil, 0
local getter = os.getenv
os.getenv = function(name)
  if name == "XAI_API_KEY" then
    return "ambient-api-key"
  end
  if name == "PSI_XAI_OAUTH_CLIENT_ID" then
    return "registered-client"
  end
  if name == "PSI_TEST_NO_SUCH_KEY" then
    return nil
  end
  return getter(name)
end
storage.get = function()
  return entry, read_error
end
local rules = {
  env = "XAI_API_KEY",
  oauth = function(saved)
    assert(saved == entry)
    refreshes = refreshes + 1
    return nil, "refresh was rejected"
  end,
  has_oauth = function(saved)
    return saved == entry
  end,
}
assert(storage.resolve_provider("xai", rules) == "ambient-api-key")
entry = {
  type = "oauth",
  access = "saved-oauth",
  refresh = "refresh",
  client = "registered-client",
  expires = (os.time() + 3600) * 1000,
}
assert(storage.provider_has_auth("xai", rules) and refreshes == 0)
local key, err = storage.resolve_provider("xai", rules)
assert(not key and err == "refresh was rejected" and refreshes == 1)
require("psi.providers.openai_compat").run_turn = function(_, cfg)
  return cfg.headers[2]
end
local xai = require("psi.providers.xai")
assert(xai.run_turn({}) == "Authorization: Bearer saved-oauth")
entry = { type = "api_key", key = "$PSI_TEST_NO_SUCH_KEY" }
key, err = storage.resolve_provider("xai", rules)
assert(not key and err:find("stored API key", 1, true))
entry = { type = "api_key", key = "saved-api-key" }
assert(xai.run_turn({}) == "Authorization: Bearer saved-api-key")
entry = { type = "unknown" }
assert(not storage.provider_has_auth("xai", rules) and not storage.resolve_provider("xai", rules))
entry, read_error = nil, "cannot parse the auth file"
key, err = storage.resolve_provider("xai", rules)
assert(not storage.provider_has_auth("xai", rules) and not key and err == read_error)
return "ok"

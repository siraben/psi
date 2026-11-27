--[==[psi-test
expect = "ok"
]==]
local auth = require("psi.providers.oauth_xai")
local storage = require("psi.auth_storage")
local client, now, entry, phase, calls = nil, 1000, nil, "device", 0
local getenv = os.getenv
os.getenv = function(key)
  if key == "PSI_XAI_OAUTH_CLIENT_ID" then
    return client
  end
  return getenv(key)
end
os.time = function()
  return now
end
storage.set = function(provider, value)
  assert(provider == "xai")
  entry = value
  return true
end
storage.get = function()
  return entry
end
psi.http_post = function(url, _, body)
  calls = calls + 1
  assert(url:match("^https://auth%.x%.ai/") and body:find("client_id=psi%-test"))
  if phase == "device" then
    return 200,
      '{"device_code":"private-device", "user_code":"ABC-123", "expires_in":300,"interval":5,"verification_uri":"https://accounts.x.ai/oauth2/device"}'
  elseif phase == "slow" then
    return 400, '{"error":"slow_down"}'
  elseif phase == "approved" then
    return 200, '{"access_token":"access", "refresh_token":"refresh", "expires_in":3600}'
  else
    assert(body:find("refresh_token=refresh", 1, true))
    return 200, '{"access_token":"fresh", "expires_in":3600}'
  end
end
assert(not auth.begin_login() and calls == 0)
client = "psi-test"
require("psi.clipboard").write_osc52 = function()
  return false
end
local output = require("psi.slash_commands").handle_command_list("/login oauth xai")
assert(psi.json_encode(output):find("/login oauth xai check", 1, true))
assert(not auth.finish_login("check") and calls == 1)
phase, now = "slow", 1005
local ok, err = auth.finish_login("check")
assert(not ok and err:find("slower", 1, true) and calls == 2)
phase, now = "approved", 1014
assert(not auth.finish_login("check") and calls == 2)
now = 1015
assert(auth.finish_login("check") and auth.has_credentials())
assert(auth.access_token() == "access")
now, phase = 4600, "refresh"
assert(auth.access_token() == "fresh" and entry.refresh == "refresh")
client = "other"
assert(not auth.has_credentials())
return "ok"

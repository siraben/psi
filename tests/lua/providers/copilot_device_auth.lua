--[==[psi-test
expect = "ok"
]==]
local auth = require("psi.providers.oauth_github_copilot")
local copilot = require("psi.providers.github_copilot")
local storage = require("psi.auth_storage")
local entry, now, exchanges = nil, 1000, 0
local getenv = os.getenv
os.getenv = function(name)
  if name == "PSI_GITHUB_COPILOT_CLIENT_ID" then
    return "psi-copilot"
  end
  return getenv(name)
end
os.time = function()
  return now
end
storage.set = function(provider, value)
  assert(provider == "github-copilot")
  entry = value
  return true
end
storage.get = function()
  return entry
end
psi.http_post = function(url, _, body)
  assert(body:find("client_id=psi%-copilot"))
  if url == "https://github.com/login/device/code" then
    assert(body:find("scope=read%%3Auser"))
    return 200,
      '{"device_code":"private","user_code":"PUBLIC","verification_uri":"https://github.com/login/device","expires_in":900}'
  end
  assert(
    url == "https://github.com/login/oauth/access_token"
      and body:find("device_code=private", 1, true)
  )
  return 200, '{"access_token":"github-token"}'
end
local token = "secret;proxy-ep=proxy.business.githubcopilot.com;end"
psi.http_get = function(url, headers)
  assert(
    url == "https://api.github.com/copilot_internal/v2/token"
      and headers[2] == "Authorization: Bearer github-token"
  )
  exchanges = exchanges + 1
  return 200, psi.json_encode({ token = token, expires_at = now + 3600 })
end
assert(auth.begin_login().user_code == "PUBLIC")
now = 1005
assert(auth.finish_login("check"))
assert(
  auth.has_credentials()
    and entry.refresh == "github-token"
    and auth.access_token() == token
    and exchanges == 1
)
require("psi.provider_loop").run_turn = function(args, cfg)
  assert(
    args.model == "gpt-5-mini" and cfg.url == "https://api.business.githubcopilot.com/responses"
  )
  assert(cfg.headers[4] == "Authorization: Bearer " .. token)
  return true
end
assert(copilot.run_turn({}))
now = now + 3600
assert(auth.access_token() == token and exchanges == 2)
entry.access = "secret;proxy-ep=proxy.attacker.example;end"
local ok, err = copilot.run_turn({})
assert(not ok and err:find("unsupported gateway", 1, true))
return "ok"

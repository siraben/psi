--[==[psi-test
expect = "ok"
env = { PSI_AUTH_FILE = "{TMP}/auth.json", META_API_KEY = "" }
]==]
local auth = require("psi.providers.oauth_meta")
local meta = require("psi.providers.meta")
local storage = require("psi.auth_storage")
local now, mint_count, revoked = 1000, 0, false
local getenv = os.getenv
os.getenv = function(name)
  if name == "PSI_META_OAUTH_CLIENT_ID" then
    return "psi-meta"
  end
  return getenv(name)
end
os.time = function()
  return now
end
psi.http_post = function(url, headers, body)
  if url == "https://auth.meta.com/oidc/device/authorization/" then
    assert(body == "client_id=psi-meta")
    return 200,
      '{"device_code":"private", "user_code":"PUBLIC", "verification_uri":"https://www.meta.com/device/"}'
  elseif url == "https://auth.meta.com/oidc/device/token/" then
    assert(body:find("device_code=private", 1, true))
    return 200, '{"access_token":"identity"}'
  end
  assert(
    url == "https://api.meta.ai/muse-code/key"
      and headers[4] == "Authorization: Bearer identity"
      and body == "{}"
  )
  mint_count = mint_count + 1
  if revoked then
    return 401, "{}"
  end
  return 200, psi.json_encode({ api_key = "mint-" .. mint_count })
end
assert(auth.begin_login().user_code == "PUBLIC")
now = 1005
assert(auth.finish_login("check"))
assert(
  auth.has_credentials()
    and storage.get("meta").refresh == "identity"
    and auth.access_token() == "mint-1"
)
now = now + 86400
assert(auth.access_token() == "mint-2")
require("psi.provider_loop").run_turn = function(args, cfg)
  assert(args.model == "muse-spark-1.3" and cfg.url == "https://api.meta.ai/v1/responses")
  assert(cfg.headers[2] == "Authorization: Bearer mint-2")
  local request = cfg.request_body({
    model = args.model,
    messages = {},
    max_tokens = 123,
    system_prompt = "test",
  })
  assert(
    request.store == false and request.instructions == "test" and request.max_output_tokens == 123
  )
  return true
end
assert(meta.run_turn({}))
now, revoked = now + 86400, true
local token, err = auth.access_token()
assert(not token and err:find("expired", 1, true))
return "ok"

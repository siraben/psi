-- Meta Muse device sign-in and Model API key mint, based on Pi's Meta flow.
local device = require("psi.providers.oauth_device")
local prelude = require("psi.prelude")

local function mint(identity_token)
  local status, raw = psi.http_post("https://api.meta.ai/muse-code/key", {
    "Accept: application/json",
    "Content-Type: application/json",
    "x-api-version: 1.0.0",
    "Authorization: Bearer " .. identity_token,
  }, "{}")
  if status == 401 or status == 403 then
    return nil, "Meta session expired or is not eligible. Run /login oauth meta again."
  end
  local body = prelude.safe_json_decode(status and raw or "", nil)
  if status ~= 200 or type(body) ~= "table" or not device.valid_secret(body.api_key) then
    return nil, "Meta did not issue a Model API key. Check account setup and client authorization."
  end
  return { access = body.api_key, refresh = identity_token, expires = (os.time() + 86400) * 1000 }
end

return device.new({
  name = "Meta Muse",
  provider = "meta",
  client_env = "PSI_META_OAUTH_CLIENT_ID",
  device_url = "https://auth.meta.com/oidc/device/authorization/",
  token_url = "https://auth.meta.com/oidc/device/token/",
  verification_hosts = { ["auth.meta.com"] = true, ["www.meta.com"] = true, ["meta.com"] = true },
  default_expiry = 600,
  exchange = function(body)
    return mint(body.access_token)
  end,
  refresh = function(entry)
    return mint(entry.refresh)
  end,
})

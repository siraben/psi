-- GitHub.com device OAuth and Copilot exchange, adapted from Pi.
-- Use only a client authorized for Psi. Never change organization/model policy.
local device = require("psi.providers.oauth_device")
local prelude = require("psi.prelude")

local function exchange(github_token)
  local status, raw = psi.http_get("https://api.github.com/copilot_internal/v2/token", {
    "Accept: application/json",
    "Authorization: Bearer " .. github_token,
    "User-Agent: psi",
  })
  local body = prelude.safe_json_decode(status and raw or "", nil)
  if
    status ~= 200
    or type(body) ~= "table"
    or not device.valid_secret(body.token)
    or not device.positive(body.expires_at)
    or body.expires_at <= os.time()
  then
    return nil,
      "GitHub did not issue a Copilot token. Check the account entitlement and Psi's client authorization."
  end
  return { access = body.token, refresh = github_token, expires = body.expires_at * 1000 }
end

return device.new({
  name = "GitHub Copilot",
  provider = "github-copilot",
  client_env = "PSI_GITHUB_COPILOT_CLIENT_ID",
  device_url = "https://github.com/login/device/code",
  token_url = "https://github.com/login/oauth/access_token",
  verification_hosts = { ["github.com"] = true },
  scope = "read:user",
  exchange = function(body)
    return exchange(body.access_token)
  end,
  refresh = function(entry)
    return exchange(entry.refresh)
  end,
})

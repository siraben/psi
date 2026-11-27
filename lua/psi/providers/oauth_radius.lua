-- Radius device OAuth for the public Radius gateway, based on Pi's Radius flow.
local device = require("psi.providers.oauth_device")
local token_url = "https://radius.pi.dev/v1/oauth/token"

local function token(body, previous_refresh)
  if type(body) ~= "table" or not device.valid_secret(body.access_token) then
    return nil
  end
  local refresh, expires = body.refresh_token or previous_refresh, device.positive(body.expires_in)
  if not device.valid_secret(refresh) or not expires then
    return nil
  end
  return { access = body.access_token, refresh = refresh, expires = (os.time() + expires) * 1000 }
end

return device.new({
  name = "Radius",
  provider = "radius",
  client_env = "PSI_RADIUS_OAUTH_CLIENT_ID",
  device_url = "https://radius.pi.dev/v1/oauth/device",
  token_url = token_url,
  verification_hosts = { ["radius.pi.dev"] = true, ["pi.dev"] = true },
  scope = "gateway offline_access",
  exchange = token,
  refresh = function(entry)
    local status, body = device.post_form(token_url, {
      grant_type = "refresh_token",
      client_id = entry.client,
      refresh_token = entry.refresh,
    })
    return status == 200 and token(body, entry.refresh) or nil
  end,
})

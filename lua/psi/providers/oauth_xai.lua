-- xAI device authorization adapted from Pi's xai OAuth provider.
local storage = require("psi.auth_storage")
local prelude = require("psi.prelude")
local M = {}
local DEVICE_URL = "https://auth.x.ai/oauth2/device/code"
local TOKEN_URL = "https://auth.x.ai/oauth2/token"
local CLIENT_ENV = "PSI_XAI_OAUTH_CLIENT_ID"
local PROVIDER = "xai"
local pending

local function form_value(s)
  return (
    s:gsub("([^a-zA-Z0-9_.~-])", function(c)
      return string.format("%%%02X", c:byte())
    end)
  )
end

local function post(url, params)
  local form = {}
  for k, v in pairs(params) do
    form[#form + 1] = k .. "=" .. form_value(v)
  end
  local status, raw = psi.http_post(
    url,
    { "Content-Type: application/x-www-form-urlencoded", "Accept: application/json" },
    table.concat(form, "&")
  )
  return status, prelude.safe_json_decode(status and raw or "", nil)
end

local function client_id()
  local client = os.getenv(CLIENT_ENV)
  return client and client ~= "" and client or nil
end

local function valid_secret(s)
  return type(s) == "string" and s ~= "" and not s:find("[%c%s]")
end

local function positive(v, default)
  return type(v) == "number" and v > 0 and v < math.huge and v or default
end

function M.begin_login()
  pending = nil
  local client = client_id()
  if not client then
    return nil, "Set " .. CLIENT_ENV .. " to an xAI client authorized for Psi's device sign-in"
  end
  local status, body = post(
    DEVICE_URL,
    { client_id = client, scope = "openid profile email offline_access grok-cli:access api:access" }
  )
  local url = type(body) == "table" and (body.verification_uri_complete or body.verification_uri)
  local allowed = type(url) == "string"
    and not url:find("[%c%s\\]")
    and (url:match("^https://accounts%.x%.ai/") or url:match("^https://auth%.x%.ai/"))
  local expires = type(body) == "table" and positive(body.expires_in)
  if
    status ~= 200
    or not allowed
    or not expires
    or not valid_secret(body.device_code)
    or not valid_secret(body.user_code)
  then
    return nil, "xAI did not issue a valid device code; check the OAuth client registration"
  end
  local now, interval = os.time(), positive(body.interval, 5)
  pending = {
    client = client,
    code = body.device_code,
    expires = now + expires,
    interval = interval,
    next_check = now + interval,
  }
  return { url = url, user_code = body.user_code }
end

local function token(body, client, previous_refresh)
  if type(body) ~= "table" or not valid_secret(body.access_token) then
    return nil
  end
  local refresh = body.refresh_token or previous_refresh
  if not valid_secret(refresh) then
    return nil
  end
  return {
    type = "oauth",
    access = body.access_token,
    refresh = refresh,
    client = client,
    expires = (os.time() + positive(body.expires_in, 3600)) * 1000,
  }
end

function M.finish_login(input)
  if input ~= "check" or not pending or pending.client ~= client_id() then
    return false, "Run /login oauth xai, then /login oauth xai check after approving the device"
  end
  local now = os.time()
  if now >= pending.expires then
    pending = nil
    return false, "Device code expired. Run /login oauth xai again."
  end
  if now < pending.next_check then
    return false, "Wait a few seconds before checking again"
  end
  local status, body = post(TOKEN_URL, {
    grant_type = "urn:ietf:params:oauth:grant-type:device_code",
    client_id = pending.client,
    device_code = pending.code,
  })
  pending.next_check = os.time() + pending.interval
  local err = type(body) == "table" and body.error
  if err == "authorization_pending" then
    return false, "Still waiting for approval; run /login oauth xai check again after approving"
  end
  if err == "slow_down" then
    pending.interval = math.max(pending.interval + 5, positive(body.interval, 0))
    pending.next_check = os.time() + pending.interval
    return false,
      "xAI requested a slower check interval. Try again in "
        .. math.ceil(pending.interval)
        .. " seconds."
  end
  if not status or status >= 500 then
    return false, "xAI device check failed temporarily; try again shortly"
  end
  local entry = status == 200 and token(body, pending.client)
  pending = nil
  if not entry then
    return false, "xAI device authorization failed or was denied; run /login oauth xai again"
  end
  local ok, write_err = storage.set(PROVIDER, entry)
  return ok, ok and "Signed in to xAI" or write_err
end

local function stored()
  local client = client_id()
  local entry = client and storage.get(PROVIDER)
  return type(entry) == "table"
      and entry.type == "oauth"
      and entry.client == client
      and valid_secret(entry.refresh)
      and entry
    or nil
end

function M.has_credentials()
  return stored() ~= nil
end

function M.access_token()
  local entry = stored()
  if not entry then
    return nil, "Run /login oauth xai or set XAI_API_KEY"
  end
  if valid_secret(entry.access) and (tonumber(entry.expires) or 0) > (os.time() + 300) * 1000 then
    return entry.access
  end
  local status, body = post(
    TOKEN_URL,
    { grant_type = "refresh_token", client_id = entry.client, refresh_token = entry.refresh }
  )
  local updated = status == 200 and token(body, entry.client, entry.refresh)
  if not updated then
    return nil, "xAI token refresh failed; run /login oauth xai again if the grant was revoked"
  end
  local ok, err = storage.set(PROVIDER, updated)
  if not ok then
    return nil, err
  end
  return updated.access
end

return M

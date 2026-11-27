-- Cooperative RFC 8628 device sign-in: the browser interaction and the next
-- check are separate slash commands, so waiting never blocks the terminal.
local storage = require("psi.auth_storage")
local prelude = require("psi.prelude")
local M = {}

function M.valid_secret(s)
  return type(s) == "string" and s ~= "" and not s:find("[%c%s]")
end

function M.positive(v, default)
  return type(v) == "number" and v > 0 and v < math.huge and v or default
end

local function form_value(s)
  return (
    s:gsub("([^a-zA-Z0-9_.~-])", function(c)
      return string.format("%%%02X", c:byte())
    end)
  )
end

function M.post_form(url, params)
  local form = {}
  for k, v in pairs(params) do
    form[#form + 1] = form_value(k) .. "=" .. form_value(v)
  end
  local status, raw = psi.http_post(
    url,
    { "Content-Type: application/x-www-form-urlencoded", "Accept: application/json" },
    table.concat(form, "&")
  )
  return status, prelude.safe_json_decode(status and raw or "", nil)
end

function M.new(spec)
  local auth, pending = {}, nil
  local command = "/login oauth " .. spec.provider
  local function client_id()
    local client = os.getenv(spec.client_env)
    return M.valid_secret(client) and client or nil
  end
  local function trusted_url(url)
    if type(url) ~= "string" or url:find("[%c%s\\]") then
      return nil
    end
    local host = url:match("^https://([^/]+)/")
    return host and spec.verification_hosts[host] and url or nil
  end

  function auth.begin_login()
    pending = nil
    local client = client_id()
    if not client then
      return nil, "Set " .. spec.client_env .. " to a client authorized for Psi's device sign-in"
    end
    local status, body = M.post_form(spec.device_url, { client_id = client, scope = spec.scope })
    if status ~= 200 or type(body) ~= "table" then
      return nil, spec.name .. " did not issue a device code; check your OAuth client registration"
    end
    local url = trusted_url(body.verification_uri_complete) or trusted_url(body.verification_uri)
    local expires = M.positive(body.expires_in, spec.default_expiry)
    if
      not url
      or not expires
      or not M.valid_secret(body.device_code)
      or not M.valid_secret(body.user_code)
    then
      return nil, spec.name .. " returned an invalid device authorization response"
    end
    local now, interval = os.time(), M.positive(body.interval, 5)
    pending = {
      client = client,
      code = body.device_code,
      expires = now + expires,
      interval = interval,
      next_check = now + interval,
    }
    return { url = url, user_code = body.user_code }
  end

  function auth.finish_login(input)
    if input ~= "check" or not pending or pending.client ~= client_id() then
      return false, "Run " .. command .. ", then " .. command .. " check after approving the device"
    end
    local now = os.time()
    if now >= pending.expires then
      pending = nil
      return false, "Device code expired. Run " .. command .. " again."
    end
    if now < pending.next_check then
      return false, "Wait a few seconds before checking again"
    end
    local status, body = M.post_form(spec.token_url, {
      grant_type = "urn:ietf:params:oauth:grant-type:device_code",
      client_id = pending.client,
      device_code = pending.code,
    })
    pending.next_check = os.time() + pending.interval
    local err = type(body) == "table" and body.error
    if err == "authorization_pending" then
      return false, "Still waiting for approval; run " .. command .. " check again after approving"
    end
    if err == "slow_down" then
      pending.interval = math.max(pending.interval + 5, M.positive(body.interval, 0))
      pending.next_check = os.time() + pending.interval
      return false,
        spec.name .. " requested a slower check interval. Try again in " .. math.ceil(
          pending.interval
        ) .. " seconds."
    end
    if not status or status >= 500 then
      return false, spec.name .. " device check failed temporarily; try again shortly"
    end
    local client = pending.client
    pending = nil
    if status ~= 200 or type(body) ~= "table" or not M.valid_secret(body.access_token) then
      return false,
        spec.name .. " device authorization failed or was denied; run " .. command .. " again"
    end
    local entry, exchange_err = spec.exchange(body)
    if not entry then
      return false, exchange_err or "Invalid sign-in token; run " .. command .. " again"
    end
    entry.type, entry.client = "oauth", client
    local ok, write_err = storage.set(spec.provider, entry)
    return ok, ok and ("Signed in to " .. spec.name) or write_err
  end

  local function valid(entry)
    local client = client_id()
    return client ~= nil
      and type(entry) == "table"
      and entry.type == "oauth"
      and entry.client == client
      and M.valid_secret(entry.refresh)
  end

  function auth.has_credentials(candidate)
    return valid(candidate or storage.get(spec.provider))
  end

  function auth.access_token(candidate)
    if not candidate then
      local read_err
      candidate, read_err = storage.get(spec.provider)
      if read_err then
        return nil, read_err
      end
    end
    local updated, err = storage.ensure_oauth(spec.provider, candidate, valid, function(current)
      local replacement, refresh_err = spec.refresh(current)
      if not replacement then
        return nil, refresh_err or ("Token refresh failed; try " .. command .. " again")
      end
      replacement.type, replacement.client = "oauth", current.client
      return replacement
    end)
    return updated and updated.access or nil, err
  end
  return auth
end

return M

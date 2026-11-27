-- Meta Model API via its OpenAI-compatible Responses endpoint.
local auth = require("psi.providers.oauth_meta")
local storage = require("psi.auth_storage")
local responses = require("psi.providers.openai_codex")
local registry = require("psi.api_registry")
local M = {}
local auth_spec =
  { env = "META_API_KEY", oauth = auth.access_token, has_oauth = auth.has_credentials }

function M.has_auth()
  return storage.provider_has_auth("meta", auth_spec)
end

local function config(model)
  local key, err = storage.resolve_provider("meta", auth_spec)
  if not key then
    return nil, err or "Run /login oauth meta or set META_API_KEY"
  end
  if key:find("[%c%s]") then
    return nil, "Invalid Meta credential"
  end
  return {
    model = registry.resolve_model("meta", model),
    provider_name = "meta",
    api_name = "meta-responses",
    url = "https://api.meta.ai/v1/responses",
    request_body = responses.responses_request,
    headers = {
      "Content-Type: application/json",
      "Authorization: Bearer " .. key,
      "Accept: text/event-stream",
    },
  }
end

function M.run_turn(opts)
  local cfg, err = config(opts.model)
  if not cfg then
    return false, err
  end
  return responses.run_responses_turn(opts, cfg)
end

function M.complete_text(opts)
  local cfg, err = config(opts.model)
  if not cfg then
    return false, err
  end
  return responses.complete_responses_text(opts, cfg)
end

return M

-- Meta Model API via its OpenAI-compatible Responses endpoint.
local auth = require("psi.providers.oauth_meta")
local storage = require("psi.auth_storage")
local responses = require("psi.providers.openai_codex")
local registry = require("psi.api_registry")
local M = {}

function M.has_auth()
  return storage.has_api_key("meta", "META_API_KEY") or auth.has_credentials()
end

local function config(model)
  local key, err = storage.resolve_api_key("meta", "META_API_KEY")
  if not key then
    key, err = auth.access_token()
  end
  if not key or key:find("[%c%s]") then
    return nil, err or "Invalid Meta credential"
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

-- Meta Model API via its OpenAI-compatible Responses endpoint.
local auth = require("psi.providers.oauth_meta")
local storage = require("psi.auth_storage")
local responses = require("psi.providers.openai_codex")
local registry = require("psi.api_registry")
local prelude = require("psi.prelude")
local M = {}

function M.has_auth()
  return storage.has_api_key("meta", "META_API_KEY") or auth.has_credentials()
end

local function request(args)
  local body = { model = args.model, input = args.messages, store = false, stream = true }
  if args.system_prompt and args.system_prompt ~= "" then
    body.instructions = prelude.sanitize_surrogates(args.system_prompt)
  end
  if args.max_tokens then
    body.max_output_tokens = args.max_tokens
  end
  if args.tool_specs and #args.tool_specs > 0 then
    body.tools = args.tool_specs
  end
  return body
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
    request_body = request,
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

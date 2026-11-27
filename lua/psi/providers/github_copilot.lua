-- GitHub.com Copilot Responses transport. Only forward tokens to known
-- first-party hosts, even if a token advertises a different proxy endpoint.
local auth = require("psi.providers.oauth_github_copilot")
local responses = require("psi.providers.openai_codex")
local registry = require("psi.api_registry")
local M = { has_auth = auth.has_credentials }
local endpoints = {
  ["proxy.individual.githubcopilot.com"] = "api.individual.githubcopilot.com",
  ["proxy.business.githubcopilot.com"] = "api.business.githubcopilot.com",
  ["proxy.enterprise.githubcopilot.com"] = "api.enterprise.githubcopilot.com",
  ["proxy.githubcopilot.com"] = "api.githubcopilot.com",
}

local function config(model)
  local token, err = auth.access_token()
  if not token then
    return nil, err
  end
  local proxy = (";" .. token):match(";proxy%-ep=([^;]+)")
  local host = proxy and endpoints[proxy]
    or not proxy and endpoints["proxy.individual.githubcopilot.com"]
  if not host then
    return nil, "The GitHub Copilot credential advertises an unsupported gateway"
  end
  return {
    model = registry.resolve_model("github-copilot", model),
    provider_name = "github-copilot",
    api_name = "copilot-responses",
    url = "https://" .. host .. "/responses",
    request_body = responses.responses_request,
    headers = {
      "Content-Type: application/json",
      "Accept: text/event-stream",
      "User-Agent: psi",
      "Authorization: Bearer " .. token,
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

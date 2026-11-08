-- Capture-only configuration: direct Anthropic Opus 5.5, actual high effort.
-- No credentials, request messages, headers, or thinking text are logged.
return function(psi)
  if psi._capture_anthropic_high then return end
  psi._capture_anthropic_high = true
  require("psi.api_registry").register_model("anthropic/claude-opus-5-5", {
    provider = "anthropic", api = "anthropic-messages", reasoning = true,
    context_window = 1000000, max_output_tokens = 128000,
    input = { "text", "image" }
  })
  local function append(path, value)
    local f = assert(io.open(path, "a")); f:write(psi.json_encode(value), "\n"); f:close()
  end
  psi.events.on("before-provider-request", function(evt)
    if evt.provider == "anthropic" and evt.model == "claude-opus-5-5" then
      evt.body.thinking = { type = "adaptive" }
      evt.body.output_config = { effort = "high" }
      evt.body.max_tokens = 32768
    end
  end)
  local begin = psi.http_stream_begin
  psi.http_stream_begin = function(url, headers, encoded)
    if url == "https://api.anthropic.com/v1/messages" then
      local body = psi.json_decode(encoded)
      assert(body.model == "claude-opus-5-5")
      assert(body.thinking and body.thinking.type == "adaptive")
      assert(body.output_config and body.output_config.effort == "high")
      append("/boot/home/anthropic-high-request-audit.jsonl", {
        provider = "anthropic", endpoint = url, model = body.model,
        thinking = body.thinking, output_config = body.output_config,
        max_tokens = body.max_tokens, audit_stage = "serialized_http_stream_begin",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
      })
    end
    return begin(url, headers, encoded)
  end
  psi.events.on("turn-end", function(evt)
    local f = assert(io.open("/boot/home/anthropic-high-turn-finished", "w"))
    f:write("finished\n"); f:close()
  end)
end

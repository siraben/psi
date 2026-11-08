--[==[psi-test
expect = "message_delta:message_delta"
]==]
local stream_parser = require("psi.stream_parser")
local parser = stream_parser.sse_parser()
local seen = {}
local opts = {
  multi_data = true,
  on_event = function(event, data)
    local decoded = psi.json_decode(data)
    seen[#seen + 1] = event .. ":" .. tostring(decoded.type)
  end,
}
stream_parser.push_sse(parser, "event: message_delta\ndata: {\"type\":\n", opts)
assert(#seen == 0, "incomplete event must not dispatch")
stream_parser.push_sse(parser, "data: \"message_delta\"}\n\n", opts)
return table.concat(seen, "|")

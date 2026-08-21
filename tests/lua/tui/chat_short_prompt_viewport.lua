--[==[psi-test
expect = "1|4|1|true|true|true"
]==]
local rt = require("psi.tui_runtime")
local snapshots = rt._debug_chat_redraw_sequence({
  { kind = "set_input", text = "one\ntwo\nthree\nfour\nfive\nsix" },
}, { width = 20, height = 4 })
local snapshot = snapshots[1]
local lines = {}
for i = 1, 40 do
  lines[#lines + 1] = string.format("transcript-%02d", i)
end
local long = rt._debug_chat_redraw_sequence({
  { kind = "assistant", text = "```text\n" .. table.concat(lines, "\n") .. "\n```" },
}, { width = 40, height = 4 })[1]
assert(long.output:find("transcript-01", 1, true))
assert(long.output:find("transcript-40", 1, true))
assert(long.cursor_offset < 4)

return table.concat({
  snapshot.input_max_rows,
  snapshot.live_rows,
  snapshot.cursor_offset,
  tostring(snapshot.output:find("six", 1, true) ~= nil),
  tostring(snapshot.output:find("one", 1, true) == nil),
  tostring(snapshot.output:find("\27[?25h", 1, true) ~= nil),
}, "|")

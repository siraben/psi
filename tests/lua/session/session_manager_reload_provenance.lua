--[==[psi-test
expect = "ok"
cwd = "provenance-reload"
files = [ { path = "sample.txt", text = "hello" } ]
]==]
local session = require("psi.session_manager")
local commands = require("psi.slash_commands")
for _ = 1, 2 do
  commands.handle("/reload")
  session.reset_file_ops()
  assert(require("psi.tools").dispatch("read", { path = "sample.txt" }).ok)
  local read, modified = session.pending_file_ops()
  assert(#read == 1 and read[1] == "sample.txt" and #modified == 0)
end
return "ok"

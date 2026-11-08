--[==[psi-test
requires = ["mcp"]
expect = "ok"
]==]
local clipboard = require("psi.clipboard")
if not require("psi.platform").is_windows() then
  local path = TMP .. "/clipboard-reader"
  assert(psi.file_write(path, "#!/bin/sh\nprintf 'clipboard text'\nprintf 'diagnostic' >&2\n"))
  assert(psi.file_chmod(path, 448))
  local begin = psi.process_begin_argv
  psi.process_begin_argv = function(argv)
    assert(argv[1] == "sh" and argv[4] == "psi-clipboard")
    local copy = {}
    for i, arg in ipairs(argv) do
      copy[i] = arg
    end
    copy[5] = path
    return begin(copy)
  end
  local captured = clipboard.read_system({ env = {}, is_windows = false, timeout_ms = 2000 })
  assert(captured == "clipboard text", "stderr is not clipboard data")
  assert(psi.file_write(path, "#!/bin/sh\nexec 1>&- 2>&-\n/bin/sleep 5\n"))
  local started = psi.time_ms()
  local timed_out = clipboard.read_system({ env = {}, is_windows = false, timeout_ms = 100 })
  psi.process_begin_argv = begin
  assert(timed_out == nil and psi.time_ms() - started < 2500, "reader deadline covers early EOF")
end
return "ok"

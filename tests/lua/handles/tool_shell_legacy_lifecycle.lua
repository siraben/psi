--[==[psi-test
expect = "ok"
]==]
local shell = require("psi.tool_shell")
local sched = require("psi.sched")
local platform = require("psi.platform")
local coroutine_mode, launch_error, aborted = false, false, false
local expected_input, launches, finishes, terminations, progress = nil, 0, 0, 0, {}
local handle = {}
sched.in_coroutine = function()
  return coroutine_mode
end
local function run(input)
  assert(input == expected_input)
  return { output = "failure output", status = 7, truncated = true }
end
local function begin(input)
  assert(input == expected_input)
  launches = launches + 1
  if launch_error then
    return nil
  end
  return handle
end
psi.process_run, psi.process_run_argv = run, run
psi.process_begin, psi.process_begin_argv = begin, begin
psi.is_aborted = function()
  return aborted
end
psi.process_terminate = function(h)
  assert(h == handle)
  terminations = terminations + 1
end
psi.process_finish = function(h)
  assert(h == handle)
  finishes = finishes + 1
  return run(expected_input)
end
sched.proc_poll = function(h, ms)
  assert(h == handle and ms == 50)
  return "chunk", true
end
psi.tool_progress = function(id, chunk)
  progress[#progress + 1] = id .. ":" .. chunk
end
local argv = { "literal", "space ' quote" }
for _, shell_argv in ipairs({ false, argv }) do
  platform.shell_argv = function()
    return shell_argv or nil
  end
  for _, mode in ipairs({ false, true }) do
    coroutine_mode = mode
    for _, use_argv in ipairs({ false, true }) do
      expected_input = use_argv and argv or shell_argv or "command"
      local result
      if use_argv then
        result = shell.run_tool_argv("test", argv, "path", false, { tool_call_id = "id" })
      else
        result = shell.run_tool("test", "command", "path", false, { tool_call_id = "id" })
      end
      assert(not result.ok and result.extras.status == 7 and result.extras.truncated)
      assert(result.extras.output == "failure output" and result.extras.path == "path")
      assert(result.extras[use_argv and "argv" or "command"] ~= nil)
    end
  end
end
assert(launches == 4 and finishes == 4 and #progress == 4 and progress[1] == "id:chunk")
coroutine_mode, launch_error = true, true
expected_input = argv
assert(shell.process_result("command").output == "process_begin failed")
assert(shell.process_result_argv(argv).output == "process_begin_argv failed")
launch_error, aborted = false, true
shell.process_result_argv(argv, "abort")
assert(terminations == 1 and finishes == 5 and progress[5] == "abort:chunk")
return "ok"

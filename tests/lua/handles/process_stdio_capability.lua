--[==[psi-test
expect = "ok"
]==]
local info = psi.runtime_info()
assert(type(info.mcp) == "boolean")
assert((type(psi.process_begin_stdio_argv) == "function") == info.mcp)
assert(info.mcp or psi.process_begin_stdio_argv == nil)
return "ok"

--[==[psi-test
expect = "Use psi here|true"
]==]
local ansi = require("psi.ansi")
ansi.enabled = true
ansi.color_enabled = true
local rendered = require("psi.markdown").render_line("Use `psi` here")
local plain = (rendered:gsub("\27%[[%d;]*m", ""))
return plain .. "|" .. tostring(rendered:find("\27[", 1, true) ~= nil)

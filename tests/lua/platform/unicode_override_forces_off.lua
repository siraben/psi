--[==[psi-test
expect = "supported=false"
env = { LC_ALL = "", LC_CTYPE = "", LANG = "en_US.UTF-8", PSI_UNICODE = "0" }
]==]
-- PSI_UNICODE wins over a perfectly good UTF-8 locale, for terminals whose
-- font lacks the glyphs even though the charset is fine.
local platform = require("psi.platform")
local glyphs = require("psi.glyphs")
local spinner = glyphs.spinner
require("psi.tui_status")
glyphs.set_enabled(true)
assert(glyphs.spinner == spinner)
glyphs.set_enabled(false)
assert(glyphs.spinner == spinner and spinner[1] == "|" and #spinner == 4)
local layout = require("psi.tui_layout").input_layout_table({ height = 24 })
assert(layout.prefix_first == "" and layout.prefix_rest == "")
return "supported=" .. tostring(platform.unicode_supported())

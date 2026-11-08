--[==[psi-test
expect = "ok"
]==]
local ansi = require("psi.ansi")
local glyphs = require("psi.glyphs")
local markdown = require("psi.markdown")
local lines = { "# Heading", "**bold** and `code`", "> quote", "- item", "---" }
local function check()
  for _, line in ipairs(lines) do
    assert(markdown.render_line(line, false) == markdown.render(line), line)
  end
  assert(markdown.render_line("code", true) == markdown.render("```\ncode"):match("[^\n]+$"))
end
ansi.enabled, ansi.color_enabled = true, true
glyphs.set_enabled(true)
check()
local heading = markdown.render_line(lines[1], false)
ansi.set_code_map({ ["md-heading"] = "35", ["36"] = "32" })
check()
assert(
  markdown.render_line(lines[1], false) ~= heading,
  "theme generation invalidates styled lines"
)
ansi.enabled = false
check()
assert(not markdown.render_line(lines[1], false):find("\27", 1, true))
ansi.enabled = true
check()
ansi.color_enabled = false
check()
ansi.color_enabled = true
check()
glyphs.set_enabled(false)
check()
assert(markdown.render_line("> quote", false):find("| ", 1, true))
glyphs.set_enabled(true)
check()
markdown.clear_render_cache()
check()
return "ok"

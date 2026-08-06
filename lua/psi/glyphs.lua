-- Terminal symbols selected independently of ANSI/color support.

local M = {}
local platform = require("psi.platform")

-- name = { preferred, ascii }
local GLYPHS = {
  bullet = { "•", "*" },
  quote_bar = { "│ ", "| " },
  hrule = { "─", "-" },
  vbar = { "│", "|" },
  corner_up = { "╰─", "\\-" },
  arrow_return = { "↳", ">" },
  prompt_caret = { "›", ">" },
  arrow_up = { "↑", "^" },
  arrow_down = { "↓", "v" },
  dash = { "—", "--" },
  ellipsis = { "…", "..." },
  radio_on = { "◉", "(*)" },
  radio_off = { "○", "( )" },
  dot = { "•", "*" },
}

local SPINNERS = {
  { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  { "|", "/", "-", "\\" },
}

function M.set_enabled(on)
  M.enabled = on and true or false
  local index = M.enabled and 1 or 2
  for name, forms in pairs(GLYPHS) do
    M[name] = forms[index]
  end
  M.spinner = M.spinner or {}
  for i = #M.spinner, 1, -1 do
    M.spinner[i] = nil
  end
  for i, frame in ipairs(SPINNERS[index]) do
    M.spinner[i] = frame
  end
end

-- Re-read the environment. Exposed for tests and for callers that change
-- locale or the override after startup.
function M.refresh()
  M.set_enabled(platform.unicode_supported())
end

M.refresh()

return M

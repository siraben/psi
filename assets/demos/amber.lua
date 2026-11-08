return function(psi)
  local bg = 52 -- dark warm (deep maroon-brown)
  psi.theme.register("amber", {
    tui = {
      header           = { fg = 214, bg = bg },
      accent           = { fg = 220, bg = bg },
      text             = { fg = 223, bg = bg },
      warning          = { fg = 208, bg = bg },
      success          = { fg = 178, bg = bg },
      error            = { fg = 202, bg = bg },
      chrome           = { fg = 137, bg = bg },
      thinking_off     = { fg = 94,  bg = bg },
      thinking_minimal = { fg = 130, bg = bg },
      thinking_low     = { fg = 136, bg = bg },
      thinking_medium  = { fg = 172, bg = bg },
      thinking_high    = { fg = 214, bg = bg },
      thinking_xhigh   = { fg = 208, bg = bg },
      thinking_max     = { fg = 202, bg = bg },
    },
  })
  psi.theme.use("amber")
end

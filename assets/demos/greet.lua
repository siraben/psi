return function(psi)
  psi.commands.register("greet", {
    description = "Print a greeting",
    argument_hint = "[name]",
    handler = function(rest)
      local name = (rest or ""):match("^%s*(.-)%s*$")
      if name == "" then name = "world" end
      return psi.records.new_command_action("print", "Hello, " .. name .. "!")
    end,
  })
end

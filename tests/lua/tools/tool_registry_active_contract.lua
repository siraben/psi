--[==[psi-test
expect = "ok"
]==]
local tools = require("psi.tools")
local records = require("psi.records")
local helpers = require("psi.tool_helpers")
local calls = {}
for _, name in ipairs({ "contract_a", "contract_b" }) do
  helpers.register({
    name = name,
    description = name,
    prompt_snippet = name,
    input_schema = helpers.schema_object({}, {}),
    impl = function(_, meta)
      calls[#calls + 1] = name
      assert(meta.tool_call_id == "contract")
      return records.tool_success(name, {})
    end,
  })
end
local all = tools.all()
assert(tools.active() == all)
for _, allowlist in ipairs({ {}, { "contract_b", "unknown", "contract_a", "contract_b" } }) do
  tools.set_active(allowlist)
  local names, active, specs = tools.get_active(), tools.active(), tools.select_specs("ignored")
  assert(#names == #active and #active == #specs)
  for i, name in ipairs(names) do
    assert(active[i].name == name and specs[i].name == name)
  end
  local prompt = require("psi.prompt").system_prompt()
  for _, name in ipairs({ "contract_a", "contract_b" }) do
    local allowed = #allowlist > 0
    assert((prompt:find(name, 1, true) ~= nil) == allowed)
    local result = tools.dispatch(name, {}, { tool_call_id = "contract" })
    assert(result.ok == allowed)
    if not allowed then
      assert(result.error == "Tool " .. name .. " not found")
    end
  end
  if #allowlist > 0 then
    assert(table.concat(names, ",") == "contract_a,contract_b")
  end
end
assert(table.concat(calls, ",") == "contract_a,contract_b")
tools.set_active(nil)
assert(tools.active() == all)
local after = 0
tools.clear_hooks()
tools.add_before_hook(function(name, _, meta)
  assert(meta.tool_call_id == "contract")
  if name == "contract_a" then
    return records.tool_success(name, { intercepted = true })
  end
end)
tools.add_after_hook(function()
  after = after + 1
end)
assert(tools.dispatch("contract_a", {}, { tool_call_id = "contract" }).extras.intercepted)
assert(after == 0 and #calls == 2)
assert(tools.dispatch("contract_b", {}, { tool_call_id = "contract" }).ok)
assert(after == 1 and #calls == 3)
assert(tools.dispatch("unknown", {}, { tool_call_id = "contract" }).error == "unknown tool")
assert(after == 2)
return "ok"

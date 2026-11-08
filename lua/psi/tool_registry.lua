-- psi.tool_registry: declarative tool registration and dispatch.
--
-- Each tool is a records.Tool; the registry owns the list. Registered
-- tools are reachable via:
--   M.register(tool)
--   M.all() / M.find(name)
--   M.select_specs(user_text) -- provider tool schemas
--   M.dispatch(name, input)   -- returns ToolResult record
--   M.dispatch_alist(n, i)    -- returns alist (entry used by vm.c)
--
-- IMPORTANT: to invoke a tool and run the registered before/after
-- hook chain, call M.dispatch(name, input) (or the shim
-- psi.tool_call(name, input) on the global). The raw `tool.impl`
-- field on a Tool record is the *unhooked* implementation — calling
-- it directly (e.g. `find("read").impl(...)`) bypasses permission
-- gating, redaction, and any transformations extensions have
-- installed. Treat `impl` as an internal slot.

local records = require("psi.records")

local M = {}

local registry = {}
local before_hooks = {}
local after_hooks = {}

function M.register(tool)
  for i, existing in ipairs(registry) do
    if existing.name == tool.name then
      registry[i] = tool
      return
    end
  end
  registry[#registry + 1] = tool
end

function M.all()
  return registry
end

function M.find(name)
  for _, t in ipairs(registry) do
    if t.name == name then
      return t
    end
  end
  return nil
end

-- nil allows all tools; an empty allowlist disables every tool without
-- unregistering records. Names, prompt records, schemas and dispatch share it.
local active_allowlist = nil

function M.set_active(names)
  if names == nil then
    active_allowlist = nil
    return
  end
  if type(names) ~= "table" then
    return
  end
  local set = {}
  for _, n in ipairs(names) do
    if type(n) == "string" and n ~= "" then
      set[n] = true
    end
  end
  active_allowlist = set
end

local function is_active(name)
  return active_allowlist == nil or active_allowlist[name] == true
end

local function active_records()
  if active_allowlist == nil then
    return registry
  end
  local out = {}
  for _, tool in ipairs(registry) do
    if is_active(tool.name) then
      out[#out + 1] = tool
    end
  end
  return out
end

function M.get_active()
  local out = {}
  for i, tool in ipairs(active_records()) do
    out[i] = tool.name
  end
  return out
end

function M.active()
  return active_records()
end

-- C-side schema serialization; user_text is retained for host compatibility.
function M.select_specs(user_text)
  local out = {}
  for i, tool in ipairs(active_records()) do
    out[i] = records.tool_to_alist(tool)
  end
  return out
end

-- Hook registration:
--   before(name, input) may return nil (proceed), a ToolResult record
--     (replace the dispatch — tool impl is NOT called), or raise.
--     Common uses: permission gating, dry-run interception, logging.
--   after(name, input, result) may return a replacement ToolResult or
--     nil (keep result). Common uses: redaction, output transformation.
function M.add_before_hook(fn)
  before_hooks[#before_hooks + 1] = fn
end
function M.add_after_hook(fn)
  after_hooks[#after_hooks + 1] = fn
end
function M.clear_hooks()
  before_hooks = {}
  after_hooks = {}
end

-- Optional meta (tool_call_id, provider, model) passes through hooks and impl.
-- Before-hook interception returns immediately, without running after hooks.
function M.dispatch(name, input, meta)
  input = input or {}
  if not is_active(name) then
    return records.tool_failure(name, "Tool " .. tostring(name) .. " not found")
  end
  for _, hook in ipairs(before_hooks) do
    local intercept = hook(name, input, meta)
    if intercept ~= nil then
      return intercept
    end
  end

  local tool = M.find(name)
  local result
  if not tool then
    result = records.tool_failure(name, "unknown tool")
  else
    result = tool.impl(input, meta)
  end

  for _, hook in ipairs(after_hooks) do
    local replaced = hook(name, input, result, meta)
    if replaced ~= nil then
      result = replaced
    end
  end
  return result
end

function M.dispatch_alist(name, input, meta)
  return records.tool_result_to_alist(M.dispatch(name, input, meta))
end

-- guardrail helpers used by tool impls
function M.require_string(input, key)
  local v = input[key]
  if type(v) == "string" and #v > 0 then
    return v
  end
  return nil
end

function M.optional_string(input, key, default)
  local v = input[key]
  if type(v) == "string" then
    return v
  end
  return default
end

function M.optional_number(input, key, default)
  local v = input[key]
  if type(v) == "number" then
    return v
  end
  return default
end

function M.optional_boolean(input, key, default)
  local v = input[key]
  if v == true then
    return true
  end
  if v == false then
    return false
  end
  return default
end

return M

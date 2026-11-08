-- Width-aware, stateful tool execution component.

local ansi = require("psi.ansi")
local component = require("psi.tui_component")
local keybindings = require("psi.keybindings")
local presentation = require("psi.tool_presentation")

local M = {
  BG_PENDING = presentation.BG_PENDING,
  BG_SUCCESS = presentation.BG_SUCCESS,
  BG_ERROR = presentation.BG_ERROR,
  render_call = presentation.render_call,
  render_result = presentation.render_result,
  output_line_count = presentation.output_line_count,
}

local function bg_fn(bg_code)
  return function(line)
    return presentation.bg_line(bg_code, line)
  end
end

local ToolExecution = {}
ToolExecution.__index = ToolExecution

local function component_bg_code(self)
  if self.result == nil or self.is_partial then
    return M.BG_PENDING
  end
  return self.result.ok and M.BG_SUCCESS or M.BG_ERROR
end

local function update_display(self)
  -- Result updates must not recompute an unchanged call preview.
  local cache = self.call_cache
  local call_text
  if
    cache ~= nil
    and cache.tool == self.tool
    and cache.input == self.input
    and cache.frame == self.frame
    and cache.before_text == (self.frame and self.frame.before_text or nil)
    and cache.expanded == self.expanded
    and cache.style_generation == ansi.generation()
    and cache.style_ansi == ansi.enabled
    and cache.style_color == ansi.color_enabled
    and cache.keybinding_revision == keybindings.revision()
  then
    call_text = cache.text
  else
    call_text = presentation.format_call(self.tool, self.input, self.frame, self.expanded)
    self.call_cache = {
      tool = self.tool,
      input = self.input,
      frame = self.frame,
      before_text = self.frame and self.frame.before_text or nil,
      expanded = self.expanded,
      style_generation = ansi.generation(),
      style_ansi = ansi.enabled,
      style_color = ansi.color_enabled,
      keybinding_revision = keybindings.revision(),
      text = call_text,
    }
  end
  self.box:set_bg_fn(bg_fn(component_bg_code(self)))
  self.call_text:set_text(call_text or "")
  if self.result ~= nil then
    local result_text =
      presentation.format_result(self.tool, self.result, self.frame, self.expanded, self.is_partial)
    self.result_text:set_text(
      result_text ~= nil and result_text ~= "" and ("\n" .. result_text) or ""
    )
  else
    self.result_text:set_text("")
  end
  self.style_generation = ansi.generation()
  self.style_ansi = ansi.enabled
  self.style_color = ansi.color_enabled
  self.keybinding_revision = keybindings.revision()
  self.generation = (self.generation or 0) + 1
end

function ToolExecution:set_input(input, frame)
  self.input = type(input) == "table" and input or {}
  self.frame = frame or self.frame
  update_display(self)
end

function ToolExecution:set_result(result, is_partial)
  self.result = result
  self.is_partial = not not is_partial
  update_display(self)
end

function ToolExecution:set_expanded(expanded)
  expanded = not not expanded
  if self.expanded == expanded then
    return
  end
  self.expanded = expanded
  self.call_cache = nil
  update_display(self)
end

function ToolExecution:render(width)
  if
    self.style_generation ~= ansi.generation()
    or self.style_ansi ~= ansi.enabled
    or self.style_color ~= ansi.color_enabled
    or self.keybinding_revision ~= keybindings.revision()
  then
    self:invalidate()
  end
  return self.box:render(width)
end

function ToolExecution:invalidate()
  self.call_cache = nil
  update_display(self)
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local obj = setmetatable({
    id = opts.id,
    tool = opts.tool or "tool",
    input = type(opts.input) == "table" and opts.input or {},
    frame = opts.frame,
    result = opts.result,
    is_partial = not not opts.is_partial,
    expanded = not not opts.expanded,
    box = component.box(1, 1, bg_fn(M.BG_PENDING)),
    call_text = component.text("", 0, 0),
    result_text = component.text("", 0, 0),
    generation = 0,
  }, ToolExecution)
  obj.box:add_child(obj.call_text)
  obj.box:add_child(obj.result_text)
  update_display(obj)
  return obj
end

return M

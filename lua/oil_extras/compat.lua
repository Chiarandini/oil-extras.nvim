--- Every place oil-extras relies on oil.nvim internals rather than its
--- documented API, kept in one file. An Oil update that moves one of these
--- breaks here, and `:checkhealth oil_extras` reports which.
local M = {}

--- The error `oil.save` reports when the confirmation is declined.
M.CANCELED = "Canceled"

--- The filetype Oil gives its confirmation window, and nothing else.
M.CONFIRM_FILETYPE = "oil_preview"

--- An entry that names something on disk: not `../`, and not a line typed
--- but not yet written, which Oil gives id 0.
---@param entry? table
---@return boolean
function M.is_real_entry(entry)
  return entry ~= nil and entry.name ~= ".." and entry.id ~= nil and entry.id ~= 0
end

--- The name as currently typed on the line, before a save renames it.
---@param entry table
---@return string
function M.typed_name(entry)
  return entry.parsed_name or entry.name
end

---@return table columns the columns Oil is rendering now
function M.columns()
  return require("oil.config").columns
end

---@return boolean
function M.show_hidden()
  return require("oil.config").view_options.show_hidden
end

---@param buf integer
---@return boolean rendering true while Oil rewrites the buffer
function M.rendering(buf)
  return vim.b[buf].oil_rendering == true
end

---@param buf integer
---@return boolean dirty true when Oil's watcher has marked the buffer for re-render
function M.dirty(buf)
  return vim.b[buf].oil_dirty ~= nil
end

--- Where Oil puts the cursor the next time it renders `bufname`.
---@param bufname string
---@param name string
function M.set_last_cursor(bufname, name)
  require("oil.view").set_last_cursor(bufname, name)
end

--- Each assumption that can be checked without an Oil buffer open.
---@return { what: string, ok: boolean }[]
function M.check()
  local function holds(fn)
    local ok, res = pcall(fn)
    return ok and res == true
  end
  return {
    {
      what = "oil.config.columns is a list",
      ok = holds(function() return type(require("oil.config").columns) == "table" end),
    },
    {
      what = "oil.config.view_options.show_hidden is a boolean",
      ok = holds(function()
        return type(require("oil.config").view_options.show_hidden) == "boolean"
      end),
    },
    {
      what = "oil.view.set_last_cursor exists",
      ok = holds(function() return type(require("oil.view").set_last_cursor) == "function" end),
    },
    {
      what = "oil.actions.copy_to_system_clipboard exists",
      ok = holds(function()
        return type(require("oil.actions").copy_to_system_clipboard.callback) == "function"
      end),
    },
  }
end

return M

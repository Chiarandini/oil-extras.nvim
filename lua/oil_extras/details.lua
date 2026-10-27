--- Size and mtime as virtual text after each Oil entry.
---
--- Oil can show these as real columns, but a column with `require_stat`
--- makes Oil stat every entry before it renders anything, so a large
--- directory sits empty for a beat. Here the listing renders at once and the
--- stats are fetched asynchronously, each row's text painting in as its stat
--- returns.
---
--- `User OilEnter` fires only on a buffer's first render; every later render
--- (Oil's watcher, a save, a sort, the hidden toggle) replaces all the lines
--- and drops the marks, so the buffer's line changes trigger a repaint too.

local compat = require("oil_extras.compat")

local M = {}

local ns = vim.api.nvim_create_namespace("oil_extras.details")
local hl_group = "OilExtrasDetails"
local enabled = false

local function format_size(bytes)
  if bytes >= 1e9 then return string.format("%6.1fG", bytes / 1e9) end
  if bytes >= 1e6 then return string.format("%6.1fM", bytes / 1e6) end
  if bytes >= 1e3 then return string.format("%6.1fk", bytes / 1e3) end
  return string.format("%5dB ", bytes)
end

--- Oil's own mtime format: "Mon DD HH:MM" this year, "Mon DD  YYYY" before.
local current_year
local function format_mtime(sec)
  if not sec then return "" end
  current_year = current_year or os.date("%Y")
  if os.date("%Y", sec) ~= current_year then
    return os.date("%b %d  %Y", sec)
  end
  return os.date("%b %d %H:%M", sec)
end

--- True when Oil is already showing size or mtime as a real column.
local function real_columns_shown()
  for _, col in ipairs(compat.columns()) do
    local name = type(col) == "table" and col[1] or col
    if name == "size" or name == "mtime" then return true end
  end
  return false
end

-- Per-buffer pass counter: a pass whose stats resolve after a newer render
-- has started must not paint onto the new lines.
local generation = {}

---@param bufnr integer
function M.decorate(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local oil = require("oil")
  local dir = oil.get_current_dir(bufnr)
  if not dir then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local gen = (generation[bufnr] or 0) + 1
  generation[bufnr] = gen
  if real_columns_shown() then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Line up the text at one screen column: the widest entry line plus a
  -- two-space gutter. strdisplaywidth counts wide icons and multibyte names.
  local widths, max_w = {}, 0
  for lnum = 1, #lines do
    if compat.is_real_entry(oil.get_entry_on_line(bufnr, lnum)) then
      local w = vim.fn.strdisplaywidth(lines[lnum])
      widths[lnum] = w
      if w > max_w then max_w = w end
    end
  end

  for lnum, w in pairs(widths) do
    local entry = oil.get_entry_on_line(bufnr, lnum)
    local pad = string.rep(" ", (max_w - w) + 2)
    vim.uv.fs_stat(dir .. entry.name, vim.schedule_wrap(function(err, stat)
      if err or not stat then return end
      if not vim.api.nvim_buf_is_valid(bufnr) or generation[bufnr] ~= gen then return end
      local size = stat.type == "directory" and "      " or format_size(stat.size)
      local text = pad .. size .. "  " .. format_mtime(stat.mtime and stat.mtime.sec)
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
        virt_text = { { text, hl_group } },
        virt_text_pos = "eol",
        hl_mode = "combine",
        invalidate = true,
      })
    end))
  end
end

--- Install the decorator. Calling it again replaces the previous setup.
---@param opts { enabled?: boolean, hl?: string }
function M.setup(opts)
  local group = vim.api.nvim_create_augroup("oil_extras_details", { clear = true })
  hl_group = opts.hl or "OilExtrasDetails"
  enabled = opts.enabled ~= false
  if not enabled then return end

  local function define_hl()
    vim.api.nvim_set_hl(0, "OilExtrasDetails", { link = "Comment", default = true })
  end
  define_hl()
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_hl })

  -- One scheduled pass per tick, skipped while there are pending edits or
  -- Oil is mid-render: both are followed by another change.
  local queued, attached = {}, {}
  local function queue(bufnr)
    if queued[bufnr] then return end
    queued[bufnr] = true
    vim.schedule(function()
      queued[bufnr] = nil
      if vim.api.nvim_buf_is_valid(bufnr) and not vim.bo[bufnr].modified
        and not compat.rendering(bufnr)
      then
        M.decorate(bufnr)
      end
    end)
  end

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "OilEnter",
    callback = function(args)
      local bufnr = args.data and args.data.buf
      if not bufnr then return end
      queue(bufnr)
      if attached[bufnr] then return end
      attached[bufnr] = vim.api.nvim_buf_attach(bufnr, false, {
        -- Returning true detaches, which is how a later setup() with the
        -- decorator off stops the watch.
        on_lines = function(_, b)
          if not enabled then
            attached[b] = nil
            return true
          end
          queue(b)
        end,
        on_detach = function(_, b) attached[b] = nil end,
      })
    end,
  })
end

--- Columns Oil was set up with, remembered at the first toggle so the toggle
--- can go back to them.
local base

--- Switch Oil between its configured columns and `columns`.
---@param columns? table default: icon, permissions, size, mtime
function M.toggle_columns(columns)
  columns = columns or { "icon", "permissions", "size", "mtime" }
  local current = compat.columns()
  base = base or vim.deepcopy(current)
  require("oil").set_columns(vim.deep_equal(current, columns) and base or columns)
end

return M

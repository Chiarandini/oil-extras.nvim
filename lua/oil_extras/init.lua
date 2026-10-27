--- oil-extras: select mode, dual pane, an entry picker, async size and
--- mtime, archives and a multi-file clipboard for oil.nvim.
---
--- Actions are bound in Oil's own `keymaps` (see oil_extras.actions);
--- `setup` configures them and installs the two features that run on their
--- own: the details decorator and keeping the cursor on re-render.

local M = {}

M.actions = require("oil_extras.actions")

---@param opts? oil_extras.Config
function M.setup(opts)
  local config = require("oil_extras.config")
  config.set(opts)
  require("oil_extras.details").setup(config.options.details)

  local group = vim.api.nvim_create_augroup("oil_extras_cursor", { clear = true })
  if config.options.keep_cursor then
    -- Oil's watcher marks a hidden directory dirty and re-renders it on
    -- return. Pin the cursor to the entry it is on now, or an entry created
    -- above it while you were away shifts it onto a neighbour.
    local compat = require("oil_extras.compat")
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype ~= "oil" or not compat.dirty(args.buf) then return end
        local entry = require("oil").get_cursor_entry()
        if entry then compat.set_last_cursor(vim.api.nvim_buf_get_name(args.buf), entry.name) end
      end,
    })
  end
end

return M

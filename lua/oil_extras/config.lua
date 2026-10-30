local M = {}

---@class oil_extras.Config
M.defaults = {
  -- Size and mtime as virtual text after each entry, painted as the stats
  -- arrive so the listing itself is never held up.
  details = {
    enabled = true,
    -- Linked to `Comment` unless a colorscheme defines it.
    hl = "OilExtrasDetails",
  },
  -- When Oil re-renders a directory you return to (its watcher marked it
  -- changed), keep the cursor on the entry it was on.
  keep_cursor = true,
  -- Keys inside select mode. `false` leaves one unbound.
  select = {
    keys = {
      toggle = "<Space>",
      yank = "y",
      cut = "d",
      trash = "D",
      rename = "c",
      leave = "<Esc>",
    },
  },
  -- Keys inside a dual-pane pair: each key in `other` moves to the other
  -- pane, `close` closes both.
  dual = {
    keys = {
      other = { "<C-h>", "<C-l>" },
      close = "q",
    },
  },
  -- In the entry picker: the key that moves the Oil cursor to the entry
  -- without opening it.
  pick = {
    keys = { jump = "<S-CR>" },
  },
  -- Opens the file and grep pickers instead of snacks.nvim:
  -- `function(source, opts)`, `source` being "files" or "grep" and `opts`
  -- holding `cwd`, `title`, and snacks' `hidden` and `ignored`.
  picker = false,
}

M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.set(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  -- A list is replaced, not merged index by index.
  local other = vim.tbl_get(opts, "dual", "keys", "other")
  if other ~= nil then
    M.options.dual.keys.other = type(other) == "table" and other or { other }
  end
end

return M

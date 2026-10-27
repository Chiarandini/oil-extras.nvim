-- Boots Neovim with oil.nvim and oil-extras only, Oil set up the way a user
-- would bind the actions. OIL_NVIM points at an oil.nvim checkout; without it
-- the usual lazy.nvim locations are tried.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

local oil_path = vim.env.OIL_NVIM
if not oil_path then
  for _, appname in ipairs({ "nvim", "noethervim" }) do
    local p = vim.fn.expand("~/.local/share/" .. appname .. "/lazy/oil.nvim")
    if vim.uv.fs_stat(p) then
      oil_path = p
      break
    end
  end
end
assert(oil_path, "oil.nvim not found; set OIL_NVIM")

vim.opt.rtp:prepend(oil_path)
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false

local actions = require("oil_extras.actions")
require("oil").setup({
  default_file_explorer = true,
  watch_for_changes = true,
  keymaps = {
    ["Y"] = actions.copy_to_clipboard,
    ["gz"] = actions.zip,
    ["gZ"] = actions.unzip,
    ["gm"] = actions.select,
    ["gd"] = actions.toggle_details,
  },
})
require("oil_extras").setup({})

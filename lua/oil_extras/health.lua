local M = {}

function M.check()
  local h = vim.health
  h.start("oil-extras")

  if not pcall(require, "oil") then
    h.error("oil.nvim is not installed; every feature needs it")
    return
  end
  h.ok("oil.nvim is installed")

  -- The parts of Oil this plugin reads that are not its documented API.
  for _, item in ipairs(require("oil_extras.compat").check()) do
    if item.ok then
      h.ok(item.what)
    else
      h.error(item.what .. ": no longer true in this oil.nvim; please report it")
    end
  end

  local oil_config = require("oil.config")
  if require("oil_extras.config").options.keep_cursor and not oil_config.watch_for_changes then
    h.info("keep_cursor only matters with Oil's watch_for_changes = true")
  end

  if pcall(require, "snacks") then
    h.ok("snacks.nvim is installed (pick, find_files, grep)")
  else
    h.info("snacks.nvim not installed: pick falls back to vim.ui.select; find_files and grep are unavailable")
  end

  local windows = vim.fn.has("win32") == 1
  for _, tool in ipairs(windows and { "powershell" } or { "zip", "unzip" }) do
    if vim.fn.executable(tool) == 1 then
      h.ok(tool .. " found (zip, unzip)")
    else
      h.warn(tool .. " not found: the zip and unzip actions need it")
    end
  end

  if vim.fn.has("macunix") == 1 then
    if vim.fn.executable("osascript") == 1 then
      h.ok("osascript found (copying several files to the clipboard)")
    else
      h.warn("osascript not found: copying several files to the clipboard needs it")
    end
  end
end

return M

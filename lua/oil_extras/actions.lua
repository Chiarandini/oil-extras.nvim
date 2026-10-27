--- Actions shaped like oil.nvim's own: bind one in Oil's `keymaps` the way
--- you would bind `actions.select`, directly or with `opts`:
---
---   keymaps = {
---     ["gm"] = require("oil_extras.actions").select,
---     ["Yd"] = { require("oil_extras.actions").yank_path, opts = { modify = ":h", register = "+" } },
---   }
---
--- Nothing is bound by default.

local compat = require("oil_extras.compat")

local M = {}

--- Title for the directory-scoped pickers: which picker it is, and the
--- directory relative to its git repository (the repository's name at its
--- root), else `~`-shortened. A long path keeps its tail, which is the part
--- that locates you.
local function picker_title(dir, what)
  local scope
  local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")[1]
  if vim.v.shell_error == 0 and git_root then
    scope = dir:sub(#git_root + 2)
    if scope == "" then scope = vim.fn.fnamemodify(git_root, ":t") end
  else
    scope = vim.fn.fnamemodify(dir, ":~")
  end
  scope = scope:gsub("(.)/$", "%1")
  if #scope > 40 then scope = "…" .. scope:sub(-39) end
  return ("Oil %s (%s)"):format(what, scope)
end

local function snacks_picker(what, source)
  local dir = require("oil").get_current_dir()
  if not dir then return end
  local ok, Snacks = pcall(require, "snacks")
  if not (ok and Snacks.picker) then
    vim.notify("Oil: this picker needs snacks.nvim", vim.log.levels.WARN)
    return
  end
  Snacks.picker[source]({
    cwd = dir,
    title = picker_title(dir, what),
    hidden = compat.show_hidden(),
    ignored = true,
  })
end

M.select = {
  desc = "Select mode: toggle the entry (or visual range)",
  mode = { "n", "x" },
  callback = function() require("oil_extras.select").enter() end,
}

M.dual_pane = {
  desc = "Open a second pane beside this one; again to close both",
  callback = function() require("oil_extras.dual").open() end,
}

M.pick = {
  desc = "Pick an entry of this directory",
  callback = function(opts) require("oil_extras.pick").pick(opts) end,
  parameters = {
    filter = { type = "fun(entry: table): boolean", desc = "Keep only the entries this returns true for" },
    title = { type = "string", desc = "Picker title" },
    auto_select = { type = "boolean", desc = "Open the entry at once when it is the only match" },
  },
}

M.find_files = {
  desc = "Find files under this directory (snacks.nvim)",
  callback = function() snacks_picker("Files", "files") end,
}

M.grep = {
  desc = "Grep under this directory (snacks.nvim)",
  callback = function() snacks_picker("Grep", "grep") end,
}

M.toggle_details = {
  desc = "Toggle the detail columns",
  callback = function(opts) require("oil_extras.details").toggle_columns(opts and opts.columns) end,
  parameters = {
    columns = { type = "table", desc = "Columns to switch to (default: icon, permissions, size, mtime)" },
  },
}

M.zip = {
  desc = "Zip the entry, the visual range or the selection",
  mode = { "n", "x" },
  callback = function() require("oil_extras.archive").zip() end,
}

M.unzip = {
  desc = "Extract the .zip entry, range or selection",
  mode = { "n", "x" },
  callback = function() require("oil_extras.archive").unzip() end,
}

M.copy_to_clipboard = {
  desc = "Copy the file(s) to the system clipboard",
  mode = { "n", "x" },
  callback = function() require("oil_extras.clipboard").copy() end,
}

--- Unlike Oil's `yank_entry`, the modifier applies before a directory gets
--- its trailing slash, so `:h` on a directory is its parent and `:t` its name.
M.yank_path = {
  desc = "Yank the entry's path",
  callback = function(opts)
    opts = opts or {}
    local oil = require("oil")
    local entry, dir = oil.get_cursor_entry(), oil.get_current_dir()
    if not entry or not dir then return end
    local path = dir .. entry.name
    if opts.modify then
      path = vim.fn.fnamemodify(path, opts.modify)
    elseif entry.type == "directory" then
      path = path .. "/"
    end
    local reg = opts.register or vim.v.register
    vim.fn.setreg(reg, path)
    if reg == "+" or reg == "*" then vim.notify("Copied: " .. path) end
  end,
  parameters = {
    modify = { type = "string", desc = "fnamemodify() mods, e.g. \":h\" or \":t\"" },
    register = { type = "string", desc = "Register to yank into (default: v:register)" },
  },
}

M.open_dir_external = {
  desc = "Open this directory in the system file manager",
  callback = function()
    local dir = require("oil").get_current_dir()
    if not dir then return end
    local cmd = vim.fn.has("macunix") == 1 and "open"
      or vim.fn.has("win32") == 1 and "explorer"
      or "xdg-open"
    vim.fn.jobstart({ cmd, dir }, { detach = true })
  end,
}

M.symlink = {
  desc = "Create a symlink in this directory",
  callback = function()
    local dir = require("oil").get_current_dir()
    if not dir then return end
    local target = vim.fn.input({ prompt = "Symlink target: ", completion = "file", cancelreturn = "" })
    if target == "" then return end
    local name = vim.fn.input({ prompt = "Symlink name: ", default = vim.fs.basename(target), cancelreturn = "" })
    if name == "" then return end
    local out = vim.fn.system({ "ln", "-s", target, dir .. name })
    if vim.v.shell_error ~= 0 then vim.notify("Oil: " .. out, vim.log.levels.ERROR) end
  end,
}

--- Apply pending edits, and from normal mode also leave Oil.
---
--- From insert it ends the edit: the name just typed is committed and you
--- are back in normal mode with the listing still up. From normal it ends the
--- session. Typing is when a stray press is likeliest and when a confirmation
--- is likeliest to be waived (`skip_confirm_for_simple_edits`), so leaving
--- stays a deliberate second press.
---
--- If Oil asked for confirmation, the press does not also leave: you were
--- stopped and asked something, and leaving as well would be a second
--- consequence of a keystroke made before the question existed. Deletes
--- always ask, and after a deletion you want the listing back to see the row
--- gone.
---
--- Leaving is `oil.close`, which puts the window back to what it held before;
--- `exit_if_last_buf` ends the session only when Oil is the sole buffer.
M.save_and_leave = {
  desc = "Apply changes; from normal mode, also leave Oil",
  mode = { "n", "i" },
  callback = function()
    local oil = require("oil")
    -- Decided before `stopinsert`, which would make every press look normal.
    local leave = vim.fn.mode():sub(1, 1) ~= "i"

    local function commit()
      local asked = false
      local probe = vim.api.nvim_create_autocmd("FileType", {
        pattern = compat.CONFIRM_FILETYPE,
        once = true,
        callback = function() asked = true end,
      })
      oil.save({}, function(err)
        pcall(vim.api.nvim_del_autocmd, probe)
        if err then
          if err ~= compat.CANCELED then vim.notify(err, vim.log.levels.ERROR) end
          return
        end
        if not leave or asked then return end
        -- One tick after the post-apply render, so the buffer is not
        -- deleted mid-render.
        vim.schedule(function() oil.close({ exit_if_last_buf = true }) end)
      end)
    end

    if leave then
      commit()
    else
      -- `oil.save` locks the buffer and the confirmation wants normal-mode
      -- keys; `stopinsert` only takes hold once the mapping returns.
      vim.cmd("stopinsert")
      vim.schedule(commit)
    end
  end,
}

return M

-- tests/actions_spec.lua
--
-- The actions and features outside select mode: details, yank_path on
-- directories, config merging, the picker without snacks, dual pane, and
-- save_and_leave.
--
-- Run: bash tests/run.sh actions_spec.lua

local pass, fail = 0, 0
local function ok(name, cond, msg)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. (msg and (" -- " .. tostring(msg)) or ""))
  end
end

local oil = require("oil")
local actions = require("oil_extras.actions")
local details_ns = vim.api.nvim_get_namespaces()["oil_extras.details"]

local root = assert(vim.uv.fs_realpath((vim.fn.tempname():gsub("[^/]+$", ""))))
root = root .. ("/oil-extras-%d"):format(vim.uv.hrtime())
vim.fn.mkdir(root .. "/dir/sub", "p")
vim.fn.writefile({ "a" }, root .. "/dir/a.txt")

local function open(dir)
  oil.open(dir)
  vim.wait(3000, function() return vim.b.oil_ready == true and vim.bo.filetype == "oil" end, 10)
  vim.wait(50)
  return vim.api.nvim_get_current_buf()
end

local function goto_name(name)
  for lnum = 1, vim.api.nvim_buf_line_count(0) do
    local e = oil.get_entry_on_line(0, lnum)
    if e and e.name == name then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return
    end
  end
  error("no entry " .. name)
end

local function detail_marks(buf)
  local n = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, details_ns, 0, -1, { details = true })) do
    if not m[4].invalid then n = n + 1 end
  end
  return n
end

-- ── details ──────────────────────────────────────────────────────────
local buf = open(root .. "/dir")
vim.wait(1000, function() return detail_marks(buf) == 2 end, 10)
ok("details: one mark per entry", detail_marks(buf) == 2, detail_marks(buf))

actions.toggle_details.callback()
vim.wait(1000, function() return detail_marks(buf) == 0 end, 10)
ok("details: none while the real columns show size", detail_marks(buf) == 0, detail_marks(buf))
actions.toggle_details.callback()
vim.wait(1000, function() return detail_marks(buf) == 2 end, 10)
ok("details: back after toggling the columns off", detail_marks(buf) == 2, detail_marks(buf))

vim.fn.writefile({ string.rep("x", 5000) }, root .. "/dir/a.txt")
vim.wait(2000, function()
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, details_ns, 0, -1, { details = true })) do
    if m[4].virt_text and m[4].virt_text[1][1]:find("5.0k", 1, true) then return true end
  end
  return false
end, 20)
local grown = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, details_ns, 0, -1, { details = true })) do
  if m[4].virt_text and m[4].virt_text[1][1]:find("5.0k", 1, true) then grown = true end
end
ok("details: follow a file that changes on disk", grown)

-- ── yank_path ────────────────────────────────────────────────────────
goto_name("sub")
actions.yank_path.callback({ register = "a" })
ok("yank_path: directory keeps its slash", vim.fn.getreg("a") == root .. "/dir/sub/", vim.fn.getreg("a"))
actions.yank_path.callback({ register = "a", modify = ":h" })
ok("yank_path: :h on a directory is its parent", vim.fn.getreg("a") == root .. "/dir", vim.fn.getreg("a"))
actions.yank_path.callback({ register = "a", modify = ":t" })
ok("yank_path: :t on a directory is its name", vim.fn.getreg("a") == "sub", vim.fn.getreg("a"))

-- ── config ───────────────────────────────────────────────────────────
local config = require("oil_extras.config")
config.set({ dual = { keys = { other = { "<C-w>w" } } }, select = { keys = { trash = false } } })
ok("config: a key list is replaced, not merged", vim.deep_equal(config.options.dual.keys.other, { "<C-w>w" }),
  vim.inspect(config.options.dual.keys.other))
ok("config: false unbinds", config.options.select.keys.trash == false)
ok("config: the rest keeps its defaults", config.options.select.keys.toggle == "<Space>")
config.set({})

-- ── pick without snacks ──────────────────────────────────────────────
local real_select = vim.ui.select
local offered
vim.ui.select = function(items, _, cb)
  offered = vim.tbl_map(function(i) return i.text end, items)
  for _, i in ipairs(items) do if i.text == "sub" then return cb(i) end end
end
actions.pick.callback({ filter = function(e) return e.type == "directory" end })
vim.wait(1000, function() return oil.get_current_dir() == root .. "/dir/sub/" end, 10)
vim.ui.select = real_select
ok("pick: falls back to vim.ui.select, filtered", offered and #offered == 1 and offered[1] == "sub", vim.inspect(offered))
ok("pick: opens the chosen entry", oil.get_current_dir() == root .. "/dir/sub/", oil.get_current_dir())

-- ── dual pane ────────────────────────────────────────────────────────
open(root .. "/dir")
local left = vim.api.nvim_get_current_win()
actions.dual_pane.callback()
vim.wait(500, function() return #vim.api.nvim_tabpage_list_wins(0) == 2 end, 10)
local right = vim.api.nvim_get_current_win()
ok("dual: a second pane", #vim.api.nvim_tabpage_list_wins(0) == 2 and right ~= left)
vim.api.nvim_feedkeys(vim.keycode("<C-h>"), "xt", false)
ok("dual: <C-h> moves to the other pane", vim.api.nvim_get_current_win() == left)
actions.dual_pane.callback()
vim.wait(500, function() return #vim.api.nvim_tabpage_list_wins(0) == 1 end, 10)
ok("dual: pressing it again closes both", #vim.api.nvim_tabpage_list_wins(0) == 1, #vim.api.nvim_tabpage_list_wins(0))

-- ── save_and_leave ───────────────────────────────────────────────────
-- A fresh tab page, so the windows the earlier steps left behind play no part.
vim.cmd("tabnew " .. vim.fn.fnameescape(root .. "/dir/a.txt"))
local origin = vim.api.nvim_get_current_buf()
require("oil.config").skip_confirm_for_simple_edits = true
buf = open(root .. "/dir")
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "made.txt" })
actions.save_and_leave.callback()
vim.wait(3000, function() return vim.uv.fs_stat(root .. "/dir/made.txt") ~= nil and vim.bo.filetype ~= "oil" end, 10)
ok("save_and_leave: applied", vim.uv.fs_stat(root .. "/dir/made.txt") ~= nil)
ok("save_and_leave: back to the buffer it replaced", vim.api.nvim_get_current_buf() == origin,
  vim.api.nvim_buf_get_name(0))

vim.fn.delete(root, "rf")
print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then vim.cmd("cquit 1") end

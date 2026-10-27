-- tests/select_spec.lua
--
-- Select mode (oil_extras.select), driven through real keys.
--
-- The contract under test:
--   entering   marks the entry under the cursor and installs the key layer
--   <Space>    toggles an entry; over a visual range, selects it whole
--              unless all of it already is
--   y / d      fill the register with the selected lines, as yy/dd would;
--              `p` + write in another directory copies / moves
--   D          deletes and writes; canceling the confirmation restores
--   leaving    restores every buffer-local mapping the layer shadowed
--   the mode   survives Oil re-rendering, ends when the dir leaves the screen
--   targets()  selection, else visual range, else cursor; what Y / gz act on
--
-- Run: bash tests/run.sh select_spec.lua

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
local sel = require("oil_extras.select")
local ns  = vim.api.nvim_get_namespaces()["oil_extras.select"]
require("oil.config").delete_to_trash = false -- keep test files out of the real trash

-- Resolved: macOS temp dirs live under /var, a symlink Oil reports through.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
local src, dst = root .. "/src", root .. "/dst"
vim.fn.mkdir(src .. "/sub", "p")
vim.fn.mkdir(dst, "p")
for _, n in ipairs({ "a.txt", "b.txt", "c.txt", "d.txt", "e.txt", "f.txt", "sub/inner.txt" }) do
  vim.fn.writefile({ n }, src .. "/" .. n)
end

local function feed(keys) vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false) end
local function exists(p) return vim.uv.fs_stat(p) ~= nil end

local function open(dir)
  oil.open(dir)
  vim.wait(3000, function() return vim.b.oil_ready == true and vim.bo.filetype == "oil" end, 10)
  vim.wait(50)
  return vim.api.nvim_get_current_buf()
end

local function goto_name(name)
  local buf = vim.api.nvim_get_current_buf()
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    local e = oil.get_entry_on_line(buf, lnum)
    if e and e.name == name then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return lnum
    end
  end
  error("no entry " .. name)
end

local function names_in(buf)
  local out = {}
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    local e = oil.get_entry_on_line(buf, lnum)
    if e and e.name ~= "" then out[e.name] = true end
  end
  return out
end

local function count() return vim.b.oil_extras_select end
local function marks(buf) return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) end
local function bufmap(lhs, mode)
  local m = vim.fn.maparg(lhs, mode or "n", false, true)
  return m.buffer == 1 and m or nil
end

-- ── enter + toggle ───────────────────────────────────────────────────
local buf = open(src)
local before = {
  space = bufmap("<Space>") and bufmap("<Space>").desc,
  slash = bufmap("/") and bufmap("/").desc,
}

goto_name("a.txt")
sel.enter()
ok("enter: active", sel.is_active(buf))
ok("enter: marks the entry under the cursor", count() == 1, count())
ok("enter: <Space> is the toggle, nowait", bufmap("<Space>") and bufmap("<Space>").nowait == 1)
ok("enter: buffer-local / lifted for native search", bufmap("/") == nil, bufmap("/") and bufmap("/").desc)

goto_name("c.txt"); feed("<Space>")
goto_name("sub");   feed("<Space>")
ok("toggle: adds", count() == 3, count())
feed("<Space>")
ok("toggle: removes", count() == 2, count())
ok("toggle: one highlight per selected row", marks(buf) == 2, marks(buf))

goto_name("d.txt"); feed("Vj<Space>")
ok("visual: selects the range", count() == 4, count())
goto_name("d.txt"); feed("Vj<Space>")
ok("visual: fully selected range clears", count() == 2, count())

-- ── survives a re-render ─────────────────────────────────────────────
require("oil.actions").toggle_hidden.callback()
vim.wait(500)
feed("<Ignore>") -- let the normal-mode loop fire TextChanged
vim.wait(50)
ok("re-render: selection repainted", marks(buf) == 2 and count() == 2, marks(buf) .. "/" .. tostring(count()))
require("oil.actions").toggle_hidden.callback()
vim.wait(500); feed("<Ignore>"); vim.wait(50)

-- ── y: yank, leave, restore ──────────────────────────────────────────
feed("y")
local reg = vim.fn.getreg('"', 1, true)
ok("y: linewise register", vim.fn.getregtype('"') == "V")
ok("y: holds the selected lines", #reg == 2 and reg[1]:find("a.txt", 1, true) and reg[2]:find("c.txt", 1, true), vim.inspect(reg))
ok("y: leaves the mode", not sel.is_active(buf) and count() == nil)
ok("y: highlights cleared", marks(buf) == 0)
ok("leave: <Space> restored", (bufmap("<Space>") and bufmap("<Space>").desc) == before.space, vim.inspect(bufmap("<Space>")))
ok("leave: / restored", (bufmap("/") and bufmap("/").desc) == before.slash, vim.inspect(bufmap("/")))

-- ── empty selection + <Esc> ──────────────────────────────────────────
goto_name("a.txt"); sel.enter(); feed("<Space>")
feed("y")
ok("empty: action refuses, mode stays", sel.is_active(buf))
feed("<Esc>")
ok("<Esc>: leaves", not sel.is_active(buf))

-- ── d + p + write: move ──────────────────────────────────────────────
goto_name("b.txt"); sel.enter()
goto_name("sub");   feed("<Space>")
feed("d")
ok("d: lines removed, pending", names_in(buf)["b.txt"] == nil and vim.bo[buf].modified)
open(dst)
feed("p")
local saved_err = "pending"
oil.save({ confirm = false }, function(err) saved_err = err end)
vim.wait(5000, function() return saved_err ~= "pending" end, 10)
vim.wait(200)
ok("d + p: moved", exists(dst .. "/b.txt") and exists(dst .. "/sub/inner.txt")
  and not exists(src .. "/b.txt") and not exists(src .. "/sub"), saved_err)

-- ── D: cancel restores, confirm deletes ──────────────────────────────
buf = open(src)
goto_name("d.txt"); sel.enter()
goto_name("e.txt"); feed("<Space>")
feed("D")
vim.wait(2000, function() return vim.bo.filetype == "oil_preview" end, 10)
ok("D: confirmation shown", vim.bo.filetype == "oil_preview")
feed("n")
vim.wait(500)
ok("D cancel: entries back", names_in(buf)["d.txt"] and names_in(buf)["e.txt"])
ok("D cancel: buffer clean", not vim.bo[buf].modified)
ok("D cancel: files untouched", exists(src .. "/d.txt") and exists(src .. "/e.txt"))

goto_name("d.txt"); sel.enter()
feed("D")
vim.wait(2000, function() return vim.bo.filetype == "oil_preview" end, 10)
feed("y")
vim.wait(2000, function() return not exists(src .. "/d.txt") end, 10)
ok("D confirm: deleted", not exists(src .. "/d.txt") and exists(src .. "/e.txt"))

-- ── leaving the directory ends the mode ──────────────────────────────
vim.wait(300)
buf = open(src)
goto_name("a.txt"); sel.enter()
oil.open(root)
vim.wait(1000, function() return not sel.is_active(buf) end, 10)
ok("hidden: mode ends with the directory", not sel.is_active(buf))

-- ── targets(): selection > visual range > cursor ─────────────────────
local function tnames(list)
  return table.concat(vim.tbl_map(function(t) return t.name end, list), ",")
end

buf = open(src)
goto_name("a.txt")
local tdir, got = sel.targets()
ok("targets: cursor entry", tdir == src .. "/" and tnames(got) == "a.txt", tnames(got))
ok("targets: absolute path", got[1] and got[1].path == src .. "/a.txt", got[1] and got[1].path)

local captured
vim.keymap.set("x", "<F13>", function() captured = { sel.targets() } end, { buffer = buf })
goto_name("a.txt"); feed("Vj<F13>")
ok("targets: visual range", captured and tnames(captured[2]) == "a.txt,c.txt", captured and tnames(captured[2]))
vim.keymap.del("x", "<F13>", { buffer = buf })

goto_name("a.txt"); sel.enter()
goto_name("e.txt"); feed("<Space>")
_, got = sel.targets()
ok("targets: selection", tnames(got) == "a.txt,e.txt", tnames(got))
ok("targets: taking the selection ends the mode", not sel.is_active(buf))

goto_name("a.txt"); sel.enter(); feed("<Space>")
_, got = sel.targets()
ok("targets: empty selection keeps the mode", #got == 0 and sel.is_active(buf))
feed("<Esc>")

-- ── Y and gz act on the selection ────────────────────────────────────
if vim.fn.has("macunix") == 1 then
  local real_system, sent = vim.system, nil
  vim.system = function(cmd) sent = cmd; return { wait = function() return { code = 0 } end } end
  goto_name("a.txt"); sel.enter()
  goto_name("f.txt"); feed("<Space>")
  feed("Y")
  vim.wait(1600, function() return sent ~= nil end, 10)
  vim.system = real_system
  local paths = sent and vim.list_slice(sent, 6) or {}
  ok("Y: selection paths to the clipboard helper",
    #paths == 2 and paths[1] == src .. "/a.txt" and paths[2] == src .. "/f.txt", vim.inspect(paths))
  ok("Y: ends the mode", not sel.is_active(buf))
end

local real_input = vim.fn.input
vim.fn.input = function() return "picked.zip" end
goto_name("c.txt"); sel.enter()
goto_name("f.txt"); feed("<Space>")
feed("gz")
vim.wait(3000, function() return exists(src .. "/picked.zip") end, 20)
vim.fn.input = real_input
local listing = vim.fn.systemlist({ "unzip", "-Z1", src .. "/picked.zip" })
table.sort(listing)
ok("gz: zips the selection", table.concat(listing, ",") == "c.txt,f.txt", table.concat(listing, ","))

-- ── c: substitute over the selected names ────────────────────────────
local ren = root .. "/ren"
vim.fn.mkdir(ren .. "/keep", "p")
for _, n in ipairs({ "x1.txt", "x2.txt", "y.txt" }) do vim.fn.writefile({}, ren .. "/" .. n) end
vim.uv.fs_symlink(ren .. "/y.txt", ren .. "/lnk")

local real_ui_input = vim.ui.input
local answer
vim.ui.input = function(_, cb) cb(answer) end
local function rename_with(input) answer = input; feed("c") end
-- Renamed lines are matched by text: until the write, Oil's entry still
-- carries the old name.
local function shows(name)
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find(" " .. name, 1, true) ~= nil
end

buf = open(ren)
goto_name("x1.txt"); sel.enter()
for _, n in ipairs({ "x2.txt", "keep", "lnk" }) do goto_name(n); feed("<Space>") end
rename_with("s/^/new_/")
local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local joined = table.concat(after, "\n")
ok("c: renames every selected name", joined:find("new_x1.txt", 1, true) and joined:find("new_x2.txt", 1, true))
ok("c: directory keeps its slash", joined:find("new_keep/", 1, true) ~= nil, joined)
ok("c: link keeps its target", joined:find("new_lnk -> ", 1, true) ~= nil, joined)
ok("c: ^ anchors on the name, not the id", vim.iter(after):all(function(l) return l == "" or l:sub(1, 1) == "/" end), joined)
ok("c: unselected untouched", joined:find("new_y.txt", 1, true) == nil)
ok("c: leaves the mode, edits pending", not sel.is_active(buf) and vim.bo[buf].modified)
feed("u")
joined = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
ok("c: one undo restores all", joined:find("new_", 1, true) == nil, joined)

goto_name("x1.txt"); sel.enter(); goto_name("x2.txt"); feed("<Space>")
rename_with([[s/x\(\d\)/z\1/]])
saved_err = "pending"
oil.save({ confirm = false }, function(err) saved_err = err end)
vim.wait(5000, function() return saved_err ~= "pending" end, 10)
vim.wait(200)
ok("c + write: renamed on disk", exists(ren .. "/z1.txt") and exists(ren .. "/z2.txt")
  and not exists(ren .. "/x1.txt"), saved_err)

buf = open(ren)
vim.fn.setreg("/", "y")
goto_name("y.txt"); sel.enter()
rename_with("s//Q/")
ok("c: empty pattern reuses the last search", shows("Q.txt"))
feed("u")

goto_name("z1.txt"); sel.enter()
rename_with("s/Z1/w1/i")
ok("c: i flag", shows("w1.txt"))
feed("u")

goto_name("z1.txt"); sel.enter()
rename_with("s/nomatch/x/")
ok("c: no match keeps the mode", sel.is_active(buf) and not vim.bo[buf].modified)
rename_with([[s/\(/x/]])
ok("c: bad pattern keeps the mode", sel.is_active(buf) and not vim.bo[buf].modified)
rename_with("s/.*//")
ok("c: would-be-empty name left alone", sel.is_active(buf) and not vim.bo[buf].modified)
feed("<Esc>")
vim.ui.input = real_ui_input

-- ── repaint cost on a large directory ────────────────────────────────
local big = root .. "/big"
vim.fn.mkdir(big, "p")
for i = 1, 2000 do vim.fn.writefile({}, ("%s/f%04d.txt"):format(big, i)) end
open(big)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
sel.enter()
local t0 = vim.uv.hrtime()
vim.api.nvim_win_set_cursor(0, { 1000, 0 }); feed("<Space>")
local ms = (vim.uv.hrtime() - t0) / 1e6
print(("toggle on 2000 entries: %.1fms"):format(ms))
ok("perf: toggle under one frame-ish budget", ms < 50, ("%.1fms"):format(ms))
feed("<Esc>")

vim.fn.delete(root, "rf")
print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
  vim.cmd("cquit 1")
end

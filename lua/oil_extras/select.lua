--- Select mode for Oil: mark entries one at a time, wherever they sit in the
--- listing, then copy, move, rename or trash them together.
---
--- Oil already does multi-file work through the buffer: `V` over a run of
--- lines, `y` or `d`, `p` in another directory, `:w`. That only reaches
--- neighbours. Select mode is the same `V` without the adjacency. `y` and `d`
--- fill a register with the selected lines exactly as `yy` and `dd` would, so
--- the copy or move still happens in Oil's own write, with its confirmation,
--- its trash and its undo. Nothing in this file touches the filesystem.
---
--- The mode is a buffer-local key layer. Entering shadows a handful of keys
--- (`<Space>` toggles, `y`/`d`/`D`/`c` act, `<Esc>` leaves) and lifts any
--- buffer-local `/` and `?`, so native search is there to reach entries with:
--- a fuzzy picker on `/` jumps once but cannot be followed by `n`. Leaving
--- restores every mapping the layer shadowed, a which-key `<Space>` trigger
--- included. The mode ends on any action, on `<Esc>`, and when the directory
--- leaves the screen, which is where Finder drops a selection too.
---
--- The selection is a set of entry names, not line numbers. Oil rewrites
--- every line on refresh, sort and hidden-toggle; the names survive that, and
--- the highlight is repainted from them after each change.
---
--- `vim.b.oil_extras_select` holds the selected count while the mode is on,
--- so a statusline can show it without requiring this module.

local compat = require("oil_extras.compat")

local M = {}

local HL = "OilExtrasSelected"
local ns = vim.api.nvim_create_namespace("oil_extras.select")
local group = vim.api.nvim_create_augroup("oil_extras_select", { clear = true })

local function define_hl()
  vim.api.nvim_set_hl(0, HL, { link = "Visual", default = true })
end
define_hl()
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_hl })

---@class oil_extras.select.Keys
---@field toggle? string|false  toggle the entry (normal) or the range (visual)
---@field yank?   string|false  yank the selection; `p` + `:w` copies
---@field cut?    string|false  delete the selection into a register; `p` + `:w` moves
---@field trash?  string|false  delete the selection and write at once
---@field rename? string|false  `s/pat/rep/` over the selected names; `:w` applies
---@field leave?  string|false  leave select mode

local NATIVE = { "/", "?" }

---@class oil_extras.select.Opts
---@field keys? oil_extras.select.Keys  rebind the in-mode keys for this entry; false drops one

---@class oil_extras.select.State
---@field names table<string, true>
---@field added { mode: string, lhs: string }[]  mappings the layer set
---@field saved { mode: string, map: table }[]   buffer-local mappings it shadowed
---@field au integer[]

---@type table<integer, oil_extras.select.State>
local active = {}

--- The entry on `lnum`, or nil for rows that cannot be selected.
---@return table?
local function entry_at(buf, lnum)
  local e = require("oil").get_entry_on_line(buf, lnum)
  if compat.is_real_entry(e) then return e end
end

---@return integer[] rows of selected entries, top to bottom
local function selected_rows(buf)
  local names, rows = active[buf].names, {}
  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    local e = entry_at(buf, lnum)
    if e and names[e.name] then rows[#rows + 1] = lnum end
  end
  return rows
end

local function repaint(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local rows = selected_rows(buf)
  for _, lnum in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, { line_hl_group = HL, invalidate = true })
  end
  vim.b[buf].oil_extras_select = #rows
  vim.cmd.redrawstatus()
end

--- Toggle rows `first`..`last`. A range is selected whole unless all of it
--- already is, in which case it is cleared: one press settles a mixed range
--- rather than inverting it entry by entry.
local function toggle_rows(buf, first, last)
  local names = active[buf].names
  local hit, all_on = {}, true
  for lnum = first, last do
    local e = entry_at(buf, lnum)
    if e then
      hit[#hit + 1] = e.name
      all_on = all_on and names[e.name] == true
    end
  end
  for _, name in ipairs(hit) do names[name] = (not all_on) or nil end
  repaint(buf)
end

---@return integer first, integer last  the visual range, after leaving visual
local function take_visual()
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  if a > b then a, b = b, a end
  return a, b
end

local function lines_of(buf, rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = vim.api.nvim_buf_get_lines(buf, r - 1, r, true)[1] end
  return out
end

--- Bottom-up so earlier deletions do not shift later rows. Joined into one
--- undo step, so `u` brings the whole selection back.
local function delete_rows(buf, rows)
  vim.api.nvim_buf_call(buf, function()
    for i = #rows, 1, -1 do
      if i < #rows then pcall(vim.cmd.undojoin) end
      vim.api.nvim_buf_set_lines(buf, rows[i] - 1, rows[i], true, {})
    end
  end)
end

--- Rewrite rows in place, as one undo step.
---@param edits { lnum: integer, line: string }[]
local function replace_rows(buf, edits)
  vim.api.nvim_buf_call(buf, function()
    for i, ed in ipairs(edits) do
      if i > 1 then pcall(vim.cmd.undojoin) end
      vim.api.nvim_buf_set_lines(buf, ed.lnum - 1, ed.lnum, true, { ed.line })
    end
  end)
end

--- Byte span of the name in an Oil line. Oil writes the name last, after
--- the id and any columns: `name`, `name/` for a directory, `name -> target`
--- for a link. Uses the name as currently typed, so an edit made before
--- renaming is what the pattern sees.
---@return integer? first, integer? last
local function name_span(line, e)
  local name = compat.typed_name(e)
  if e.type == "link" then
    for _, sep in ipairs({ " -> ", "/ -> " }) do
      local s = line:find(name .. sep, 1, true)
      if s then return s, s + #name - 1 end
    end
    return nil
  end
  local suffix = name .. (e.type == "directory" and "/" or "")
  if line:sub(-#suffix) == suffix then
    local s = #line - #suffix + 1
    return s, s + #name - 1
  end
end

--- Read `s/pat/rep/flags` the way `:s` does: any punctuation delimiter, the
--- leading `s` optional, a backslash before the delimiter making it literal,
--- and an empty pattern meaning the last search, so `/` to find the entries
--- and `s//new/` to rename them reads as it would anywhere else. The flags
--- are the ones that mean something on a single name: g, i, I.
---@return { pat: string, rep: string, flags: string }? sub, string? err
function M._parse_sub(input)
  if input:match("^s[^%w%s]") then input = input:sub(2) end
  local delim = input:sub(1, 1)
  if not delim:match('^[^%w%s\\"|]$') then return nil, "expected s/pattern/replacement/" end

  local parts, cur, i = {}, {}, 2
  while i <= #input do
    local ch = input:sub(i, i)
    if ch == "\\" and i < #input then
      local nxt = input:sub(i + 1, i + 1)
      cur[#cur + 1] = nxt == delim and nxt or ch .. nxt
      i = i + 2
    elseif ch == delim and #parts < 2 then
      parts[#parts + 1] = table.concat(cur)
      cur = {}
      i = i + 1
    else
      cur[#cur + 1] = ch
      i = i + 1
    end
  end
  parts[#parts + 1] = table.concat(cur)

  local pat, rep, flags = parts[1], parts[2] or "", parts[3] or ""
  if pat == "" then pat = vim.fn.getreg("/") end
  if pat == "" then return nil, "empty pattern and no previous search" end
  if flags:match("[^giI]") then return nil, "unsupported flag (use g, i, I)" end
  if flags:find("I", 1, true) then
    pat = "\\C" .. pat
  elseif flags:find("i", 1, true) then
    pat = "\\c" .. pat
  end
  return { pat = pat, rep = rep, flags = flags:find("g", 1, true) and "g" or "" }
end

--- Undo back past `seq`. Stepped rather than `:undo {seq}`: Oil's render
--- clears the undo history but not the counter, so `seq` can name a state
--- that no longer exists (E830).
local function undo_past(buf, seq)
  vim.api.nvim_buf_call(buf, function()
    while true do
      local cur = vim.fn.undotree().seq_cur
      if cur <= seq then return end
      vim.cmd("silent undo")
      if vim.fn.undotree().seq_cur == cur then return end
    end
  end)
end

local function plural(n) return n == 1 and "entry" or "entries" end

---@return integer[]? rows, nil (with a warning) when nothing is selected
local function rows_for_action(buf)
  local rows = selected_rows(buf)
  if #rows == 0 then
    vim.notify("Oil select: nothing selected", vim.log.levels.WARN)
    return nil
  end
  return rows
end

local function yank(buf)
  local rows = rows_for_action(buf)
  if not rows then return end
  vim.fn.setreg(vim.v.register, lines_of(buf, rows), "l")
  M.leave(buf)
  vim.notify(("%d %s yanked: p in another directory, :w to copy"):format(#rows, plural(#rows)))
end

local function cut(buf)
  local rows = rows_for_action(buf)
  if not rows then return end
  vim.fn.setreg(vim.v.register, lines_of(buf, rows), "l")
  M.leave(buf)
  delete_rows(buf, rows)
  vim.notify(("%d %s cut: p in another directory, :w to move"):format(#rows, plural(#rows)))
end

--- Delete and write in one go. Oil always confirms a deletion, and with
--- `delete_to_trash` the confirmed entries go to the system trash. Canceling
--- undoes back to before the deletion, so the listing is as you left it
--- rather than holding unsaved deletions for the next `:w` to apply.
local function trash(buf)
  local rows = rows_for_action(buf)
  if not rows then return end
  local seq, was_modified
  vim.api.nvim_buf_call(buf, function() seq = vim.fn.undotree().seq_cur end)
  was_modified = vim.bo[buf].modified
  M.leave(buf)
  delete_rows(buf, rows)
  require("oil").save({}, function(err)
    if err == compat.CANCELED and vim.api.nvim_buf_is_valid(buf) then
      undo_past(buf, seq)
      vim.bo[buf].modified = was_modified
    elseif err then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end)
end

--- Run a substitution over the selected names and leave the result in the
--- buffer, unsaved: the listing is the preview, `u` takes it back, and `:w`
--- shows Oil's rename confirmation. Only the name is matched, never the id
--- or icon in front of it. A name the substitution would empty is left as it
--- was. When nothing changes the mode stays on, so the pattern can be fixed.
local function rename(buf)
  if not rows_for_action(buf) then return end
  vim.ui.input({ prompt = "Rename selection: ", default = "s/" }, function(input)
    if not input or input:match("^s?/?$") then return end
    if not (active[buf] and vim.api.nvim_buf_is_valid(buf)) then return end
    local sub, err = M._parse_sub(input)
    if not sub then
      vim.notify("Oil select: " .. err, vim.log.levels.WARN)
      return
    end

    local edits, emptied = {}, 0
    for _, lnum in ipairs(selected_rows(buf)) do
      local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, true)[1]
      local first, last = name_span(line, entry_at(buf, lnum))
      if first then
        local old = line:sub(first, last)
        local ok, new = pcall(vim.fn.substitute, old, sub.pat, sub.rep, sub.flags)
        if not ok then
          vim.notify("Oil select: " .. tostring(new), vim.log.levels.ERROR)
          return
        end
        if new == "" then
          emptied = emptied + 1
        elseif new ~= old then
          edits[#edits + 1] = { lnum = lnum, line = line:sub(1, first - 1) .. new .. line:sub(last + 1) }
        end
      end
    end

    local note = emptied > 0 and (" (%d left alone: would be empty)"):format(emptied) or ""
    if #edits == 0 then
      vim.notify("Oil select: no names changed" .. note, vim.log.levels.WARN)
      return
    end
    M.leave(buf)
    replace_rows(buf, edits)
    vim.notify(("%d %s renamed: review, :w to apply%s"):format(#edits, plural(#edits), note))
  end)
end

--- Shadow `lhs` in `buf` for the life of the mode. A buffer-local mapping
--- already there is saved for `release` to restore; a global one needs no
--- saving, since the buffer-local mapping only hides it. `rhs = false` lifts
--- the key without replacing it, exposing whatever it means outside Oil.
local function claim(buf, s, mode, lhs, rhs, desc)
  local prev = vim.fn.maparg(lhs, mode, false, true)
  if prev.buffer == 1 then
    s.saved[#s.saved + 1] = { mode = mode, map = prev }
    vim.keymap.del(mode, lhs, { buffer = buf })
  end
  if rhs then
    -- nowait: a global mapping that begins with the same key (a <Space>
    -- leader) would otherwise make the toggle sit out 'timeoutlen'.
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, nowait = true, desc = desc })
    s.added[#s.added + 1] = { mode = mode, lhs = lhs }
  end
end

local function release(buf, s)
  for _, m in ipairs(s.added) do pcall(vim.keymap.del, m.mode, m.lhs, { buffer = buf }) end
  vim.api.nvim_buf_call(buf, function()
    for _, sv in ipairs(s.saved) do pcall(vim.fn.mapset, sv.mode, false, sv.map) end
  end)
end

---@class oil_extras.Target
---@field name string
---@field type string  oil entry type: "file", "directory", "link"
---@field path string  absolute; no trailing slash on directories

--- What a multi-entry action acts on: the selection while select mode is
--- on, else the visual range, else the entry under the cursor. Taking the
--- selection ends the mode, as an operator ends visual mode, unless it is
--- empty; taking a range leaves visual. `../` and unwritten lines are never
--- targets.
---
--- One answer for every action, so each multi-file action (`zip`, `unzip`,
--- `copy_to_clipboard`, or one of your own) handles a selection through this
--- call alone, with no select-mode logic of its own.
---@return string? dir  the Oil directory; nil outside Oil
---@return oil_extras.Target[]
function M.targets()
  local buf = vim.api.nvim_get_current_buf()
  local dir = vim.bo[buf].filetype == "oil" and require("oil").get_current_dir(buf) or nil
  if not dir then return nil, {} end

  local rows
  if active[buf] then
    rows = selected_rows(buf)
    if #rows > 0 then M.leave(buf) end
  elseif vim.fn.mode():match("^[vV\22]") then
    local first, last = take_visual()
    rows = {}
    for lnum = first, last do rows[#rows + 1] = lnum end
  else
    rows = { vim.api.nvim_win_get_cursor(0)[1] }
  end

  local out = {}
  for _, lnum in ipairs(rows) do
    local e = entry_at(buf, lnum)
    if e then out[#out + 1] = { name = e.name, type = e.type, path = dir .. e.name } end
  end
  return dir, out
end

---@param buf? integer
---@return boolean
function M.is_active(buf)
  return active[buf or vim.api.nvim_get_current_buf()] ~= nil
end

--- Leave select mode in `buf`, dropping the selection.
---@param buf? integer
function M.leave(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local s = active[buf]
  if not s then return end
  active[buf] = nil
  for _, id in ipairs(s.au) do pcall(vim.api.nvim_del_autocmd, id) end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  release(buf, s)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.b[buf].oil_extras_select = nil
  vim.cmd.redrawstatus()
end

--- Toggle the entry under the cursor (or, from visual mode, the selected
--- range), entering select mode first if it is not already on. Pressing the
--- key that entered the mode again toggles, as `<Space>` does.
---@param opts? oil_extras.select.Opts
function M.enter(opts)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "oil" then return end

  local first, last
  if vim.fn.mode():match("^[vV\22]") then
    first, last = take_visual()
  else
    first = vim.api.nvim_win_get_cursor(0)[1]
    last = first
  end
  if active[buf] then return toggle_rows(buf, first, last) end

  ---@type oil_extras.select.Keys
  local keys = vim.tbl_extend("force", require("oil_extras.config").options.select.keys,
    opts and opts.keys or {})
  local s = { names = {}, added = {}, saved = {}, au = {} }
  active[buf] = s

  if keys.toggle then
    claim(buf, s, "n", keys.toggle, function()
      local lnum = vim.api.nvim_win_get_cursor(0)[1]
      toggle_rows(buf, lnum, lnum)
    end, "select: toggle entry")
    claim(buf, s, "x", keys.toggle, function()
      toggle_rows(buf, take_visual())
    end, "select: toggle range")
  end
  if keys.yank then claim(buf, s, "n", keys.yank, function() yank(buf) end, "select: yank (p + :w copies)") end
  if keys.cut then claim(buf, s, "n", keys.cut, function() cut(buf) end, "select: cut (p + :w moves)") end
  if keys.trash then claim(buf, s, "n", keys.trash, function() trash(buf) end, "select: move to trash") end
  if keys.rename then
    claim(buf, s, "n", keys.rename, function() rename(buf) end, "select: rename (s/pat/rep/)")
  end
  if keys.leave then claim(buf, s, "n", keys.leave, function() M.leave(buf) end, "select: leave") end
  for _, lhs in ipairs(NATIVE) do claim(buf, s, "n", lhs, false) end

  s.au = {
    -- Oil re-renders with a whole-buffer write, which drops the highlights;
    -- TextChanged follows it, as it does any edit or undo.
    vim.api.nvim_create_autocmd("TextChanged", {
      group = group,
      buffer = buf,
      callback = function()
        vim.schedule(function()
          if active[buf] and vim.api.nvim_buf_is_valid(buf) then repaint(buf) end
        end)
      end,
    }),
    -- Scheduled: the buffer is still mid-switch while BufHidden runs.
    vim.api.nvim_create_autocmd("BufHidden", {
      group = group,
      buffer = buf,
      callback = function() vim.schedule(function() M.leave(buf) end) end,
    }),
    -- A wipe skips BufHidden; there is nothing left to restore, only state.
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      buffer = buf,
      callback = function() active[buf] = nil end,
    }),
  }

  toggle_rows(buf, first, last)
end

return M

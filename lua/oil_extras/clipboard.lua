--- Copy files (not their paths) to the system clipboard, so a paste in the
--- file manager copies them.
---
--- One entry goes through Oil's own `copy_to_system_clipboard`. Several (a
--- visual range or a select-mode selection) need more on macOS: Oil's
--- AppleScript copies only the first, and even a multi-object write is read
--- back by Finder from the first pasteboard item only. Declaring
--- NSFilenamesPboardType with a path-list property list is what makes Finder
--- take the multi-file paste. Elsewhere Oil's copy handles a visual range
--- itself, but not a scattered selection.

local M = {}

local MAC_JXA = [[
function run(argv) {
  ObjC.import("AppKit");
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  pb.declareTypesOwner($.NSArray.arrayWithObject("NSFilenamesPboardType"), $.nil);
  var paths = $.NSMutableArray.alloc.init;
  for (var i = 0; i < argv.length; i++) {
    paths.addObject(argv[i]);
  }
  pb.setPropertyListForType(paths, "NSFilenamesPboardType");
}
]]

--- Put `paths` on the macOS pasteboard as Finder file references.
---@param paths string[]
function M.mac_copy_paths(paths)
  if #paths == 0 then
    vim.notify("Oil: no files to copy", vim.log.levels.WARN)
    return
  end
  local cmd = { "osascript", "-l", "JavaScript", "-e", MAC_JXA }
  vim.list_extend(cmd, paths)
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        vim.notify("Clipboard copy failed: " .. (out.stderr or ""), vim.log.levels.ERROR)
      else
        vim.notify(("Copied %d file%s to clipboard"):format(#paths, #paths == 1 and "" or "s"))
      end
    end)
  end)
end

--- Copy the entries an action targets: the selection, the visual range, or
--- the entry under the cursor.
function M.copy()
  local select = require("oil_extras.select")
  local several = select.is_active() or vim.fn.mode():match("^[vV\22]") ~= nil
  if several and vim.fn.has("macunix") == 1 then
    local _, targets = select.targets()
    M.mac_copy_paths(vim.tbl_map(function(t) return t.path end, targets))
  elseif select.is_active() then
    vim.notify("Oil: copying a selection to the clipboard is macOS-only", vim.log.levels.WARN)
  else
    require("oil.actions").copy_to_system_clipboard.callback()
  end
end

return M

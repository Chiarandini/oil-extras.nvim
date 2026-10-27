--- Zip and unzip the entries an action targets (see `select.targets`).
---
--- `zip -r` / `unzip -o` on macOS and Linux, PowerShell's Compress-Archive /
--- Expand-Archive on Windows; each is stock on its platform. The new files
--- appear when Oil re-reads the directory: at once with
--- `watch_for_changes`, otherwise on the next refresh.

local M = {}

local function names_of(targets)
  return vim.tbl_map(function(t) return t.name end, targets)
end

local function have(tool, what)
  if vim.fn.executable(tool) == 1 then return true end
  vim.notify(("Oil: '%s' not found in PATH; cannot %s"):format(tool, what), vim.log.levels.ERROR)
  return false
end

--- Zip the targets into one archive in the Oil directory, asking for its name.
function M.zip()
  local dir, targets = require("oil_extras.select").targets()
  if not dir then return end
  local names = names_of(targets)
  if #names == 0 then
    vim.notify("Oil: nothing to zip", vim.log.levels.WARN)
    return
  end
  local windows = vim.fn.has("win32") == 1
  if not have(windows and "powershell" or "zip", "create a zip") then return end

  -- Deferred so the <Esc> queued by leaving visual mode is processed first.
  vim.schedule(function()
    local base = #names == 1 and names[1]:gsub("/$", "") or "archive"
    local archive = vim.fn.input({ prompt = "Archive name: ", default = base .. ".zip", cancelreturn = "" })
    if archive == "" then return end
    if not archive:lower():match("%.zip$") then archive = archive .. ".zip" end

    local cmd
    if windows then
      local quoted = vim.tbl_map(function(n) return "'" .. n:gsub("'", "''") .. "'" end, names)
      cmd = {
        "powershell", "-NoProfile", "-NonInteractive", "-Command",
        ("Compress-Archive -Path %s -DestinationPath '%s' -Force"):format(
          table.concat(quoted, ","), (archive:gsub("'", "''"))),
      }
    else
      cmd = { "zip", "-rq", archive }
      vim.list_extend(cmd, names)
    end

    vim.fn.jobstart(cmd, {
      cwd = dir,
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify(("Zipped %d entr%s → %s"):format(#names, #names == 1 and "y" or "ies", archive))
          else
            vim.notify("Oil: zip failed (exit " .. code .. ")", vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

--- Extract the `.zip` targets into a directory, asking which. Other targets
--- are skipped and counted.
function M.unzip()
  local dir, targets = require("oil_extras.select").targets()
  if not dir then return end

  local zips, skipped = {}, 0
  for _, n in ipairs(names_of(targets)) do
    if n:lower():match("%.zip$") then
      zips[#zips + 1] = n
    else
      skipped = skipped + 1
    end
  end
  if #zips == 0 then
    vim.notify("Oil: no .zip entries to extract", vim.log.levels.WARN)
    return
  end
  local windows = vim.fn.has("win32") == 1
  if not have(windows and "powershell" or "unzip", "extract a zip") then return end

  vim.schedule(function()
    local dest = vim.fn.input({ prompt = "Extract to: ", default = ".", completion = "dir", cancelreturn = "" })
    if dest == "" then return end

    local pending, failed = #zips, 0
    local function finish()
      pending = pending - 1
      if pending > 0 then return end
      vim.schedule(function()
        if failed == 0 then
          local msg = ("Extracted %d archive%s → %s"):format(#zips, #zips == 1 and "" or "s", dest)
          if skipped > 0 then msg = msg .. (" (skipped %d non-zip)"):format(skipped) end
          vim.notify(msg)
        else
          vim.notify(("Oil: %d of %d extractions failed"):format(failed, #zips), vim.log.levels.ERROR)
        end
      end)
    end

    for _, zip in ipairs(zips) do
      local cmd
      if windows then
        cmd = {
          "powershell", "-NoProfile", "-NonInteractive", "-Command",
          ("Expand-Archive -Path '%s' -DestinationPath '%s' -Force"):format(
            (zip:gsub("'", "''")), (dest:gsub("'", "''"))),
        }
      else
        cmd = { "unzip", "-oq", zip, "-d", dest }
      end
      vim.fn.jobstart(cmd, {
        cwd = dir,
        on_exit = function(_, code)
          if code ~= 0 then failed = failed + 1 end
          finish()
        end,
      })
    end
  end)
end

return M

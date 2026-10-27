# oil-extras.nvim

Additions to [oil.nvim](https://github.com/stevearc/oil.nvim), as actions you
bind in Oil's own `keymaps`:

- **Select mode:** mark entries anywhere in the listing, then copy, move,
  rename (`s/pattern/replacement/`) or trash them together. The copy or move
  still happens in Oil's write, with its confirmation, trash and undo.
- **Dual pane:** a second Oil pane beside the first, each navigable on its
  own, for moving files between two directories.
- **Pickers:** a fuzzy picker over the entries of the listing, and file and
  grep pickers scoped to the directory.
- **Details:** size and mtime after each entry, painted as the stats arrive,
  so a large directory never sits empty waiting for them.
- **Files:** zip and unzip, copying several files to the macOS clipboard so
  Finder pastes them all, path yanks that work on directories, symlinks, and
  a key that applies edits and leaves.

## Requirements

- Neovim 0.10+
- [oil.nvim](https://github.com/stevearc/oil.nvim)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for the
  pickers (the entry picker falls back to `vim.ui.select`)
- Optional: `zip` and `unzip` (PowerShell on Windows), `osascript` on macOS

## Setup

Nothing is bound by default. With lazy.nvim, build Oil's keymaps once
oil-extras is loaded:

```lua
{
  "stevearc/oil.nvim",
  dependencies = { "Chiarandini/oil-extras.nvim" },
  opts = function()
    local x = require("oil_extras.actions")
    return {
      watch_for_changes = true,
      keymaps = {
        ["gm"] = x.select,
        ["gV"] = x.dual_pane,
        ["gd"] = x.toggle_details,
        ["gf"] = x.find_files,
        ["gG"] = x.grep,
        ["gz"] = x.zip,
        ["gZ"] = x.unzip,
        ["gX"] = x.open_dir_external,
        ["gS"] = x.symlink,
        ["Y"]  = x.copy_to_clipboard,
        ["yp"] = x.yank_path,
        ["yd"] = { x.yank_path, opts = { modify = ":h" } },
        ["yn"] = { x.yank_path, opts = { modify = ":t" } },
        ["<S-CR>"] = x.save_and_leave,
      },
    }
  end,
},
{ "Chiarandini/oil-extras.nvim", lazy = true, opts = {} },
```

`opts` for oil-extras (the defaults):

```lua
{
  details = { enabled = true, hl = "OilExtrasDetails" },
  keep_cursor = true, -- with watch_for_changes: stay on your entry when a changed directory re-renders
  select = { keys = { toggle = "<Space>", yank = "y", cut = "d", trash = "D", rename = "c", leave = "<Esc>" } },
  dual = { keys = { other = { "<C-h>", "<C-l>" }, close = "q" } },
  pick = { keys = { jump = "<S-CR>" } },
}
```

## Select mode

Entering (`select`) marks the entry under the cursor. Inside the mode:

| Key | Does |
|---|---|
| `<Space>` | toggle the entry; over a visual range, select it whole |
| `y` / `d` | yank / cut the selected lines; `p` in another directory and `:w` copies / moves |
| `D` | delete and write; canceling Oil's confirmation puts them back |
| `c` | rename by `s/pattern/replacement/`, left unsaved for review |
| `<Esc>` | leave |

`/` and `?` are native search inside the mode. `zip`, `unzip` and
`copy_to_clipboard` act on the selection when there is one, and
`require("oil_extras.select").targets()` gives your own actions the same
answer.

A statusline can show the count from `vim.b.oil_extras_select`.

## Health

`:checkhealth oil_extras` checks the parts of oil.nvim this plugin relies on
that are not Oil's documented API, so an Oil update that moves one is
reported instead of failing quietly.

Full reference: `:h oil-extras`.

## License

MIT

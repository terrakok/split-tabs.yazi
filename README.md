# split-tabs.yazi

<p align="center">
    <img src="media/screenshot.png" width="70%"/>
</p>

A [Yazi](https://github.com/sxyazi/yazi) plugin that provides a dual-pane view by splitting the screen between two tabs.

## Features
- Toggle dual-pane mode
- Switch focus between panes
- Toggle a full-width preview panel at the bottom

## Installation
```sh
ya pkg add terrakok/split-tabs
```
or
```sh
# Windows
git clone https://github.com/terrakok/split-tabs.yazi %AppData%\yazi\config\plugins\split-tabs.yazi
# Linux/macOS
git clone https://github.com/terrakok/split-tabs.yazi ~/.config/yazi/plugins/split-tabs.yazi
```

## Configuration
Add this to your `keymap.toml`:
```
[mgr]
prepend_keymap = [
    { on = "\\", run = "plugin split-tabs spl_toggle", desc = "Split-tabs: toggle split tabs mode" },
    { on = "<Tab>", run = "plugin split-tabs spl_switch_tab", desc = "Split-tabs: switch to the other pane" },
    { on = "<F5>", run = "plugin split-tabs spl_copy", desc = "Split-tabs: copy to the other pane" },
    { on = "<F6>", run = "plugin split-tabs spl_move", desc = "Split-tabs: move to the other pane" },
    { on = "P", run = "plugin split-tabs spl_preview", desc = "Split-tabs: toggle preview pane" },
    ...
]
```

### Activate on startup

The plugin also exposes the idempotent `spl_activate` action. Add this to
`~/.config/yazi/init.lua` (create the file if it does not exist):

```lua
ya.emit("plugin", { "split-tabs", "spl_activate" })
```

## Support the Developer

<p align="center">
  <a href="https://www.buymeacoffee.com/terrakok" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-green.png" alt="Buy Me A Coffee" width="200"></a>
</p>

If you enjoy the project and want to support its development, consider buying me a coffee. Your support helps keep this project free and open-source!

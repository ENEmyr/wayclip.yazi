# wayclip.yazi

Copy, cut and paste files between [Yazi](https://github.com/sxyazi/yazi) and the
rest of your Wayland desktop. Yank a file in Yazi and paste it into Nautilus, or
copy a file in Firefox's download list and paste it into Yazi.

Yazi's own yank buffer never leaves Yazi, and the system clipboard never enters
it. This plugin connects the two.

## Requirements

- Yazi 26.9.1 or newer
- Wayland, with `wl-clipboard` installed, which provides `wl-copy` and `wl-paste`

This plugin is Wayland only. It does not work on X11.

## Installation

```sh
ya pkg add ENEmyr/wayclip
```

## Usage

Add three bindings to your `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = "y"
run  = [ "yank", "plugin wayclip" ]
desc = "Yank selected files (also to system clipboard)"

[[mgr.prepend_keymap]]
on   = "x"
run  = [ "yank --cut", "plugin wayclip" ]
desc = "Cut selected files (also to system clipboard)"

[[mgr.prepend_keymap]]
on   = "<C-p>"
run  = "plugin wayclip paste"
desc = "Paste files from system clipboard"
```

Chaining onto `y` and `x` keeps Yazi's own yank buffer intact, so `p` still
pastes what you yanked inside Yazi and `<C-p>` pastes whatever the desktop is
holding. The two buffers stay independent.

With no action argument the plugin mirrors Yazi's yank buffer, publishing a cut
when Yazi has one and a copy otherwise. That is why the same `plugin wayclip`
call works for both bindings above.

If you would rather not involve Yazi's yank buffer, `plugin wayclip copy` and
`plugin wayclip cut` force the action. In that case the plugin uses the current
selection, falling back to the hovered file when nothing is selected.

Reading the yank buffer matters when chaining. Yazi's own `yank` clears the
visual selection as it fills the buffer, so by the time a chained plugin runs
the selection is already empty and only the hovered file would be published.

Optionally, set the notification timeout in your `init.lua`:

```lua
require("wayclip"):setup({ timeout = 5 })
```

## How paste decides between copying and moving

`paste` reads the clipboard and looks for a cut marker before deciding what to
do:

1. If `x-special/gnome-copied-files` is present and begins with `cut`, the files
   are moved.
2. If `application/x-kde-cutselection` is `1`, the files are moved.
3. Otherwise the files are copied.

The URIs themselves come from `text/uri-list`. If an application offers only
`x-special/gnome-copied-files` and no `text/uri-list`, which some GNOME
applications do, the URIs are read from that type instead.

Files are transferred using Yazi's own task system, so you get the same progress
reporting and overwrite prompts as a normal `paste` inside Yazi.

## Differences from wl-clipboard.yazi

This plugin was inspired by [wl-clipboard.yazi](https://github.com/grappas/wl-clipboard.yazi)
by grappas, which covers the Yazi to desktop direction. The URI encoding routine
here is derived from it. These are the differences:

- **Paste works.** `wl-clipboard.yazi` only copies out of Yazi. Files copied in
  another application cannot be pasted into Yazi with it. This plugin reads the
  clipboard as well as writing it, which was the whole reason it exists.
- **Cut is supported.** `wl-clipboard.yazi` has no cut. This plugin publishes a
  cut that GNOME file managers understand, and honours a cut published by other
  applications by moving rather than copying.
- **A GNOME-only clipboard still works.** Some applications publish
  `x-special/gnome-copied-files` without a `text/uri-list`. Reading only
  `text/uri-list` misses those; this plugin falls back.
- **Failures are reported honestly.** `wl-clipboard.yazi` checks
  `if status or status.succes`, where `succes` is a typo for `success`. Since
  `status` is truthy whenever the process ran at all, it reports success even
  when `wl-copy` fails, and then reports the error too. This plugin checks
  `status.success` and shows one message.
- **Transfers use Yazi's task system** rather than being fire and forget, so
  large pastes show progress and conflicts prompt instead of failing silently.

## Limitations

- `wl-copy` can only advertise one MIME type per invocation. A copy is therefore
  published as `text/uri-list`, which every file manager understands, and a cut
  is published as `x-special/gnome-copied-files`, which is the only type that can
  express a cut at all. The practical effect is that a cut made in Yazi is
  visible to GNOME file managers and to Yazi itself, but applications that read
  only `text/uri-list` will not see it.
- The clipboard payload is passed to `wl-copy` as an argument, so a selection is
  bounded by `ARG_MAX`. That is a few thousand paths in practice.
- Only `file://` URIs are handled. Remote URIs on the clipboard are ignored.

## Credits

Inspired by [wl-clipboard.yazi](https://github.com/grappas/wl-clipboard.yazi) by
grappas, MIT licensed. The `encode_uri` routine is derived from that project and
its copyright notice is preserved in `LICENSE`.

## License

MIT. See [LICENSE](LICENSE).

# profiles.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: pick, save and edit ranma profiles, with each profile a file of its own.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/specs/profiles.lua`:

```lua
return { "masshirodev/profiles.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/profiles.ranma ~/.config/ranma/pack/plugins/start/profiles.ranma
```

Needs: ranma 0.4.0 or newer. On 0.4.0 the picker lists only this plugin's own files. The release after 0.4.0 (ranma's `main` until it is out) brings `ranma.profiles()`, `theme.base`, `setup`, and a bad profile theme failing only its own file. With those, the picker lists every profile with where it came from. The plugin asks for each with `ranma.has` and uses what is there.

## What it does

```text
profiles: pick, save and edit ranma profiles.

Needs ranma 0.4.0 or newer. The release after 0.4.0 (main until then)
adds what makes it whole: ranma.profiles(), so the picker shows every
profile and where it came from, not only this folder's; theme.base and
setup in a profile; and a bad profile theme failing only its own file.

A profile is a file: ~/.config/ranma/profiles/<name>.lua returns what
ranma.profile takes,

  return { set = { layout = "monocle" }, theme = { base = "latte" } }

and is declared under its file's name when ranma loads. Saving a file
reloads ranma (it watches every .lua under its config directory), so an
edit shows at once. A file that does not load is listed with its error
instead of taking the plugin down.

leader y p (or `:profiles` in the palette) picks the profile to use, or
none. Every profile is listed, whoever declared it: these files, init.lua,
other plugins (mobile.ranma's `mobile`). Each row says where it came from,
marks the one in use (●), and says when switching to it reloads ranma
(a profile with a `setup`). Names matching profiles.hide are left out.
The picker's last rows:
  + save the look on screen  writes a new file from what is on screen now:
                             the theme, border style, bar position, gaps
                             and the workspace's layout;
  + new profile              writes an empty one and opens it;
  manage...                  edit, rename or delete one of these files, or
                             open another profile's source to read.
Edits open $EDITOR (then $VISUAL, then nvim, vim, nano or vi, the first
found) in a floating pane (profiles.float, in percent). The plugin
never writes a file it did not make: profiles from init.lua or another
plugin can be used and read, not changed. A file of this folder that a
later ranma.profile of the same name replaced (init.lua runs last) is
marked "replaced", so editing it is not expected to show.

`:profiles save NAME`, `:profiles new NAME`, `:profiles edit NAME` do
the same from the palette.

The `profile` bar module shows the profile in use, nothing when none, and
opens the picker when clicked: ranma.bar { right = { "profile", ... } }.

```

## A profile file

`~/.config/ranma/profiles/present.lua`:

```lua
return {
  set = { layout = "monocle" },
  bar = { center = {}, right = { "mode" } },
  theme = { base = "latte", border = { style = "none" } },
  -- Anything init.lua can do. Switching to or from this profile reloads ranma.
  setup = function()
    ranma.bind("f5", "fullscreen")
  end,
}
```

The file's name is the profile's name: letters, digits, `_`, `-` and `.`, and not `none`. What a profile can carry is ranma's [CONFIG.md, "Profiles"](https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md#profiles--ranmaprofilename-def).

"Save the look on screen" writes one like this from what is on screen: the theme by name (`theme.base`), the border style, the bar's position, the gaps, and the shown workspace's layout.

## Keys and commands

| | |
| --- | --- |
| `leader y p` | The picker: the profile to use, or none; then save, new, manage. WM mode ends with it. |
| `:profiles` | The same, from the palette. |
| `:profiles save NAME` | Save the look on screen as `NAME`. |
| `:profiles new NAME` | Write an empty profile `NAME` and open it in the editor. |
| `:profiles edit NAME` | Open this folder's `NAME` in the editor. |
| `:profiles manage` | Edit, rename or delete a file, or read another profile's source. |

`ranma.unbind("y p")` in `init.lua` drops the key; `:profiles` stays in the palette.

## Options

In ranma's settings panel under `profiles`, or with hako's `opts`, or `ranma.set { profiles = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `profiles.hide` | `"zen zen.*"` | Profiles the picker leaves out, as globs separated by spaces. zen.ranma declares one profile per combination of its options, and they are its, not yours to pick. The profile in use is shown even when hidden. |
| `profiles.float` | `80` | The floating editor's width and height, in percent of the workspace. |

## The bar module

```lua
ranma.bar { right = { "profile", "clock" } }
```

`profile` shows the profile in use (nothing when none) and opens the picker when clicked.

## How it works, and its limits

- **Profiles are declared while ranma loads**, so this folder is read then, once per load. ranma watches every `.lua` under its config directory, so writing, renaming or deleting a file reloads it, and the plugin needs no state of its own for what is in the folder.
- **Each file is its own `pcall`**: a syntax error, a wrong field, or a feature this ranma lacks is one row in the picker, with its reason, and a toast. The toast is said when a server starts with a broken file, and on a reload only when the set of broken files changed, so switching profiles does not repeat it.
- **It never writes another's file.** It knows its own declarations by `ranma.profiles()`'s `source`. Profiles from `init.lua` or another plugin can be used, and their source opened to read, but rename, delete and edit are for this folder's files only. A later `ranma.profile` of the same name wins (`init.lua` runs last); such a file is marked `replaced`.
- **Renaming the profile in use** keeps it in use under its new name: the rename sets off a reload that would find the old name gone, so the plugin puts the new one in use after it (`ranma.store("profiles")`).
- **A profile with a `setup` reloads ranma** to switch to or from it, which closes open plugin screens and restarts plugin timers; ranma says so in a toast. Other switches are instant.
- **The folder is fixed**, `~/.config/ranma/profiles/` (ranma's config directory): an option would be set by `init.lua`, which runs after the plugin has already read the folder.

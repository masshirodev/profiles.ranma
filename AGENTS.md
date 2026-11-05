# AGENTS.md

profiles.ranma is a ranma plugin in Lua: `plugin/profiles.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit (the README's "What it does" block is the header verbatim), and
  an option goes in the README's table.
- It must load on the latest ranma release, which CI checks. It uses newer
  ranma features (`ranma.profiles()`, `theme.base`, `setup`) only behind
  `ranma.has`, and skips a profile file that needs one this ranma lacks,
  because a ranma without `theme.base` fails its whole load on one.
- It never writes a file it did not make: only `~/.config/ranma/profiles/*.lua`.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
- Test behaviour on a private server, never the one your terminal runs in:
  unset `RANMA_SOCKET RANMA RANMA_PANE TMUX`, point `RANMA_CONFIG_DIR` and
  the `XDG_*` directories at a temp dir (the runtime dir at a short path: a
  Unix socket's path is limited to about 100 bytes), and drive ranma in a
  private tmux (`tmux -L <name>`). ranma's server outlives tmux: stop a test
  server by the runtime dir in its environment, never by name. Cases worth
  repeating: a good file, a syntax error, a wrong field, a bad theme key, a
  file named `none`; a profile of init.lua's with the same name as a file
  (marked replaced); a profile with a `setup` (the switch reloads, and the
  broken-file toast is not repeated); save the look, new, edit with `$EDITOR`
  set to something missing (the pane stays open saying so), rename the
  profile in use (still in use under its new name), delete (starts on "no").
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.

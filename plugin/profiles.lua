-- profiles: pick, save and edit ranma profiles.
--
-- Needs ranma 0.4.0 or newer. The release after 0.4.0 (main until then)
-- adds what makes it whole: ranma.profiles(), so the picker shows every
-- profile and where it came from, not only this folder's; theme.base and
-- setup in a profile; and a bad profile theme failing only its own file.
--
-- A profile is a file: ~/.config/ranma/profiles/<name>.lua returns what
-- ranma.profile takes,
--
--   return { set = { layout = "monocle" }, theme = { base = "latte" } }
--
-- and is declared under its file's name when ranma loads. Saving a file
-- reloads ranma (it watches every .lua under its config directory), so an
-- edit shows at once. A file that does not load is listed with its error
-- instead of taking the plugin down.
--
-- leader shift+p (or `:profiles` in the palette) picks the profile to use, or
-- none. Every profile is listed, whoever declared it: these files, init.lua,
-- other plugins (mobile.ranma's `mobile`). Each row says where it came from,
-- marks the one in use (●), and says when switching to it reloads ranma
-- (a profile with a `setup`). Names matching profiles.hide are left out.
-- The picker's last rows:
--   + save the look on screen  writes a new file from what is on screen now:
--                              the theme, border style, bar position, gaps
--                              and the workspace's layout;
--   + new profile              writes an empty one and opens it;
--   manage...                  edit, rename or delete one of these files, or
--                              open another profile's source to read.
-- Edits open $EDITOR (then $VISUAL, then nvim, vim, nano or vi, the first
-- found) in a floating pane (profiles.float, in percent). The plugin
-- never writes a file it did not make: profiles from init.lua or another
-- plugin can be used and read, not changed. A file of this folder that a
-- later ranma.profile of the same name replaced (init.lua runs last) is
-- marked "replaced", so editing it is not expected to show.
--
-- `:profiles save NAME`, `:profiles new NAME`, `:profiles edit NAME` do
-- the same from the palette.
--
-- The `profile` bar module shows the profile in use, nothing when none, and
-- opens the picker when clicked: ranma.bar { right = { "profile", ... } }.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Profiles",
-- "Pickers and prompts", "Commands").

ranma.option("profiles.hide", {
  type = "string", default = "zen zen.*",
  name = "Hidden", desc = "Profiles the picker leaves out, as globs separated by spaces "
    .. "(zen.ranma declares one profile per combination of its options).",
})
ranma.option("profiles.float", {
  type = "int", min = 30, max = 100, default = 80,
  name = "Editor size", desc = "The floating editor's width and height, in percent of the workspace.",
})

local DIR = ranma.config_dir and (ranma.config_dir .. "/profiles") or nil
local HAS_LIST = ranma.has and ranma.has("profiles")
local HAS_BASE = ranma.has and ranma.has("profile.theme_base")
local HAS_SETUP = ranma.has and ranma.has("profile.setup")
-- Whether ranma.profiles() names this file as a declaration's source. Lua's
-- debug library is not in ranma's, so the file is known by its place in the
-- package; with OWN (what this load declared) that is never another's.
local function from_self(source)
  return source ~= nil and source:match("/plugin/profiles%.lua$") ~= nil
end
local store = ranma.store("profiles")

local function valid_name(n)
  return type(n) == "string" and n:match("^[%w_%-%.]+$") ~= nil and n ~= "none"
end

local function path_of(name)
  return DIR .. "/" .. name .. ".lua"
end

local function exists(p)
  local f = io.open(p, "r")
  if f then f:close() end
  return f ~= nil
end

local function shq(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function tilde(p)
  local home = os.getenv("HOME")
  if home and p:sub(1, #home + 1) == home .. "/" then return "~" .. p:sub(#home + 1) end
  return p
end

-- The folder's files, declared now: OWN[name] = its path, BROKEN[name] = why
-- it did not load. Each file is its own pcall, so one typo is one row.
local OWN, BROKEN = {}, {}
if DIR then
  local found = {}
  -- -L: a dotfiles repo links the folder (or a file in it) in, and find
  -- does not follow a link it starts from without it.
  local ls = io.popen("find -L " .. shq(DIR) .. " -maxdepth 1 -type f -name '*.lua' 2>/dev/null")
  if ls then
    for p in ls:lines() do found[#found + 1] = p end
    ls:close()
  end
  table.sort(found)
  for _, p in ipairs(found) do
    local name = p:match("([^/]+)%.lua$")
    if not valid_name(name) then
      BROKEN[name or p] = "not a profile name (letters, digits, _ - . only, and not `none`)"
    else
      local ok, def = pcall(dofile, p)
      if not ok then
        BROKEN[name] = tostring(def)
      elseif type(def) ~= "table" then
        BROKEN[name] = "returns " .. type(def) .. ", not a profile's table"
      -- Checked before ranma sees them: a ranma without theme.base fails
      -- its whole load on one, not the call, so it is never declared there.
      elseif type(def.theme) == "table" and def.theme.base ~= nil and not HAS_BASE then
        BROKEN[name] = "theme.base needs a newer ranma than this one"
      elseif def.setup ~= nil and not HAS_SETUP then
        BROKEN[name] = "setup needs a newer ranma than this one"
      else
        -- Called from a function of this file, not straight from pcall, so
        -- ranma sees this file as the declaration's source.
        local declared, err = pcall(function() ranma.profile(name, def) end)
        if declared then OWN[name] = p else BROKEN[name] = tostring(err) end
      end
      if BROKEN[name] then OWN[name] = nil end
    end
  end
end
-- Why a file did not load, first line only and without what every such
-- message starts with, so the reason fits a picker row.
local function reason(err)
  local r = tostring(err):gsub("\n.*", "")
  r = r:gsub("^runtime error: ", ""):gsub("^syntax error: ", "")
  r = r:gsub('^ranma%.profile%b(): ', "")
  r = r:gsub("^[^:]*/profiles/[^:/]+%.lua:(%d+): ", "line %1: ")
  return r
end
local BROKEN_PATH = {}
for name in pairs(BROKEN) do BROKEN_PATH[name] = path_of(name) end

-- Said when a server starts with a broken file, and on a reload only when
-- the set changed: a switch to a profile with a setup reloads, and would
-- say it again on every switch. A reload runs config_reload before the
-- deferred check, a fresh start does not.
local RELOADED = false
ranma.on("config_reload", function() RELOADED = true end)
do
  local names = {}
  for n in pairs(BROKEN) do names[#names + 1] = n end
  table.sort(names)
  local said = table.concat(names, ", ")
  local before = store:get("broken") or ""
  if said ~= before then store:set("broken", said) end
  if said ~= "" then
    ranma.defer(300, function()
      if RELOADED and said == before then return end
      ranma.toast("profiles: " .. said .. " did not load (leader shift+p lists why)", { urgent = true })
    end)
  end
end

local function glob_match(name, globs)
  for g in (globs or ""):gmatch("%S+") do
    local pat = "^" .. g:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
    if name:match(pat) then return true end
  end
  return false
end

-- Where a profile came from, short: "file", "init.lua", "zen.ranma", ...
local function origin(p)
  if OWN[p.name] and not HAS_LIST then return "file" end
  if OWN[p.name] and from_self(p.source) then return "file" end
  local src = p.source
  if not src then return "?" end
  local pkg = src:match("/([^/]+)/plugin/[^/]+%.lua$")
  if pkg then return pkg end
  return src:match("[^/]+$") .. (p.line and (":" .. p.line) or "")
end

-- Every profile, sorted: ranma's list when it has one, else this folder's.
local function profiles()
  if HAS_LIST then return ranma.profiles() end
  local out, active = {}, ranma.state().profile
  for name, p in pairs(OWN) do
    out[#out + 1] = { name = name, active = name == active, path = p }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function edit(path)
  local pct = ranma.get("profiles.float") or 80
  ranma.open {
    -- $EDITOR, else $VISUAL, else the first of these the machine has. An
    -- editor that fails keeps the pane open saying so, or it would close
    -- before anyone saw why.
    command = "e=${EDITOR:-${VISUAL:-$(command -v nvim || command -v vim || command -v nano || echo vi)}}; "
      .. "$e " .. shq(path) .. " || { echo \"profiles: $e exited with $?\"; read -r _; }",
    float = pct,
    name = "profile " .. (path:match("([^/]+)%.lua$") or path),
  }
end

local function write(path, text)
  os.execute("mkdir -p " .. shq(DIR))
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(text)
  f:close()
  return true
end

local function lua_value(v, indent)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local pad = string.rep("  ", indent + 1)
  local lines = {}
  for _, k in ipairs(keys) do
    lines[#lines + 1] = pad .. k .. " = " .. lua_value(v[k], indent + 1) .. ","
  end
  return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep("  ", indent) .. "}"
end

-- What is on screen now, as a profile: the theme (by name, where ranma can
-- build a profile over another theme), the frame's keys and the layout.
local function current_look()
  local function get(k)
    local ok, v = pcall(ranma.get, k)
    if ok then return v end
  end
  local theme = {}
  if HAS_BASE and get("theme") then theme.base = get("theme") end
  if get("border.style") then theme.border = { style = get("border.style") } end
  if get("bar.position") then theme.bar = { position = get("bar.position") } end
  local gaps = {}
  for _, k in ipairs({ "inner", "outer_horizontal", "outer_vertical",
    "outer_top", "outer_bottom", "outer_left", "outer_right" }) do
    local v = get("gaps." .. k)
    if type(v) == "number" then gaps[k] = v end
  end
  if next(gaps) then theme.gaps = gaps end
  local def = {}
  if next(theme) then def.theme = theme end
  local layout = ranma.state().layout
  if layout then def.set = { layout = layout } end
  return def
end

local HEADER = "-- %s: a ranma profile, for `profile %s` or the profiles picker (leader shift+p).\n"
  .. "-- What it can carry: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md "
  .. "(\"Profiles\").\n"

local function save(name, def, open_after)
  if not DIR then return ranma.notify("profiles: ranma has no config directory to write to") end
  if not valid_name(name) then
    return ranma.notify("profiles: `" .. tostring(name) .. "` is not a profile name")
  end
  local path = path_of(name)
  if exists(path) then return ranma.notify("profiles: " .. tilde(path) .. " already exists") end
  local text
  if def then
    text = HEADER:format(name, name) .. "-- Saved from the look on screen, "
      .. os.date("%Y-%m-%d %H:%M") .. ".\nreturn " .. lua_value(def, 0) .. "\n"
  else
    text = HEADER:format(name, name) .. "return {\n  set = {},\n  bar = {},\n"
      .. "  -- theme = { base = \"latte\", border = { style = \"none\" } },\n"
      .. "  -- setup = function() ranma.bind(\"f5\", \"fullscreen\") end,"
      .. " -- switching to or from it reloads\n}\n"
  end
  local ok, err = write(path, text)
  if not ok then return ranma.notify("profiles: " .. tostring(err)) end
  ranma.toast("profiles: wrote " .. tilde(path))
  if open_after then edit(path) end
end

local function ask_name(title, then_do)
  ranma.input { title = title, on_submit = function(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text ~= "" then then_do(text) end
  end }
end

local function rename(name)
  ask_name("rename " .. name .. " to", function(new)
    if not valid_name(new) then return ranma.notify("profiles: `" .. new .. "` is not a profile name") end
    local to = path_of(new)
    if exists(to) then return ranma.notify("profiles: " .. tilde(to) .. " already exists") end
    local ok, err = os.rename(OWN[name] or BROKEN_PATH[name], to)
    if not ok then return ranma.notify("profiles: " .. tostring(err)) end
    -- The reload this rename sets off would find the profile in use gone;
    -- it is put back in use under its new name instead.
    if ranma.state().profile == name then store:set("use", new) end
  end)
end

local function delete(name)
  local path = OWN[name] or BROKEN_PATH[name]
  ranma.picker {
    title = "delete " .. tilde(path) .. "?",
    items = { { label = "no, keep it" }, { label = "yes, delete it", yes = true } },
    on_select = function(item)
      if not item.yes then return end
      local ok, err = os.remove(path)
      if not ok then return ranma.notify("profiles: " .. tostring(err)) end
      ranma.toast("profiles: deleted " .. tilde(path))
    end,
  }
end

local function actions(p)
  local name = p.name
  local mine = OWN[name] or BROKEN_PATH[name]
  local items = {}
  if mine then
    items[#items + 1] = { label = "edit", detail = tilde(mine), run = function() edit(mine) end }
    items[#items + 1] = { label = "rename", run = function() rename(name) end }
    items[#items + 1] = { label = "delete", run = function() delete(name) end }
  elseif p.source and p.source:sub(1, 1) == "/" then
    items[#items + 1] = { label = "open its source", detail = tilde(p.source)
      .. (p.line and (":" .. p.line) or "") .. " (not written by this plugin)",
      run = function() edit(p.source) end }
  end
  if #items == 0 then return ranma.notify("profiles: nothing to do with " .. name) end
  ranma.picker { title = name, items = items, on_select = function(item) item.run() end }
end

local pick

local function manage()
  local items = {}
  for _, p in ipairs(profiles()) do
    if OWN[p.name] or (p.source and p.source:sub(1, 1) == "/") then
      items[#items + 1] = { label = p.name, detail = origin(p), p = p }
    end
  end
  local broken = {}
  for n in pairs(BROKEN) do broken[#broken + 1] = n end
  table.sort(broken)
  for _, n in ipairs(broken) do
    items[#items + 1] = { label = n, detail = "did not load", p = { name = n } }
  end
  ranma.picker { title = "manage profiles", items = items, on_select = function(item) actions(item.p) end }
end

pick = function()
  local hide = ranma.get("profiles.hide")
  local active = ranma.state().profile
  local items = { { label = "none", detail = (active == nil and "● " or "") .. "the configuration as init.lua sets it", use = false } }
  for _, p in ipairs(profiles()) do
    if not glob_match(p.name, hide) or p.name == active then
      local parts = { (p.active and "● " or "") .. origin(p) }
      if p.reloads then parts[#parts + 1] = "reloads" end
      -- This folder declared it, and a later ranma.profile of the name won:
      -- the file is not what is used, so editing it would show nothing.
      if OWN[p.name] and p.source and not from_self(p.source) then
        parts[#parts + 1] = tilde(OWN[p.name]) .. " replaced"
      end
      items[#items + 1] = { label = p.name, detail = table.concat(parts, " · "), use = p.name }
    end
  end
  local broken = {}
  for n, why in pairs(BROKEN) do broken[#broken + 1] = { n, why } end
  table.sort(broken, function(a, b) return a[1] < b[1] end)
  for _, b in ipairs(broken) do
    items[#items + 1] = { label = b[1], detail = "did not load: " .. reason(b[2]), broken = b[1] }
  end
  items[#items + 1] = { label = "+ save the look on screen", save = true }
  items[#items + 1] = { label = "+ new profile", new = true }
  items[#items + 1] = { label = "manage...", manage = true }
  ranma.picker { title = "profiles", items = items, on_select = function(item)
    if item.save then
      ask_name("save the look as", function(n) save(n, current_look(), false) end)
    elseif item.new then
      ask_name("new profile", function(n) save(n, nil, true) end)
    elseif item.manage then
      manage()
    elseif item.broken then
      edit(BROKEN_PATH[item.broken])
    elseif item.use == false then
      ranma.use_profile(nil)
    else
      ranma.use_profile(item.use)
    end
  end }
end

-- A rename of the profile in use: back in use under its new name.
ranma.on("config_reload", function()
  local want = store:get("use")
  if want then
    store:set("use", nil)
    ranma.use_profile(want)
  end
end)

ranma.command("profiles", function(arg)
  local verb, name = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  if verb == "" then return pick() end
  if verb == "save" then return save(name, current_look(), false) end
  if verb == "new" then return save(name, nil, true) end
  if verb == "edit" then
    local p = OWN[name] or BROKEN_PATH[name]
    if p then return edit(p) end
    return ranma.notify("profiles: no file for `" .. name .. "` in " .. tilde(DIR or "?"))
  end
  if verb == "manage" then return manage() end
  ranma.notify("profiles: save, new, edit or manage, not `" .. verb .. "`")
end, {
  desc = "pick, save or edit a profile",
  args = "[save|new|edit|manage] [name]",
  complete = function() return { "save", "new", "edit", "manage" } end,
})

ranma.bind("shift+p", function() pick() end, { desc = "profiles", exit = true })

ranma.module("profile", {
  render = function()
    local p = ranma.state().profile
    if p then return { text = p, style = "accent" } end
  end,
  on_click = function() pick() end,
})
if ranma.has and ranma.has("hook.profile_change") then
  ranma.on("profile_change", function() ranma.refresh_module("profile") end)
end

-- Fold (Xiaomi, AVF Terminal): mirror every SUPER binding onto a modifier the
-- Android keyboard can type. Android IMEs have no Super/Caps key, so SUPER + 1
-- and friends can't be pressed; they can send Alt (and Ctrl/Shift).
--
-- Loaded from hyprland.lua *before* Omarchy's defaults, so it sees every bind:
--   SUPER + <mods> + key  ->  kept as is (Bluetooth/physical keyboards, caps:super)
--                         +  FOLD_MOD + <mods> + key  (when <mods> has no ALT)
-- SUPER + ALT + ... chords have no free Alt equivalent and are not mirrored;
-- add the ones you need with fold.bind() in bindings.lua.
-- A real binding on the same chord (e.g. ALT + TAB window cycling) always wins
-- over a mirrored one.
-- Change the modifier here (e.g. "CTRL + ALT") if your Android keyboard lacks Alt.
local FOLD_MOD = "ALT"

local state = { taken = {}, mirrors = {} } -- fresh on every config (re)load
fold = { mod = FOLD_MOD, state = state }

-- The Lua state may survive `hyprctl reload`; never wrap our own wrapper.
if hl.bind ~= _G.fold_modifier_bind then
  _G.fold_modifier_orig_bind = hl.bind
end
if hl.unbind ~= _G.fold_modifier_unbind then
  _G.fold_modifier_orig_unbind = hl.unbind
end
local orig_bind = _G.fold_modifier_orig_bind
local orig_unbind = _G.fold_modifier_orig_unbind

local function parse(keys)
  local parts = {}
  for part in tostring(keys):gmatch("[^+]+") do
    table.insert(parts, (part:gsub("^%s+", ""):gsub("%s+$", "")))
  end
  local key = table.remove(parts)
  local mods = {}
  for _, m in ipairs(parts) do
    mods[m:upper()] = true
  end
  return mods, key
end

local function norm(mods, key)
  local list = {}
  for m in pairs(mods) do
    table.insert(list, m)
  end
  table.sort(list)
  return table.concat(list, "+") .. "|" .. tostring(key):lower()
end

local function join(mods, key)
  local order, out = { "SUPER", "CTRL", "ALT", "SHIFT" }, {}
  for _, m in ipairs(order) do
    if mods[m] then
      table.insert(out, m)
      mods[m] = nil
    end
  end
  for m in pairs(mods) do
    table.insert(out, m)
  end
  table.insert(out, key)
  return table.concat(out, " + ")
end

local function mirror_of(keys)
  local mods, key = parse(keys)
  if not mods.SUPER or mods.ALT or not key then
    return nil
  end
  mods.SUPER = nil
  for m in pairs(parse(FOLD_MOD .. " + x")) do
    mods[m] = true
  end
  return join(mods, key)
end

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do
    c[k] = v
  end
  return c
end

-- Bind without mirroring; used for real binds and for fold.bind().
local function claim(keys, dispatcher, opts)
  local mods, key = parse(keys)
  local id = norm(mods, key)
  local m = state.mirrors[id]
  if m then -- a real binding owns this chord: drop the mirrored one
    m.handle:unbind()
    state.mirrors[id] = nil
  end
  state.taken[id] = true
  return orig_bind(keys, dispatcher, opts)
end

_G.fold_modifier_bind = function(keys, dispatcher, opts)
  local handle = claim(keys, dispatcher, opts)
  local alt = mirror_of(keys)
  if alt then
    local mods, key = parse(alt)
    local id = norm(mods, key)
    if not state.taken[id] then
      local o2 = copy(opts)
      state.mirrors[id] = { from = keys, handle = orig_bind(alt, dispatcher, o2) }
      state.taken[id] = true
    end
  end
  return handle
end

_G.fold_modifier_unbind = function(keys, ...)
  local alt = mirror_of(keys)
  if alt then
    local mods, key = parse(alt)
    local id = norm(mods, key)
    local m = state.mirrors[id]
    if m then
      m.handle:unbind()
      state.mirrors[id] = nil
      state.taken[id] = nil
    end
  end
  local mods, key = parse(keys)
  state.taken[norm(mods, key)] = nil
  return orig_unbind(keys, ...)
end

hl.bind = _G.fold_modifier_bind
hl.unbind = _G.fold_modifier_unbind

-- Extra fold-only chords (no mirroring, owns the chord).
function fold.bind(keys, description, dispatcher, options)
  local opts = copy(options)
  opts.description = description
  if type(dispatcher) == "string" then
    dispatcher = hl.dsp.exec_cmd(dispatcher)
  end
  return claim(keys, dispatcher, opts)
end

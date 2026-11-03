-- @manual standalone: lua tools/tests/heal_weapon_selftest.lua
-- heal_weapon_selftest.lua -- the battle driver's guard against a Fight (or GOGO's Mimic of one) by a member whose
-- hand holds a weapon whose blow heals what it hits (#499, Driver:healWeaponPlan; the Heal Rod: ItemProp +27 high
-- nibble $0C).  Synthetic RAM/ROM stubs, no emulator: a controller contract, not play.  Each case runs with the
-- guard on (it must hold) and with M.HEAL_WEAPON_GUARD = false (the control arm: each case the guard changes must
-- go red there).
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")
assert(loadfile("tools/tests/lib/ot6_field.lua"))(H)
local ram, rom = {}, {}
H.readByte = function(a) return ram[a] or 0 end
H.readWord = function(a) return (ram[a] or 0) | ((ram[a + 1] or 0) << 8) end
H.readRomByte = function(a) return rom[a] or 0 end
H.readRomWord = function(a) return (rom[a] or 0) | ((rom[a + 1] or 0) << 8) end
local ITEMS, MAGIC = 0x10000, 0x20000
H.sym = function(s)
  if s == "ItemProp" then return ITEMS elseif s == "MagicProp" then return MAGIC end
  error("sym " .. s)
end
H.log = function() end
local ROD, BLADE, SHIELD = 0x33, 0x10, 0x5A
local function item(id, typ, eff27) rom[ITEMS + id * 30] = typ; rom[ITEMS + id * 30 + 27] = eff27 end
item(ROD, 0x01, 0xC0)      -- a weapon, its blow heals (AttackerEffect_0c)
item(BLADE, 0x01, 0x00)    -- a weapon
item(SHIELD, 0x03, 0x00)   -- a shield
-- actor 0 is character 7 (BATTLE.BCHID $3ED8), whose hands are $1600 + 37*7 + $1F/$20; no Magic row in its
-- command table ($202E, all zero: Fight in every row)
ram[0x3ED8] = 7
local REC = 0x1600 + 37 * 7
local function hands(r, l) ram[REC + 0x1F], ram[REC + 0x20] = r, l end
local function plan(kind, extra)
  local p = { kind = kind }
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end
local function run(guard, r, l, p)
  H.HEAL_WEAPON_GUARD = guard
  hands(r, l)
  local d = H.newFightDriver("heal weapon", {}).driver
  local out = d:healWeaponPlan(0, p)
  H.HEAL_WEAPON_GUARD = nil
  return out
end
local n, said = 0, {}
local function case(what, r, l, p, want, guarded)
  n = n + 1
  local out = run(nil, r, l, p)
  assert(out ~= nil and out.kind == want, string.format("FAIL %s: got %s, want %s", what, out and out.kind or "nil",
    want))
  if guarded then
    local off = run(false, r, l, plan(p.kind, { copy = p.copy, ally = p.ally }))
    assert(off ~= nil and off.kind ~= want, string.format("FAIL %s: the control arm (the guard off) gave %s too",
      what, want))
  end
  said[#said + 1] = what
end
case("a Fight with the Heal Rod in the main hand: the window is handed on", ROD, SHIELD, plan("fight"), "switch", true)
case("a Fight with the Heal Rod in the off hand of a pair: handed on", BLADE, ROD, plan("fight"), "switch", true)
case("GOGO's Mimic of a Fight with the Heal Rod in hand: handed on", ROD, SHIELD,
  plan("mimic", { copy = { cmd = 0x00, atk = 0xEE, mons = 1 } }), "switch", true)
case("a Mimic of a spell with the Heal Rod in hand: kept (the copy is a cast)", ROD, SHIELD,
  plan("mimic", { copy = { cmd = 0x02, atk = 0x01, mons = 1 } }), "mimic", false)
case("a Fight with a blade: kept", BLADE, SHIELD, plan("fight"), "fight", false)
case("a Fight with an empty hand: kept", 0xFF, 0xFF, plan("fight"), "fight", false)
case("a Fight on an ally (the Muddle rule's) with the Heal Rod: kept", ROD, SHIELD, plan("fight", { ally = true }),
  "fight", false)
case("an Item with the Heal Rod in hand: kept", ROD, SHIELD, plan("item"), "item", false)
print(string.format("heal_weapon_selftest: PASS -- %d cases (the guarded ones red with the guard off): %s", n,
  table.concat(said, "; ")))

-- probe_battle11.lua -- watches battle 11 (the South Figaro gate soldier)
-- end-of-battle decision cells and hooks CheckBattleEnd, LoseBattle,
-- WinBattle, BattleEnd_01/_04, ShowMsg, TerminateBattle and UpdateDead so
-- the outcome is attributed to a named routine rather than inferred from a
-- sample.  Fights the soldier the way gen_sfigaro does (same equip stop,
-- same row, H.rideOut) and reports.
--
-- Cells sampled each frame and logged on change:
--   $3A74/$3A76  characters alive (mask / count), rebuilt by UpdateDead.
--   $3A75/$3A77  monsters alive, the other termination condition.
--   $3AA0/$3AA8  the per-entity "target present" bit ($xx.0): an entity
--                that is not PRESENT is not alive, whatever its hp.
--   $3EE4+e*2    status 1 per entity; bits $C2 (wound/petrify/zombie) drop
--                an entity out of $3A74 with its hp untouched.
--   $2F4C/$2F4E  can't-be-targetted / can-be-targetted masks.
--   $3EBC        battle termination flags ($01 game over, $10 banquet
--                timeout, $20 timer expired, $80 zone eater).
--   $1DD1        the FIELD copy of that byte on the way in: bit 5 set on
--                entry ends the battle at the first CheckBattleEnd call,
--                whatever the hp are.
--   $2D6E/$2D6F  the battle script's message command and index.
--   $3A6E/$3EE0  the end-of-battle special event and its enable.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/locke_scenario.mss.lua"

local function map() return H.mapId() & 0x1ff end

-- ------------------------------------------------------------- the watch --
-- byte cells, sampled every frame and logged only when one moves.  Words
-- are listed separately so the log reads as numbers rather than as bytes.
local BYTES = {
  { "3A74 charsAlive", 0x3A74 }, { "3A75 monsAlive", 0x3A75 },
  { "3A76 nChars", 0x3A76 },     { "3A77 nMons", 0x3A77 },
  { "3A78", 0x3A78 },            { "3A79", 0x3A79 },
  { "3AA0 c0pres", 0x3AA0 },     { "3AA2 c1pres", 0x3AA2 },
  { "3AA8 m0pres", 0x3AA8 },
  { "2F4C", 0x2F4C },            { "2F4D", 0x2F4D },
  { "2F4E", 0x2F4E },            { "2F4F", 0x2F4F },
  { "3EBC term", 0x3EBC },       { "3EBD", 0x3EBD },
  { "3EE4 c0st1", 0x3EE4 },      { "3EE5 c0st2", 0x3EE5 },
  { "3EEC m0st1", 0x3EEC },      { "3EED m0st2", 0x3EED },
  { "3A40 asEnemy", 0x3A40 },    { "3A42 charMons", 0x3A42 },
  { "3A46", 0x3A46 },            { "3A95 lastHidden", 0x3A95 },
  { "3A6E endEvent", 0x3A6E },   { "3EE0 endEnable", 0x3EE0 },
  { "2D6E msgCmd", 0x2D6E },     { "2D6F msgIdx", 0x2D6F },
  { "3408", 0x3408 },            { "3409", 0x3409 },
  { "3219 c0atb", 0x3219 },      { "3221 m0atb", 0x3221 },
  { "3A70 nAtk", 0x3A70 },       { "3A7C atkIdx", 0x3A7C },
  { "B3 rowflag", 0x00B3 },
}
local WORDS = {
  { "hpC0", 0x3BF4 }, { "hpM0", 0x3BFC },
}

local watching, prev = false, {}
local function sampleLine()
  local out = {}
  for _, c in ipairs(BYTES) do
    out[#out + 1] = string.format("%s=%02X", c[1], H.readByte(c[2]))
  end
  for _, c in ipairs(WORDS) do
    out[#out + 1] = string.format("%s=%d", c[1], H.readWord(c[2]))
  end
  return table.concat(out, " ")
end

local function watchTick()
  if not watching then return end
  local changed = {}
  for _, c in ipairs(BYTES) do
    local v = H.readByte(c[2])
    if prev[c[1]] ~= v then
      changed[#changed + 1] = string.format("%s %s->%02X", c[1],
        prev[c[1]] and string.format("%02X", prev[c[1]]) or "--", v)
      prev[c[1]] = v
    end
  end
  for _, c in ipairs(WORDS) do
    local v = H.readWord(c[2])
    if prev[c[1]] ~= v then
      changed[#changed + 1] = string.format("%s %s->%d", c[1],
        prev[c[1]] and tostring(prev[c[1]]) or "--", v)
      prev[c[1]] = v
    end
  end
  if #changed > 0 then
    H.log(string.format("[watch f%d] %s", H.frame, table.concat(changed, "  ")))
  end
end

-- ------------------------------------------------------------- the hooks --
-- Each hook prints the whole sampled state, not just its own name.
-- H.sym requires a literal string argument at each call site; H.sym(name)
-- with a variable does not resolve.
local fires = {}
local function hook(name, addr, cap)
  local n = 0
  emu.addMemoryCallback(function()
    n = n + 1
    fires[name] = n
    if n > (cap or 8) then return end
    local st = emu.getState()
    H.log(string.format("[hook f%d] %s #%d @$%06X a=%02X x=%04X | %s",
      H.frame, name, n, addr, st["cpu.a"] & 0xFF, st["cpu.x"] & 0xFFFF,
      sampleLine()))
  end, emu.callbackType.exec, addr, addr)
  H.log(string.format("hooked %s at $%06X", name, addr))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
  end),
  H.equipLoadout(1, {
    { 0, 0x00 }, -- Dirk: the only weapon in this checkpoint's bag
    { 2, 0x69 }, -- Leather Hat
    { 3, 0x84 }, -- LeatherArmor
  }, { tag = "LOCKE battle-11 control kit" }),
  H.setRows({ [1] = true }, { tag = "locke solo rows" }),

  H.call(function()
    -- $1DD1 is the field copy of the battle-termination byte on the way
    -- in; bit 5 set ends the battle at the first CheckBattleEnd call
    -- regardless of hp.
    local bsw = {}
    for a = 0x1DC9, 0x1DD8 do bsw[#bsw + 1] = string.format("%02X", H.readByte(a)) end
    H.log(string.format("pre-battle: $1DD1=%02X $1DD2=%02X $1DC9..$1DD8=%s",
      H.readByte(0x1DD1), H.readByte(0x1DD2), table.concat(bsw, " ")))
    H.log(string.format("pre-battle: obj26 at (%d,%d), party at (%d,%d)",
      H.objX(26), H.objY(26), H.fieldX(), H.fieldY()))
    local bag = {}
    for i = 0, 63 do
      local id, q = H.readByte(0x1869 + i), H.readByte(0x1969 + i)
      if id ~= 0xFF and q > 0 then
        bag[#bag + 1] = string.format("$%02X x%d", id, q)
      end
    end
    H.log("pre-battle bag: " .. table.concat(bag, " "))
    local r = 0x1600 + 37
    H.log(string.format("pre-battle LOCKE: L%d hp %d/%d gear %02X %02X %02X %02X %02X  gp=%d",
      H.readByte(r + 8), H.readWord(r + 9), H.readWord(r + 11),
      H.readByte(r + 0x1F), H.readByte(r + 0x20), H.readByte(r + 0x21),
      H.readByte(r + 0x22), H.readByte(r + 0x23),
      H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16)))
    -- $3A7C is the attack index ExecAttack works from, $3A70 is the
    -- engine's one multi-hit counter (0 = one attack), and $B3 bit 7 is
    -- what the row code reads to decide whether to halve the hit.
    hook("ShowAttackName", H.sym("ShowAttackName"), 40)
    hook("CheckBattleEnd", H.sym("CheckBattleEnd"), 60)
    hook("LoseBattle", H.sym("LoseBattle"), 8)
    hook("WinBattle", H.sym("WinBattle"), 8)
    hook("BattleEnd_01", H.sym("BattleEnd_01"), 8)
    hook("BattleEnd_04", H.sym("BattleEnd_04"), 8)
    hook("ShowMsg", H.sym("ShowMsg"), 16)
    hook("TerminateBattle", H.sym("TerminateBattle"), 8)
    hook("UpdateDead", H.sym("UpdateDead"), 0)
    emu.addEventCallback(function() watchTick() end, emu.eventType.startFrame)
    watching = true
  end),

  H.talkToObj(26, "gate soldier (battle 11)"),
  H.rideOut("ride battle 11 out", 30000, 75),

  H.call(function()
    watching = false
    local t = {}
    for k, v in pairs(fires) do t[#t + 1] = string.format("%s=%d", k, v) end
    table.sort(t)
    H.log("hook fire counts: " .. table.concat(t, " "))
    H.log(string.format("after: map=%d (%d,%d) $1DD1=%02X",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x1DD1)))
    H.log(string.format("outcome: %s",
      (H.fieldX() == 47 and H.fieldY() == 43) and "SCENARIO RESET (loss)"
        or "not the reset tile"))
  end),
})

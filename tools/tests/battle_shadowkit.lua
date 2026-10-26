-- @suite slow savestate=wor_colosseum
-- battle_shadowkit.lua -- SHADOW's throwing kit (#383, kits.md "Shadow"): the skeans pierce, and the smoke
-- and exit tricks reach one more ally per boost point.
--
--   tools/tests/run.sh tools/tests/battle_shadowkit.lua
--
-- The rules.
--   * A Fire Skean, Water Edge or Bolt Edge resolves as its spell ($51-$53, ThrowToolsOffsetTbl), and since
--     #383 that spell carries the pierce class (Ot6SkillClassTbl), so a thrown skean chips a pierce-weak body
--     by its class as well as by its element.
--   * A thrown Shadow Edge (the smoke: Image) or Inviz Edge (the exit: Vanish) covers the thrower and, per
--     boost point, the next living ally in battle order after him (Ot6TrickReach, ot6_shadow.asm, between
--     the item path's target mask and ExecAttack), passing over an ally it cannot land on (under Vanish, or
--     for the smoke already doubled).  At 0 BP it is vanilla: the thrower alone.
--
-- Boots wor_colosseum (gen_wor_colosseum's end: SHADOW, CELES, CYAN and TERRA on the Falcon's tile by
-- Maranda, the bag holding the skeans and edges Maranda's weapon counter sold), walks into the plain's pool
-- (world group 49: every formation holds a pierce-keyed body, the Crawler, Sprinter or Spek Tor) and plays
-- one battle through the real menu (H.kitBattle; the others Defend while the plan runs):
--   1. SHADOW throws a Fire Skean at 0 BP: a class chip lands (Ot6ClassChip's shield store, the attack's
--      class byte pierce, the queued action Throw of $AB) on a pierce-keyed body.
--   2. SHADOW throws a Shadow Edge at 0 BP: the mask Ot6TrickReach returns is SHADOW alone, and nobody
--      else gains Image from it.
--   3. SHADOW throws an Inviz Edge at 1 BP: the mask is SHADOW and the next standing ally after him; each
--      masked member holds Vanish after it.
--   4. SHADOW throws a Shadow Edge at 2 BP: SHADOW and the next two standing allies; each holds Image.
-- Each trick's mask is read at the proc's own exit (Ot6TrickReachOut) against the boost pending at its
-- entry and the standing mask ($3A74); a member outside a trick's mask gains nothing from it.  Nothing is
-- written.
local H = dofile("tools/tests/lib/ot6.lua")
local TERRA, CYAN, SHADOW, CELES = 0, 2, 3, 6
local STATE = "build/states/wor_colosseum.mss.lua"
local FIRE_SKEAN, INVIZ, SMOKE = 0xAB, 0xAE, 0xAF
local CLASS_PIERCE = 0x02
local ATKCLASS = 0x7E57B8                          -- OT6_ATKCLASS
local REACH, REACH_OUT = H.sym("Ot6TrickReach"), H.sym("Ot6TrickReachOut")
local CLASSCHIP = H.sym("Ot6ClassChip")

local tricks = {}       -- { item, thrower, pend, alive, before, mask, f }
local cur = nil
local chips = {}        -- { slot, from, to, f }: class chips under a thrown Fire Skean
local sets = {}         -- { e, bit, f }: Image/Vanish set on a party member
local watching = false

emu.addMemoryCallback(function()
  if not watching then return end
  local st = emu.getState()
  local x = st["cpu.x"] & 0xFF
  cur = { item = H.readByte(0x3411), cmd = H.readByte(0xB5), thrower = x, pend = H.readByte(0x3E9D + x),
    alive = H.readByte(0x3A74), before = H.readByte(0xB8), f = H.frame, st = {} }
  for e = 0, 7 do cur.st[e] = H.readByte(0x3EE4 + e) end
end, emu.callbackType.exec, REACH, REACH)
emu.addMemoryCallback(function()
  if not watching or cur == nil then return end
  cur.mask = H.readByte(0xB8)
  if cur.cmd == 0x08 and (cur.item == INVIZ or cur.item == SMOKE) then
    tricks[#tricks + 1] = cur
    H.log(string.format("[trick] f%d $%02X thrown by entity %d at %d BP pending: mask $%02X (before $%02X), "
      .. "standing $%02X", cur.f, cur.item, cur.thrower, cur.pend, cur.mask, cur.before, cur.alive))
  end
  cur = nil
end, emu.callbackType.exec, REACH_OUT, REACH_OUT)
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  local s = emu.getState()
  local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
  if pc < CLASSCHIP or pc >= CLASSCHIP + 0x80 then return end
  if H.readByte(0x3A7C) ~= 0x08 or H.readByte(0x3A7D) ~= FIRE_SKEAN then return end
  local e = addr - 0x7E3E38
  local slot = (e - 8) // 2
  chips[#chips + 1] = { slot = slot, to = v, cls = emu.read(ATKCLASS, emu.memType.snesMemory),
    row = H.readByte(0x3E9C + e), f = H.frame }
  H.log(string.format("[chip] f%d the Fire Skean's class chip on monster %d: shields -> %d (attack class $%02X, "
    .. "its class row $%02X)", H.frame, slot, v, chips[#chips].cls, chips[#chips].row))
end, emu.callbackType.write, 0x7E3E38 + 8, 0x7E3E38 + 0x13)
local last = {}
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  local off = addr - 0x7E3EE4
  local e, byte = off & 0xFE, off & 1
  if e > 6 then return end
  local bit = byte == 0 and 0x10 or 0x04       -- Vanish (status 1 $10), Image (status 2 $04)
  local was = last[off] or 0
  last[off] = v
  if (v & bit) ~= 0 and (was & bit) == 0 then
    sets[#sets + 1] = { e = e, bit = byte == 0 and "Vanish" or "Image", f = H.frame }
    H.log(string.format("[status] f%d entity %d gains %s", H.frame, e, byte == 0 and "Vanish" or "Image"))
  end
end, emu.callbackType.write, 0x7E3EE4, 0x7E3EEB)

-- the seats a trick at this boost should cover: the thrower, then the next standing seats after him that it
-- can land on (not under Vanish, which a thrown item misses; for the smoke, not already doubled), read at the
-- proc's entry
local function expect(t)
  local m, left, e = (1 << (t.thrower // 2)), t.pend, t.thrower
  for _ = 1, 3 do
    e = (e + 2) % 8
    local b = 1 << (e // 2)
    local can = (t.st[e] & 0x10) == 0 and not (t.item == SMOKE and (t.st[e + 1] & 0x04) ~= 0)
    if left > 0 and e ~= t.thrower and (t.alive & b) ~= 0 and can then m, left = m | b, left - 1 end
  end
  return m
end
local function heldAfter(t, bitName, untilF)
  local out = {}
  for _, s in ipairs(sets) do
    if s.bit == bitName and s.f >= t.f and s.f <= math.min(t.f + 900, untilF or t.f + 900) then out[s.e] = true end
  end
  return out
end

local A, B = nil, nil
-- BURN (a global a lab sets ahead of the lib; 0 in the suite): that many random battles on the plain fought
-- first with the route's driver, to vary the encounter history the suite's battle comes from (TESTING.md)
local burnN0 = 0
local K = H.worLegKit({ fight = {}, links = {}, names = { [0] = "TERRA", [2] = "CYAN", [3] = "SHADOW", [6] = "CELES" } })
H.run({ maxFrames = 600000 }, {
  H.loadState(STATE),
  H.cond(function() return type(BURN) == "number" and BURN > 0 end, {
    H.call(function() burnN0 = #H.outcomes end),
    K.pace(function() return #H.outcomes - burnN0 >= BURN end, (type(BURN) == "number" and BURN or 0) + 2,
      "the encounters BURN uses up"),
    H.fieldCare({ threshold = 1.0, tag = "after the burned encounters" }),
  }, {}),
  H.call(function()
    for _, ch in ipairs({ SHADOW, CELES, CYAN, TERRA }) do
      H.assertEq(H.readByte(0x1850 + ch) & 7, 1, string.format("char %d is seated", ch))
    end
    H.assertEq(H.invCountOf(FIRE_SKEAN) >= 1, true, "the bag holds a Fire Skean")
    H.assertEq(H.invCountOf(SMOKE) >= 2, true, "the bag holds two Shadow Edges")
    H.assertEq(H.invCountOf(INVIZ) >= 1, true, "the bag holds an Inviz Edge")
    H.assertEq(H.worldMode(), true, "on the World of Ruin map")
    local x, y = H.worldX(), H.worldY()
    A = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if B == nil and H.worldPassable(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(B ~= nil, true, "a passable tile beside the party")
    H.log(string.format("[kit] pacing (%d,%d) <-> (%d,%d) into the plain's pool", A[1], A[2], B[1], B[2]))
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle on the plain by Maranda"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    local ids, t = H.monsterIds(), {}
    for s = 1, 6 do if ids[s] ~= 0xFFFF then t[#t + 1] = string.format("$%03X", ids[s]) end end
    H.log(string.format("[kit] battle formation $%03X: %s", H.readWord(0x11E0), table.concat(t, " ")))
    for e = 0, 7 do last[e] = H.readByte(0x3EE4 + e) end
    watching = true
  end),
  H.kitBattle({
    { who = SHADOW, cmd = 0x08, row = FIRE_SKEAN, boost = 0 },
    { who = SHADOW, cmd = 0x08, row = SMOKE, boost = 0, self = true },
    { who = SHADOW, cmd = 0x08, row = INVIZ, boost = 1, self = true },
    { who = SHADOW, cmd = 0x08, row = SMOKE, boost = 2, self = true },
  }, { maxFrames = 60000 }),
  H.call(function()
    watching = false
    -- 1. the skean's class chip
    local pierceChip = nil
    for _, c in ipairs(chips) do
      if c.cls == CLASS_PIERCE and (c.row & CLASS_PIERCE) ~= 0 then pierceChip = c end
    end
    H.assertEq(pierceChip ~= nil, true,
      string.format("1. the thrown Fire Skean chips a pierce-keyed body by its class (%d class chip(s) under it)", #chips))
    -- the tricks, in the order thrown
    H.assertEq(#tricks >= 3, true, string.format("three tricks reached Ot6TrickReach (%d)", #tricks))
    local plan = { { SMOKE, 0, "Image" }, { INVIZ, 1, "Vanish" }, { SMOKE, 2, "Image" } }
    for i, p in ipairs(plan) do
      local t = tricks[i]
      H.assertEq(t.item, p[1], string.format("trick %d is $%02X", i, p[1]))
      H.assertEq(t.pend, p[2], string.format("trick %d is thrown at %d BP", i, p[2]))
      local want = expect(t)
      H.assertEq(t.mask & 0x0F, want, string.format("%d. $%02X at %d BP covers the thrower and the next %d standing "
        .. "ally(ies) (mask)", i + 1, p[1], p[2], p[2]))
      local held = heldAfter(t, p[3], tricks[i + 1] and tricks[i + 1].f or nil)
      for e = 0, 6, 2 do
        local b = 1 << (e // 2)
        if (want & b) ~= 0 then
          local had = (t.st[e + (p[3] == "Image" and 1 or 0)] & (p[3] == "Image" and 0x04 or 0x10)) ~= 0
          if (t.st[e] & 0x10) ~= 0 and p[3] ~= "Vanish" then
            -- the thrower under Vanish (the mask always holds him, as vanilla's does): a thrown item is a
            -- physical hit, and it misses a vanished body
            H.assertEq(held[e] == nil, true, string.format("%d. entity %d, the thrower under Vanish, gains no %s "
              .. "(the throw cannot land on him)", i + 1, e, p[3]))
          else
            H.assertEq(held[e] or had, true, string.format("%d. entity %d holds %s after the throw", i + 1, e, p[3]))
          end
        else
          H.assertEq(held[e] == nil, true, string.format("%d. entity %d, outside the mask, gains no %s from the "
            .. "%d-BP throw", i + 1, e, p[3], p[2]))
        end
      end
    end
    H.log("[kit] PASS: the skean pierces; the smoke and exit reach one more ally per point")
  end),
})

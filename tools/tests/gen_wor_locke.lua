-- gen_wor_locke.lua -- the Phoenix Cave's second half: Continue the
-- `wor-phoenix-v1` battery (the cave's save point, party 1 on it, party 2
-- beside the lava switch it pulled), the bridge (party 1 on (23,19), party
-- 2 over it), the Red Dragon (event battle 138), the jump plate (party 2 on
-- (12,23), party 1 across the jumps), the two steps that open the last
-- bridge (party 1 on (10,32), party 2 onto (12,32)), and LOCKE (313 (6,53),
-- _cc2b43): the scene, Phoenix, LOCKE and CELES on the Falcon.  The leg ends
-- there with control; the regroup and the save beside the Falcon are the
-- next arc's (#268).  docs/design/split-party.md has the cave and what
-- this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CELES = 0, 1, 6
local POTION, FENIX, REMEDY, TENT, TINCTURE, RIBBON = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xCA
local MAP_CAVE, MAP_DEEP = 315, 313
local AQUA_RAKE = 3
local FIGHT = { nukeLore = { AQUA_RAKE }, strago = { study = true, pearlWind = true } }
-- the Red Dragon ($153, L67, 30,000 HP; weak ice and water, absorbs fire:
-- route_data pool event 138)
local RED_DRAGON = 0x153
local BOSS_FIGHT = { nukeLore = { AQUA_RAKE } }
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(0xF1), H.invCountOf(TENT), H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end

-- the cave's links (gen_wor_phoenix's; docs/design/split-party.md)
local function plate24() return sw(0x02D4) == 1 or sw(0x02D5) == 1 end
local LINKS = {
  [MAP_DEEP] = {
    { 36, 34, "right", 44, 34, function() return sw(0x02A8) == 1 end },
    { 36, 31, "right", 44, 31 }, { 44, 31, "left", 36, 31 }, { 44, 34, "left", 36, 34 },
    { 25, 17, "left", 9, 17 }, { 9, 17, "right", 25, 17 }, { 6, 19, "down", 6, 24 }, { 6, 23, "up", 6, 19 },
    { 8, 25, "right", 16, 25 }, { 16, 25, "left", 8, 25 }, { 18, 23, "up", 18, 15 }, { 18, 15, "down", 18, 25 },
    { 23, 20, "up", 23, 14 }, { 23, 14, "down", 23, 22 }, { 8, 50, "right", 14, 50 }, { 14, 50, "left", 8, 50 },
  },
  [MAP_CAVE] = {
    { 4, 23, "right", 10, 23, plate24 }, { 10, 23, "left", 4, 23, plate24 },
    { 19, 22, "down", 19, 25 }, { 19, 24, "up", 19, 21 },
  },
}
local function walk(x, y, what, arrive)
  return H.lazy(function()
    return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
      fight = FIGHT, arrive = arrive })
  end)
end
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
local function hold(x, y, id, what)
  return H.seqStep({
    walk(x, y, what),
    H.waitUntil(function() return sw(id) == 1 end, 600, what .. string.format(": $%04X set", id), 1),
    H.call(function() say("plate", what) end),
  })
end
-- a chest, when a side of it can be reached from here over the floor and
-- the links (the walk there by them, then the chest); else a line
local function chestIfNear(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local sx, sy = cx + o[1], cy + o[2]
      for _, z in ipairs({ false, 1, 2 }) do
        if H.bfsReach(nil, nil, z or nil, LINKS[map()] or {}, sx, sy) then
          return H.seqStep({
            walk(sx, sy, what .. ": beside it"),
            H.openChest({ stand = { sx, sy }, face = o[3], bit = bit, what = what, item = item,
              nav = { fight = FIGHT, playBattles = "tactical" } }),
          })
        end
      end
    end
    return H.logStep(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end

-- the key of every battle (reads only)
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d party %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map(), H.activeParty()))
    end, emu.callbackType.exec, addr, addr)
  end)
end

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-phoenix-v1"),
  watches(),
  H.splitBegin(),
  H.call(function() say("wor", "boot") end),
  -- @@setup-end

  -- ---- 1. the bridge: party 1 on (23,19), party 2 over it -----------------------------
  -- @@stage bridge
  hold(23, 19, 0x02D2, "party 1 holds the bridge plate (23,19): the bridge north-south"),
  H.switchParty(2),
  walk(19, 25, "party 2 over the bridge (19,22) -> (19,25)"),

  -- ---- 2. the Red Dragon ---------------------------------------------------------------
  -- @@stage dragon
  -- touch-to-fight (315 NPC_1, _cc2048: battle 138, a game over when
  -- lost).  It wanders its room (18-21,44-48): the walk to its side met it
  -- in the corridor and fought it there under the walk's driver, then the
  -- talk waited on a dragon gone (lab/swl_k1_s0: 'battle $174 WON' then
  -- 'activation round 2' timed out), and a walk planned onto (20,45) found
  -- it in the way (swl_k2_s0: 'no route (19,25)->(20,45)').  So party 2
  -- tops up in the corridor above its room, and the talk, which finds it
  -- where it stands, is made only while it is still shown
  walk(16, 38, "party 2 in the corridor above the Red Dragon's room"),
  H.fieldCare({ threshold = 0.95, tag = "before the Red Dragon" }),
  H.cond(function() return sw(0x069C) == 1 end, {
    H.talkToObj(0x10, "the Red Dragon (315 NPC_1)", nil, function() return sw(0x069C) == 0 end),
  }, {}),
  H.advanceStory(function() return sw(0x069C) == 0 and map() == MAP_CAVE and settled() end, 200000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "the Red Dragon beaten") end),
  H.saveState("wor_locke_dragon.mss"),

  -- ---- 3. the jump plate and the two steps ---------------------------------------------
  -- @@stage steps
  chestIfNear(20, 40, 0x0B1, "Dragon Horn (315 (20,40))"),
  hold(12, 23, 0x02D5, "party 2 holds the jump plate (12,23): the jumps (4,23)-(10,23)"),
  H.switchParty(1),
  walk(23, 21, "party 1 off the bridge plate"),
  door(11, 14, MAP_DEEP, "party 1: -> 313 (13,9)"),
  -- the Ribbon (313 (13,20), treasure bit 171), reached from below by the
  -- jumps of 313's west side; it goes on at once (guidelines.md, "Ribbons
  -- are worth going out of your way for")
  chestIfNear(13, 20, 0x0AB, "Ribbon (313 (13,20))", RIBBON),
  H.lazy(function()
    local m = {}
    -- the members the Relic menu takes: a KO'd or zombied member's A is
    -- refused there (lab/swl2_k4_s7: STRAGO zombied at 0 HP, '4 A presses
    -- on the target were not taken')
    for _, c in ipairs(H.partyRoster(1)) do
      if H.charHp(c) > 0 and (H.charStatus1(c) & 0xC2) == 0 then m[#m + 1] = { c, H.SPLIT_NAMES[c] } end
    end
    return H.dressRelics(m, { tag = "relics with the Ribbon, party 1" })
  end),
  door(6, 7, MAP_CAVE, "party 1: -> 315 (6,12)"),
  hold(10, 32, 0x02C5, "party 1 across the jumps, on the step (10,32)"),
  H.switchParty(2),
  walk(12, 32, "party 2 onto the step (12,32): the last bridge"),
  H.waitUntil(function() return sw(0x02D6) == 1 and settled() end, 1200, "the bridge (10,35) open ($02D6)", 1),
  H.call(function() say("route", "the last bridge") end),

  -- ---- 4. LOCKE -------------------------------------------------------------------------
  -- @@stage locke
  door(16, 52, MAP_DEEP, "party 2: -> 313 (18,52)"),
  walk(18, 54, "party 2 onto (18,54): LOCKE shown"),
  H.waitUntil(function() return sw(0x0698) == 1 end, 600, "LOCKE shown ($0698)", 1),
  walk(6, 53, "party 2 to LOCKE (313 (6,53))", function() return sw(0x00D7) == 1 end),
  H.splitEnd(),
  H.advanceStory(function() return sw(0x00D7) == 1 and sw(0x01F0) == 1 and settled() end, 60000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("wor", "LOCKE joined")
    H.assertEq(H.partyOfChar(LOCKE), 1, "LOCKE in party 1 (_cc3178: char_party LOCKE, 1)")
    H.assertEq(H.partyOfChar(CELES), 1, "CELES in party 1")
    H.assertEq(sw(0x02F1), 1, "LOCKE available ($02F1)")
    H.assertEq(sw(0x01CE), 0, "party switching off: one party again (_cc3178 .. $01CE)")
  end),
  -- LOCKE joins with nothing on (his record is empty since the World of
  -- Balance; the scene gives a ValiantKnife and a Flame Shld to the bag:
  -- _cc3178 .. give_item), so he is dressed from the bag at once
  -- (tools/audit_equipment.py: 'BARE wor_locke.mss: LOCKE', lab/l2)
  H.gearDress({ tag = "LOCKE's gear from the bag" }),
  H.dressRelics({ { CELES, "CELES" }, { LOCKE, "LOCKE" } }, { tag = "relics, CELES and LOCKE" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * LOCKE + 0x1F) ~= 0xFF, true, "LOCKE holds a weapon")
    say("wor", "LOCKE dressed")
  end),
  H.saveState("wor_locke.mss"),
  H.logStep(function()
    return string.format("wor_locke generated: LOCKE L%d joined; %s", H.readByte(0x1600 + 37 * LOCKE + 8),
      H.partiesLine())
  end),
})

-- gen_wor_veldt.lua -- the Gau arc's first leg (docs/design/route-wor-gau.md):
-- Continue the `wor-ragnarok-v1` battery (LOCKE, TERRA, CELES and RELM
-- beside the Falcon south of Narshe), the cabin (TERRA, CELES and RELM:
-- three, so GAU can come), the Veldt until GAU joins after a battle, his
-- kit, and the Veldt cave: the dog, its three chests (the Rage Ring, Allo
-- Ver's box, the Striker), the wall's switch, and the save point before the
-- dog's master: the `wor-veldt-cave-v1` battery, the retry point for the
-- SrBehemoth (gen_wor_gau).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, SABIN, CELES, RELM, GAU = 0, 1, 5, 6, 8, 11
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_VCAVE = 11, 12, 353
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [SABIN] = "SABIN", [CELES] = "CELES", [RELM] = "RELM",
  [GAU] = "GAU" }
-- world tiles (route_data world-entrances 1; landable: the property word's
-- bit 1 clear): the Veldt (group 255) on (199,85); the cave (207,89) -> map
-- 353 (33,61), down on (207,90)
local VELDT_LANDING = { 199, 85 }
local CAVE_DOOR, CAVE_LANDING = { 207, 89 }, { 207, 90 }
-- GAU comes to a party of three or fewer after a Veldt battle, 5/8 of the
-- time (battle_main.asm @4840: `Rand / cmp #$a0`; @2fbb: $fc < 4).  Twelve
-- battles without him is (3/8)^12, 8e-6
local VELDT_BUDGET = 12
-- the cave's doors (route_data map 353: each short entrance to the same
-- map), as links a walk takes by stepping onto the door's tile
local DOORS353 = { { 41, 55, 13, 32 }, { 12, 32, 40, 55 }, { 14, 18, 7, 48 }, { 7, 47, 14, 17 }, { 8, 55, 17, 25 },
  { 17, 24, 8, 54 }, { 40, 45, 13, 25 }, { 12, 25, 39, 45 }, { 23, 52, 42, 7 }, { 42, 6, 23, 51 }, { 55, 8, 50, 47 },
  { 50, 48, 55, 9 }, { 60, 18, 52, 53 }, { 51, 53, 59, 18 } }
local LINKS = {}
for _, d in ipairs(DOORS353) do
  for _, dir in ipairs({ "up", "down", "left", "right" }) do LINKS[#LINKS + 1] = { d[1], d[2], dir, d[3], d[4] } end
end
-- the dog's master: the trigger (59,18) (_cb7a18), the landing of the door
-- (51,53); gen_wor_gau takes it
local MASTER = { 59, 18 }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function lv(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(REVIVIFY), H.invCountOf(TENT),
    H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end
local function kitLine(members)
  local t = {}
  for _, ch in ipairs(members) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
-- the rages GAU knows ($1D2C, one bit a species) and the loadout's eight
-- bytes ($1E1F, rage id + 1, all zero AUTO: kit-gau.md section 4)
local function rageLine()
  local n, ids = 0, {}
  for i = 0, 255 do
    if (H.readByte(0x1D2C + (i >> 3)) >> (i & 7)) & 1 == 1 then n = n + 1; ids[#ids + 1] = string.format("$%02X", i) end
  end
  local l = {}
  for i = 0, 7 do l[#l + 1] = string.format("%02X", H.readByte(0x1E1F + i)) end
  return string.format("GAU knows %d rages (%s); loadout %s", n, table.concat(ids, " "), table.concat(l, " "))
end
-- walk onto (x, y) until the map reads dst (gen_wor_relm's)
local function walkInto(x, y, dst, what, avoid)
  local function there() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.waitUntil(there, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- onto a world door until its field map holds the screen
local function enterFrom(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_locke's)
local function board()
  local n, ph = 0, 0
  local drv = H.fightDriverFor("board", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local battleFrames = 0
  local function offTile()
    return not H.battleLoadStarted() and H.worldSettled() and not H.aboardAirship()
      and (H.worldX() ~= H.readByte(0x1F62) or H.worldY() ~= H.readByte(0x1F63))
  end
  return H.withReset(H.driveUntil(function()
    n = H.airshipControl() and n + 1 or 0
    return n >= 30
  end, 30000, {
    H.cond(offTile, {
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = battleFrames + 1
        if battleFrames >= 3 then drv.frame() end
        return
      end
      if battleFrames > 0 then drv.idle() end
      ph = (ph + 1) % 16
      if H.aboardAirship() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "board the Falcon"), function() n, ph, battleFrames = 0, 0, 0 end)
end
-- the cabin's waiting members (map 12) each ask "Change party members?"
-- (_caf59d); NPC_n is object $10 + n - 1, shown by its switch
-- (gen_wor_locke's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
      if obj == nil and sw(n[3]) == 1 and reach then obj = n end
    end
    return obj
  end
  return H.seqStep({
    board(),
    H.withReset((function()
      local ph = 0
      return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
        H.call(function()
          ph = (ph + 1) % 16
          H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
        end),
      }, "X: to the Falcon's deck (map 11)")
    end)(), function() end),
    walkInto(24, 8, MAP_CABIN, "the deck -> the cabin (map 12)"),
    H.call(function() pickTalker() end),
    H.cond(function() return obj == nil end, {
      H.navTo(23, 44, { maxFrames = 3000, arrive = function() return H.fieldY() < 40 end }),
      H.waitUntil(function() return settled() and H.fieldY() < 40 end, 1200, "up the cabin's stairs", 1),
      H.call(function() pickTalker() end),
    }, {}),
    H.call(function()
      H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
      H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
    end),
    H.lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      local n = 0
      for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("%s is in party 1 after the regroup", NAMES[ch]))
      end
      H.assertEq(n, #members, "party 1 holds exactly the regroup's members")
      say("regroup", "after the menu")
    end),
  })
end
-- lift off from the deck's wheel (_caf532: face left, A held on (15,8))
local function liftOff()
  return H.seqStep({
    H.navTo(15, 8, { maxFrames = 3000 }),
    H.faceAndHoldA("left", function() return H.dialogWaiting() end, 1200, "the Falcon's wheel (11 (15,8)): face left, A"),
    H.release(),
    H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
  })
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
-- the cave: a walk over its floor and doors
local function cwalk(x, y, what, avoid, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS, { what = what, maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
        avoid = avoid, arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- a chest from the tile below it; a monster chest's battle is played out
-- (the cave's (6,8): event group 153, formation 515, Allo Ver)
local function chest(cx, cy, bit, what, item)
  return H.seqStep({
    cwalk(cx, cy + 1, what .. ": below it", { MASTER }),
    H.openChest({ stand = { cx, cy + 1 }, face = "up", bit = bit, what = what, item = item,
      nav = { fight = FIGHT, playBattles = "tactical" } }),
    H.waitFrames(30),
    H.advanceStory(function() return settled() and not H.battleLoadStarted() end, 60000,
      { playBattles = "tactical", fight = FIGHT }),
    H.call(function() say("chest", what) end),
  })
end
-- Veldt battles, pacing between the landing and a tile beside it, until
-- done() or the budget's battles are fought
local function veldt(done, budget, what)
  local A, B, n0 = nil, nil, nil
  return H.seqStep({
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      A, B, n0 = { x, y }, nil, #H.outcomes
      for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) then B = { bx, by } end
      end
      H.assertEq(B ~= nil, true, what .. ": a passable tile beside (" .. x .. "," .. y .. ")")
      H.log(string.format("[veldt] %s: pacing (%d,%d) <-> (%d,%d)", what, A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function()
      if H.battleLoadStarted() or not H.worldSettled() then return false end
      if done() then return true end
      H.assertEq(#H.outcomes - n0 < budget, true, string.format("%s: done within %d Veldt battles", what, budget))
      return false
    end, 900000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
      H.call(function()
        A, B = B, A
        H.log(string.format("[veldt] %s: %d battle(s); GAU's party byte $%02X", what, #H.outcomes - n0,
          H.readByte(0x1850 + GAU)))
      end),
    }, what),
  })
end

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-ragnarok-v1"),
  watches(),
  H.call(function() say("wor", "boot") end),
  -- @@setup-end

  -- ---- 1. the cabin, the Veldt: GAU -------------------------------------------------
  -- @@stage veldt
  -- three seated: GAU joins only a party of three or fewer.  The three
  -- highest: the Veldt's first battle from this save is the Holy Dragon
  -- (formation 481, route-wor-gau.md finding 2), which TERRA, CELES and
  -- RELM won in 10 of 10 with no one down and SABIN, TERRA and CELES in 8
  -- of 8 at 2.12 deaths a fight (section 7, the hd lab)
  regroup({ TERRA, CELES, RELM }),
  liftOff(),
  H.flyTo(VELDT_LANDING[1], VELDT_LANDING[2], { what = "the Falcon down on the Veldt", fight = FIGHT }),
  H.call(function() H.log("[kit] " .. rageLine()) end),
  veldt(function() return partyOf(GAU) == 1 end, VELDT_BUDGET, "the Veldt until GAU joins"),
  H.call(function()
    say("wor", "GAU joined")
    H.assertEq(H.readByte(0x1EDF) & 0x08, 0x08, "GAU available ($1EDF bit 3: MiscAIEffect_03)")
  end),
  -- his kit from the bag (he holds no weapon: the Fight row is his fists)
  H.gearDress({ tag = "GAU's gear from the bag" }),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { GAU, "GAU" } },
    { tag = "relics with GAU" }),
  H.fieldCare({ tag = "after GAU" }),
  H.call(function()
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, GAU }))
    H.log("[kit] " .. rageLine())
  end),
  H.saveState("wor_veldt_gau.mss"),

  -- ---- 2. the Veldt cave ---------------------------------------------------------------
  -- @@stage cave
  -- GAU with the three who brought him: SABIN, LOCKE and the rest wait aboard
  board(),
  H.flyTo(CAVE_LANDING[1], CAVE_LANDING[2], { what = "the Falcon down by the Veldt cave", fight = FIGHT }),
  enterFrom(CAVE_DOOR, MAP_VCAVE, "the Veldt cave (353)"),
  -- the dog (35,56) (_cb799f: Interceptor shows, then the way he went)
  H.navTo(35, 56, { maxFrames = 3000, arrive = function() return not H.hasControl() end }),
  H.advanceStory(function() return sw(0x0195) == 1 and settled() end, 20000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the dog ($0195)") end),
  chest(18, 20, 0x0BF, "Rage Ring (353 (18,20))"),
  chest(6, 8, 0x0C0, "the monster chest (353 (6,8))"),
  chest(42, 26, 0x0C1, "Striker (353 (42,26))"),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { GAU, "GAU" } },
    { tag = "relics with the cave's" }),
  -- the wall (43,16) (_cb79e6: facing up, A held -> $016E, the way north)
  cwalk(43, 16, "the wall's switch (353 (43,16))", { MASTER }),
  H.faceAndHoldA("up", function() return sw(0x016E) == 1 end, 1200, "the wall (353 (43,16)): face up, A"),
  H.release(),
  H.waitUntil(settled, 1200, "control after the wall", 1),
  H.call(function() say("story", "the wall open ($016E)") end),
  H.saveState("wor_veldt_wall.mss"),

  -- ---- 3. the save point --------------------------------------------------------------------
  -- @@stage save
  cwalk(57, 45, "below the save point (353 (57,44))", { MASTER }),
  H.fieldCare({ threshold = 1.0, tag = "at the cave's save point" }),
  H.call(function()
    say("wor", "at the save point")
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, GAU }))
    H.log("[kit] " .. rageLine())
  end),
  H.saveAtCheckpoint("wor-veldt-cave-v1"),
  H.saveState("wor_veldt.mss"),
  H.logStep(function()
    return string.format("wor_veldt generated: TERRA L%d, CELES L%d, RELM L%d and GAU L%d on the Veldt cave's save "
      .. "point, map 353 (%d,%d), saved in slot 3", lv(TERRA), lv(CELES), lv(RELM), lv(GAU), H.fieldX(), H.fieldY())
  end),
})

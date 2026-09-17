-- gen_zozo1_submerge.lua -- v0.4 step 1a: kefka_won (Arvis's house, map 30
-- {60,37}, LOCKE+CELES+EDGAR+SABIN) -> Narshe streets -> the world -> the
-- east Figaro castle -> the engine-room attendant -> the Kohlingen crossing
-- -> generate figaro_submerged.mss (map 61 {6,34}, castle parked west).

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ANTIDOTE, REMEDY = 0xF2, 0xF5
local SHOP_PROP = H.sym("ShopProp") & 0x3FFFFF   -- shop_prop.dat: 9 bytes per shop, items at +1
local function shopRow(shop, row) return H.readRomByte(SHOP_PROP + shop * 9 + 1 + row) end

-- calm-arrival pred (gen_kefka_won's): n consecutive controllable
-- full-bright field frames on map m
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- cross a CheckDoor door: stand beside it (navTo), then hold `dir` until
-- the destination map is up, then settle.  Doors are walls to bfsPath, so
-- the held press is the only way through (gen_edgar).
local function door(nx, ny, dir, m, what)
  return H.cond(function() return true end, {
    H.navTo(nx, ny, { maxFrames = 12000, playBattles = "tactical" }),
    H.driveUntil(function() return map() == m end, 900, {
      H.hold({ dir }), H.waitFrames(4),
    }, what .. ": through the door"),
    H.advanceStory(landed(m, 10), 2400, { playBattles = "tactical" }),
    H.waitFrames(150),
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 30, "booted in Arvis's house (map 30)")
    H.assertEq(H.fieldX() == 60 and H.fieldY() == 37, true, "at {60,37}")
    H.assertEq(sw(0x010B), 1, "$010B SET -- castle parked EAST")
    H.assertEq(sw(0x0048), 1, "$0048 SET -- the attendant will offer the ride")
    H.assertEq(partyOf(0x01), 1, "LOCKE aboard")
  end),

  -- 1. Arvis's house -> Narshe town by the front door (55,35) -> map 20
  --    {49,14}.  Tier 1's invisible door-NPC no longer stands there
  --    (probe_n30: reachable in 9, tile unoccupied), and the tier-1
  --    corridor exit's (53,8) clifftop position is isolated after the
  --    battle (probe_n20 census after full settle: zero reachable tiles),
  --    so the front door is now the only way to the streets.
  H.navTo(55, 35, { arrive = function() return map() == 20 end,
                    maxFrames = 12000, playBattles = "tactical" }),
  H.waitUntil(landed(20, 10), 1200, "landed on the streets", 1),
  H.waitFrames(150),

  -- 1b. Narshe's item shop on the way out (#176): the door (41,22) is eight
  --     tiles from Arvis's front door, shop 3 on map 26 (shopkeeper (44,8);
  --     _ccd28c opens 3 while $006B/$00A4 are clear, both clear here), rows
  --     TONIC 0 / POTION 1 / FENIX DOWN 4.  Every town tops up, and this is
  --     the last TONIC counter before the post-opera checkpoint: Jidoor's
  --     shop 22 (gen_zozo2_arrival's stop after the L18 grind) sells none,
  --     and the #158 chain walked the grind and the Zozo climb from 82 Tonics
  --     to 14 (zozo_arrival attempt 3 "[west landing] ... tonic=82";
  --     zozo_done "[care before leaving Zozo] ... tonic=14").  No Potion
  --     line: Nikeah's stop (gen_sabin_trench) now carries 27 to here
  --     (kefka_won potion=27, over the L14 band of 21) and Jidoor buys the
  --     L18 band after the grind, so a POTION line here buys nothing.
  H.call(function()
    H.vars.shopStart = H.frame
    H.assertEq(sw(0x006B), 0, "$006B clear -- the item shop opens as shop 3")
    H.assertEq(sw(0x00A4), 0, "$00A4 clear -- the item shop opens as shop 3")
    H.log(string.format("[shop] Narshe stop begins f%d: gil=%d tonic=%d potion=%d fenix=%d",
      H.frame, H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.crossDoor(41, 22, 26, 44, 13, "item shop door 20(41,22)->26(44,13)"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
    "shop interior settled", 10),
  H.waitFrames(60),
  H.shopTalk(44, 8, "Narshe item shop"),
  H.call(function()
    -- event command $9b parks the shop number at $0201 (field/event.asm:3656);
    -- the rows come from the ROM table, since the menu fills its $7E9D89 row
    -- list only once the buy list is drawn.
    H.assertEq(H.readByte(0x0201), 3, "the counter opened shop 3 ($0201)")
    H.assertEq(shopRow(3, 0), TONIC, "shop 3 row 0 is Tonic")
    H.assertEq(shopRow(3, 1), POTION, "shop 3 row 1 is Potion")
    H.assertEq(shopRow(3, 4), FENIX_DOWN, "shop 3 row 4 is Fenix Down")
  end),
  H.buyItem(FENIX_DOWN, 4, function() return 15 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.call(function()
    H.log(string.format("[shop] Narshe item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), H.gil(), H.frame))
  end),
  H.shopClose("Narshe item shop"),
  -- #197: the combat items back on top of the bag after every purchase
  -- (the fight driver found the Potion at row 43 downstream of a stop
  -- that did not re-arrange)
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top (Narshe item shop)" }),
  H.call(function()
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 15, true, "Fenix Downs at 15 for the Zozo stretch")
    H.assertEq(H.invCountOf(TONIC) >= 90, true, "Tonics topped up for the field care")
    H.log(string.format("[shop] leaving the shop: gil=%d tonics=%d potions=%d fenix=%d",
      H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.crossDoor(44, 14, 20, 41, 24, "item shop door 26(44,14)->20(41,24), return"),
  H.call(function()
    H.log(string.format("[shop] Narshe stop cost %d frames (f%d -> f%d)",
      H.frame - H.vars.shopStart, H.vars.shopStart, H.frame))
  end),

  -- 2. the south gate at (38,61) (gen_worldmap's verified tile), then one
  --    held step south onto the y=62 exit row -> world {83,36}
  H.navTo(38, 61, { maxFrames = 20000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off the south edge to the world"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 1200, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] at (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- 3. to the east castle trigger (64,76): stop one tile north, then step
  --    onto it (the trigger checks $010B and loads map 55 {28,42}).  The
  --    arrive bails if a stray step fires the trigger early; the next
  --    drive's map-55 pred is then already true and holds nothing (holding
  --    down at the gate would step onto y=43, the world-exit row).
  H.worldNavTo(64, 75, { maxFrames = 30000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() and map() == 55 end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "onto the castle trigger"),
  H.waitUntil(landed(55, 10), 1500, "castle gate up", 1),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[castle] map 55 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  door(28, 39, "up", 59, "into the keep"),
  H.saveState("_scratch_keep59.mss"),   -- cheap re-entry for route iteration
  H.navTo(9, 49, { arrive = function() return map() == 61 end,
                   maxFrames = 9000, playBattles = "tactical" }),
  H.waitUntil(landed(61, 10), 1500, "engine room", 1),
  H.waitFrames(150),

  -- 5. the attendant at {6,33}: stand below at (6,34), face up (a held up
  --    turns in place, because the NPC blocks the step), then edge-A.
  --    (6,34) keeps the route off (5,35), the "That's dangerous!" shoo
  --    trigger (_ca69cd) that takes control every frame it is stood on.
  H.navTo(6, 34, { maxFrames = 9000, playBattles = "tactical" }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(4),
  (function()
    local aPh = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the attendant answers")
  end)(),
  H.call(function()
    H.log(string.format("[attendant] dlg up, $056E=%d", H.readByte(0x056e)))
  end),

  -- 6. tap through the greeting into the choice; index 0 = Kohlingen; then
  --    ride the crossing hands-off (advanceStory: dialog-gated taps only)
  H.advanceStory(landed(61, 60), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 61, "back in the engine room")
    H.assertEq(sw(0x010C), 1, "$010C SET -- castle parked WEST")
    H.assertEq(sw(0x010B), 0, "$010B clear -- no longer east")
    H.log(string.format("[figaro_submerged] f%d map=%d (%d,%d) parent=(%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x1f69 + 2), H.readByte(0x1f69 + 3)))
    H.screenshot("figaro_submerged")
  end),
  H.saveState("figaro_submerged.mss"),
  H.logStep(function()
    return string.format("figaro_submerged generated at frame %d", H.frame)
  end),
})

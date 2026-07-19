-- gen_terra_narshe.lua -- from rapids_done.mss across the World of Balance
-- into NARSHE, and through the townsfolk's turn-away at the checkpoint.
-- Mints one state:
--   terra_narshe.mss  map 20 (39,53), EDGAR leading TERRA and BANON, first
--                     controllable frame after the "Get out of here!" scene,
--                     with $001F set.  The doorstep for the rest of the
--                     scenario, and deliberately its own link: everything
--                     past here goes through the secret wall and the mines,
--                     which is the part worth iterating on.
--
-- THE WORLD LEG is short and dull: `load_map 0, {93,41}` drops the party
-- north-east of Narshe and the town's world tile is (84,33) -> map 20
-- (38,61) (ShortEntrance::_0).  21 steps, planned by worldBfs and asserted
-- to exist before it is walked.
--
-- ============ THE CHECKPOINT IS A WALL, NOT A SPEED BUMP ============
-- Map 20's south strip and the rest of Narshe are joined by ONE three-tile
-- corridor, and the checkpoint sits on it.  Measured, not assumed: a flood
-- over the engine's own passability rules (transcribed from
-- field/player.asm, reachability probe run during development) reaches 834
-- tiles spanning y 0..63 from the arrival tile, and 231 tiles spanning
-- y 50..63 with just {37,50}/{38,50}/{39,50} sealed.  Those three tiles are
-- _ccb205/_ccb230/_ccb21d (event_trigger.asm:111-113) and they re-fire for
-- as long as the scenario is unfinished:
--     _ccb230  $0019=1, $001F=0  -> the long scene, ends `switch $001F=1`
--     _ccb205  once $001F=1      -> goto _ccb35c -> _ccb37f, the short one
--     _ccb37f  guard: $0019=1 AND $001F=1 AND $0021=0   (:104721-104726)
-- and _ccb37f ends by shoving SLOT_1 five tiles south (:104768).  So the
-- party cannot walk into Narshe at all during this scenario -- which is the
-- point of the scene, and why the way onward is the secret wall at (15,57)
-- that gen_terra_done handles, not a smarter path north.
--
-- THE SCENE NEEDS A, NOT JUST A DIRECTION.  _ccb230 opens with five dialogs
-- ($01A0 at :104526 through $01A4 at :104607) and every one waits for a
-- keypress.  A first cut drove the step onto the checkpoint by holding UP
-- alone and timed out after 3000 frames sitting at (38,51) with $001F still
-- clear -- the trigger had fired and the scene was parked on "Hey, lady…".
-- So the held-UP phase ends the moment the event picks up, and advanceStory
-- (which taps dialogs) owns everything after that.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DONE = "/Users/mtklein/ot6/build/states/rapids_done.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

-- n consecutive settled field frames on `m`, saying why it is not satisfied
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local okMap = map() == m
    local okCtl, okAlign = H.hasControl(), H.tileAligned()
    local okBright, okBatt = bright() >= 15, not H.battleLoadStarted()
    local okDlg = not H.dialogWaiting()
    local ok = okMap and okCtl and okAlign and okBright and okBatt and okDlg
           and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d blocked: map=%s(%d) ctl=%s algn=%s " ..
        "bright=%s(%d) batt=%s dlg=%s world=%s at (%d,%d) ev=%s", m, H.frame,
        tostring(okMap), map(), tostring(okCtl), tostring(okAlign),
        tostring(okBright), bright(), tostring(okBatt), tostring(okDlg),
        tostring(H.worldMode()), H.fieldX(), H.fieldY(),
        tostring(H.eventRunning())))
    end
    return cnt >= (n or 20)
  end
end

-- ONE INSTANCE PER USE SITE.  landed() returns a closure with a consecutive
-- frame counter in it; calling landed(20)() inline builds a fresh counter
-- every frame, so it reads 1 forever.  That is exactly how the first cut of
-- this file failed: the party sat at (39,53) with ctl/algn/bright/batt all
-- reading fine for 30,000 frames and the settle predicate never once
-- returned true.
local settleArrival, settleScene = landed(20), landed(20)

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) ctl=%s $0019=%d $001F=%d " ..
    "$0020=%d $0021=%d $01F0=%d", tag, H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), sw(0x0019), sw(0x001F), sw(0x0020), sw(0x0021),
    sw(0x01F0)))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DONE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "booted on the world map")
    H.assertEq(H.worldX(), 93, "world (93,41): x")
    H.assertEq(H.worldY(), 41, "world (93,41): y")
    H.assertEq(sw(0x0019), 1, "$0019 set -- the river was run")
    H.assertEq(sw(0x001F), 0, "$001F clear -- the townsfolk have not turned us away")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
    local p = H.worldBfs(84, 33)
    H.assertEq(p ~= nil, true, "Narshe's world tile (84,33) is reachable")
    H.log(string.format("world leg: (%d,%d) -> (84,33), %d steps",
      H.worldX(), H.worldY(), #p))
  end),

  -- ===================================================================== --
  -- THE WORLD LEG: (93,41) -> (84,33) -> map 20 (38,61).
  -- ===================================================================== --
  H.worldNavTo(84, 33, { maxFrames = 40000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  H.advanceStory(settleArrival, 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 20, "on map 20, the Narshe streets")
    H.assertEq(H.fieldX(), 38, "arrival tile x=38")
    H.assertEq(H.fieldY(), 61, "arrival tile y=61 (world (84,33) -> map 20 (38,61))")
    where("narshe arrival")
    H.screenshot("terra_narshe_arrival")
  end),

  -- ===================================================================== --
  -- THE CHECKPOINT.  navTo stops one tile short at (38,51) so the trigger
  -- fires on OUR held step rather than in the middle of a plan, then the
  -- scene is handed to advanceStory the instant it picks up.
  -- ===================================================================== --
  H.navTo(38, 51, { maxFrames = 12000 }),
  H.release(),
  H.call(function() where("checkpoint doorstep") end),
  H.driveUntil(function()
    return H.eventRunning() or H.dialogWaiting() or sw(0x001F) == 1
  end, 3000, {
    H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(4),
  }, "step onto the checkpoint (38,50) and start _ccb230"),
  H.release(),
  H.call(function() where("_ccb230 running") end),
  H.advanceStory(function()
    return sw(0x001F) == 1 and settleScene()
  end, 30000),
  H.waitFrames(30),

  H.call(function()
    H.assertEq(map(), 20, "still on map 20")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x001F), 1, "$001F set -- _ccb230 ran to its end (:104697)")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    -- _ccb230 ends `party_chars EDGAR` (:104694), so EDGAR leads from here
    H.assertEq(H.fieldX(), 39, "shoved back to x=39")
    H.assertEq(H.fieldY(), 53, "shoved back to y=53 -- south of the checkpoint")
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA still in the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR still in")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON still in")
    -- the secret wall the next link opens has not been touched
    H.assertEq(sw(0x01F0), 0, "$01F0 clear -- the rock wall is still shut")
    H.assertEq(sw(0x0020), 0,
      "$0020 clear -- so _ccb133 takes the _ccb154 branch, this scenario's")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    where("terra_narshe")
    H.screenshot("terra_narshe")
  end),
  H.saveState("terra_narshe.mss"),
  H.logStep(function()
    return string.format("terra_narshe minted at frame %d", H.frame)
  end),
})

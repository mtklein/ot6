-- gen_kolts_cave.lua -- one crossing past kolts_pool, for the OTHER Mt. Kolts
-- pool: the one the mountain is actually made of.
--
--   kolts_cave.mss   map 96 region P, party in control and tile-aligned.
--
-- WHY THIS EXISTS.  kolts_pool.mss stands on map 100 (shelf F), whose
-- encounter group is 63 -- Brawler-pair 62.5% / Tusker-pair 37.5%.  That is
-- ONE of the mountain's four groups, and Measurement #7 measured it and
-- reported "two Kolts formations" as though it were the pool.  It is not.
-- Decoding SubBattleGroup for every Mt. Kolts map (field/battle.asm:391)
-- gives four:
--
--   maps 95/96/97   group 61   Cirpius x3 (93.75%), +Tusker in slot 1
--   maps 98/99/102  group 62   Trilium-pair 62.5%, Trilium+Tusker+Cirpius x2
--   map  100        group 63   Brawler-pair / Tusker-pair   <- kolts_pool
--   map  101        group 64   Brawler+Trilium+Vaporite x2 / Tusker-pair
--
-- Group 61 is the one that matters most and the one nothing has ever
-- measured: CIRPIUS ($0086) is 93.75% of its draws, it arrives THREE AT A
-- TIME, and until the v0.3 trash pass it had no weakness of any kind
-- (monster_prop.dat +$10D9 = $00) -- so the mountain's single most common
-- fight was three unchippable birds.  The pass gives Cirpius poison, which
-- makes it the one fight in the demo where a GROUP tool answers a GROUP
-- enemy: Bio Blaster targets the whole enemy side (magic_prop_en.dat $7d,
-- targeting byte $6a), so one deliberate action chips all three.  That claim
-- needs a fixture to be a measurement rather than arithmetic, and this is it.
--
-- THE CROSSING is gen_kolts' K2, verbatim: shelf F (19,17) -> map 96 region
-- P.  Everything else -- the danger-counter suppression during the walk, the
-- settle, the "prove an encounter really fires" tail -- is gen_kolts_pool's,
-- and its header carries the reasoning for all three.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local POOL = "/Users/mtklein/ot6/build/states/kolts_pool.mss.lua"
local DANGER = 0x1f6e

local function map() return H.mapId() & 0x1ff end

local function where(tag)
  H.log(string.format("[kolts_cave] f%d map=%d field=(%d,%d) ctrl=%s aligned=%s",
    H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned())))
end

local function settleField(what, dstMap, maxF)
  local held = 0
  return H.driveUntil(function()
    H.writeWord(DANGER, 0)
    local ok = H.hasControl() and H.tileAligned()
      and (dstMap == nil or map() == dstMap)
    held = ok and held + 1 or 0
    return held >= 30
  end, maxF or 12000, { H.call(function() H.setPad({}) end), H.waitFrames(1) },
  "settle " .. what)
end

local function mapChanged()
  local m0 = nil
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(POOL),
  H.waitFrames(30),
  settleField("shelf F", 100),
  H.call(function()
    H.assertEq(map(), 100, "loaded on map 100, Mt. Kolts shelf F")
    where("shelf F")
  end),

  H.call(function() H.writeWord(DANGER, 0) end),
  H.navTo(19, 17, { maxFrames = 20000, arrive = mapChanged() }),
  H.release(),
  settleField("cave 96 P", 96),
  H.call(function()
    H.assertEq(map(), 96, "crossed onto map 96, the Mt. Kolts cave")
    H.writeWord(DANGER, 0)
    where("cave arrival")
  end),

  -- STEP OFF THE TRIGGER BEFORE SAVING.  The crossing lands on (16,22),
  -- and that tile is one of the two event triggers that open each Kolts
  -- cave with a glimpse of the figure on the peak (gen_kolts' header,
  -- :170-171).  A fixture saved standing on it is unmeasurable in a way
  -- that looks like a broken fixture: bal_party's pacer shuffles between
  -- the spawn tile and one neighbour, so every other step RE-ENTERS the
  -- trigger, the cutscene takes control, and the run dies on "timeout
  -- waiting for field control" before a single encounter.  Measured
  -- exactly that on the first mint.  Two tiles east is clear of both
  -- triggers ((16,22) and (14,12)) and still inside region P.
  H.call(function() H.writeWord(DANGER, 0) end),
  H.navTo(18, 22, { maxFrames = 8000 }),
  H.release(),
  settleField("cave 96 P, off-trigger", 96),
  H.call(function()
    H.assertEq(map(), 96, "still on map 96 after stepping clear")
    H.assertEq(H.fieldX(), 18, "spawn tile is (18,22), not the trigger")
    H.assertEq(H.fieldY(), 22, "spawn tile is (18,22), not the trigger")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.writeWord(DANGER, 0)
    where("cave spawn")
    H.screenshot("kolts_cave")
  end),
  H.saveState("kolts_cave.mss"),
  H.logStep(function()
    return string.format("kolts_cave minted at frame %d", H.frame)
  end),

  -- PROOF THE FIXTURE IS WHAT IT CLAIMS, gen_kolts_pool's tail.  The lane is
  -- not named here the way shelf F's "right" is, because map 96 P's arrival
  -- tile is not a tile any earlier script stops on -- so the first walkable
  -- direction is taken and the MAP IS GUARDED.  P's two exits are (16,22)
  -- and (21,21) (gen_kolts' mountain flood); if the shuffle ever reaches
  -- one, this raises with the tile in the message rather than pacing a
  -- different map and reporting it as this one, which is the exact way map
  -- 95 wasted six samples.
  (function()
    local battN, waited, lane, lastXY, steps = 0, 0, nil, nil, 0
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then H.setPad({}) return true end
      if map() ~= 96 then
        error("pacing left map 96 (now " .. map() .. ") after " .. steps
          .. " steps: the lane walked onto an entrance tile", 0)
      end
      return waited >= 7000
    end, 7600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then
              lane = { ax = x, ay = y, out = d, back = BACK[d] }
              break
            end
          end
          if lane == nil then
            error("cave P: no walkable direction from (" .. x .. "," .. y .. ")", 0)
          end
          H.log(string.format("[kolts_cave] lane (%d,%d) %s/%s",
            x, y, lane.out, lane.back))
        end
        local xy = x * 1000 + y
        if lastXY ~= nil and xy ~= lastXY then steps = steps + 1 end
        lastXY = xy
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "an encounter fires in cave 96 P")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.monstersPresent() > 0, true,
      "cave 96 drew a live formation -- map 96 carries an encounter group")
    H.log(string.format("[kolts_cave] formation %s",
      string.format("%04X %04X %04X %04X %04X %04X",
        table.unpack(H.formationWords()))))
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        H.log(string.format("[kolts_cave] mon s%d sp%04X hp%d weak%02X sh%d/%d",
          slot, H.readWord(0x57c0 + slot * 2),
          H.readWord(0x3bfc + slot * 2),
          H.readByte(0x3be8 + slot * 2),
          H.readByte(0x3e40 + slot * 2), H.readByte(0x3e41 + slot * 2)))
      end
    end
  end),
})

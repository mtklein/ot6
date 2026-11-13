-- gen_wob_base_treasure.lua -- a branch beside the voyage (#281, docs/design/wob-side-trips.md section 2):
-- Continue the `banquet-done-v1` battery (TERRA and LOCKE on the world outside Vector, (120,188)), walk east to the
-- Imperial Base (world (165,194) -> map 377), and open the treasure room the Emperor's reward unlocks (map 378, the
-- thirteen chests behind the lock NPC $045D that _cb2566 hides at a banquet score of 67 or more,
-- event_main.asm:99221-99224).  The base's guards are gone by then ($0076, set at the Narshe meeting, hides
-- $045E-$0467, event_main.asm:94179-94189), so the room costs no fight; the walk there fights the world's own pool.
-- Then back to the world by the base.  No leg boots what it leaves (the state `wob_base_treasure`); gen_voyage
-- goes on from the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE = 0, 1
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE" }
local TWO = { TERRA, LOCKE }
local MAP_BASE, MAP_ROOM = 377, 378
local BASE_DOOR = { 165, 194 }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, settled = K.map, K.say, K.kitLine, K.settled
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- map 378's chests (treasure records, route_data.py map 378): x, y, bit, what, item (nil for gil)
local CHESTS = {
  { 50, 42, 110, "X-Potion", 0xEA }, { 51, 42, 111, "Cherub Down", 0xBC }, { 49, 44, 112, "8000 GP" },
  { 51, 44, 113, "Ether", 0xEC }, { 54, 44, 114, "Wall Ring", 0xBB }, { 56, 44, 115, "13000 GP" },
  { 52, 45, 116, "RunningShoes", 0xBA }, { 51, 46, 117, "Elixir", 0xEE }, { 53, 46, 118, "20000 GP" },
  { 49, 47, 119, "Cure Ring", 0xBD }, { 50, 47, 120, "Back Guard", 0xE1 }, { 55, 42, 121, "Flame Sabre", 0x0D },
  { 56, 49, 257, "Elixir", 0xEE },
}

-- the chest from the side the party can stand on, picked on a live frame (the room's other chests are solid too)
local SIDES = { { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }
local function chest(c)
  return H.lazy(function()
    local best, blen = nil, nil
    for _, s in ipairs(SIDES) do
      local p = H.bfsPath(c[1] + s[1], c[2] + s[2])
      if p and (blen == nil or #p < blen) then best, blen = s, #p end
    end
    H.assertEq(best ~= nil, true, string.format("chest (%d,%d) %s: a side to stand on", c[1], c[2], c[4]))
    return H.openChest({ stand = { c[1] + best[1], c[2] + best[2] }, face = best[3], bit = c[3], what = c[4],
      item = c[5], nav = { fight = FIGHT } })
  end)
end
local function chests()
  local steps = {}
  -- nearest first, from wherever the last one left the party
  local left = {}
  for _, c in ipairs(CHESTS) do left[#left + 1] = c end
  for _ = 1, #CHESTS do
    steps[#steps + 1] = H.lazy(function()
      local bi, bl = nil, nil
      for i, c in ipairs(left) do
        if not H.chestOpen(c[3]) then
          local d = math.abs(c[1] - H.fieldX()) + math.abs(c[2] - H.fieldY())
          if bl == nil or d < bl then bi, bl = i, d end
        end
      end
      if bi == nil then return H.call(function() end) end
      local c = table.remove(left, bi)
      return chest(c)
    end)
  end
  return H.seqStep(steps)
end

local gil0 = nil
H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("banquet-done-v1"),
  K.watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(TWO))
    H.assertEq(sw(0x0278), 1, "the Emperor's weapons reward was granted ($0278; gen_banquet_done's score >= 67)")
    H.assertEq(sw(0x045D), 0, "the treasure room's lock is gone ($045D; _cb2566)")
    H.assertEq(H.worldBfs(164, 194) ~= nil, true, "the Imperial Base's world tile (164,194) on foot from the boot "
      .. "tile, gen_banquet_done's save outside Vector")
  end),
  -- @@setup-end

  -- ---- 1. to the base ------------------------------------------------------------------------------------
  -- @@stage walk
  H.fieldCare({ threshold = 1.0, tag = "outside Vector" }),
  H.worldNavTo(BASE_DOOR[1], BASE_DOOR[2], { maxFrames = 40000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_BASE and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_BASE and settled() end, 2400, "the Imperial Base: map 377", 1),
  H.call(function() say("base", "in the base") end),

  -- ---- 2. the treasure room ------------------------------------------------------------------------------
  -- @@stage room
  H.crossDoor(13, 18, MAP_ROOM, 33, 43, "the base's door 377 (13,18) -> 378 (33,43)", { fight = FIGHT }),
  H.call(function() gil0 = H.gil(); say("base", "the treasure room") end),
  -- the vault behind it is its own pocket of the map: in by 378 (39,40) -> (52,33), out by (51,32) -> (38,39)
  H.crossDoor(39, 40, MAP_ROOM, 52, 33, "the treasure room's inner door 378 (39,40) -> (52,33)", { fight = FIGHT }),
  chests(),
  H.call(function()
    for _, c in ipairs(CHESTS) do
      H.assertEq(H.chestOpen(c[3]), true, string.format("chest bit %d (%s) open", c[3], c[4]))
    end
    H.log(string.format("[base] the room's gil: %d -> %d (+%d, the chests hold 41000)", gil0, H.gil(),
      H.gil() - gil0))
    H.assertEq(H.gil() - gil0, 41000, "the three gil chests paid 41000")
    say("base", "all thirteen chests open")
  end),

  -- ---- 3. out to the world -------------------------------------------------------------------------------
  -- @@stage out
  H.crossDoor(51, 32, MAP_ROOM, 38, 39, "the vault's door 378 (51,32) -> (38,39)", { fight = FIGHT }),
  K.walkInto(33, 44, MAP_BASE, "the treasure room -> the base"),
  H.navTo(5, 17, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return H.worldMode() end }),
  H.waitWorldSettled("out of the base", 2400, 30),
  H.fieldCare({ threshold = 1.0, tag = "outside the base" }),
  H.call(function()
    say("wob", "outside the base")
    H.log("[kit] " .. kitLine(TWO))
  end),
  H.saveState("wob_base_treasure.mss"),
  H.logStep(function()
    return string.format("wob_base_treasure generated: TERRA L%d, LOCKE L%d by the Imperial Base, world (%d,%d), "
      .. "thirteen chests open, gil %d", K.lv(TERRA), K.lv(LOCKE), H.worldX(), H.worldY(), H.gil())
  end),
})

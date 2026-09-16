-- gen_narshe_mission.lua -- the generator that cuts battery checkpoint G,
-- `narshe-mission-v1`.

-- The step: cold-Continue the tracked `terra-returned-v1` battery (boundary
-- F, the v0.6 stop line), assert its contract, board the parked Blackjack,
-- fly to Narshe, walk the mission-meeting scene to `$0076=1`, walk back out
-- to the world map, and save through the game's own Save UI at the Narshe
-- exit spawn, world (84,34), which is boundary G.

-- Checkpoint G is a world battery save, so it needs no authoring (the
-- 2-trigger ROM budget stays untouched).  The save happens at the
-- Narshe exit spawn because that tile is where a cold Continue of the
-- checkpoint puts the party, and the step out of G starts there.

-- The grind's supply line (measured, 2026-09-07).  Two full grinds of this
-- generator -- the one that PASSED (74 battles, ot6-qual) and the v0.17
-- requal attempt that WIPED at its 73rd battle -- both drank the bag's 73
-- Tonics down to the care kernel's 4-Tonic floor by about battle 55 and
-- fought the last ~20 battles unhealed between level-up restores: the
-- pass finished with SABIN at 132/830 and no Tonic or Potion left; the
-- wipe walked into an Iron Fist x2 / Mind Candy x2 formation at
-- 93/93/75/134 HP after a fight the party left at 221/77/76/548 with
-- `tonic=2 potion=0` and a care stop that logged "nothing to do".  A Tonic
-- is +50 against 500-900 HP pools; the party stands ten tiles from JIDOOR
-- (world (27,129), item shop 22: Potion 300, Fenix Down 500, Tent 1200)
-- with ~63k gil and four Tents in the bag.  So the grind now plays the way
-- a person with an item shop next door plays it: it shops at Jidoor before
-- the first leg and again whenever the Tents run out or the Potion/Fenix
-- band is broken (docs/design/level-curve.md's supply curve), and it pitches
-- a Tent on the world map whenever a member is under half HP after a leg's
-- care stop -- a full party restore for 1200 gil, the save-point rest the
-- world map allows (item.asm @84f8: Tent needs $0201 bit7, which the world
-- map sets).  Coordinates and menu flow measured by tools/tests/probe_jidoor.lua:
-- world (27,129) + DOWN -> map 198 (15,61); shop door 198 (27,41) -> map 201
-- (34,20), keeper at (34,15) (npc_prop NPCProp::_201, event _cb4460 = shop
-- 22); back out 201 (34,21) -> 198 (27,43); south edge (15,62)+DOWN -> the
-- world at (27,129).
--
-- The departure stock (#176; brought over by hand from ad7a0104 on
-- wt/potion-route, which bought it at Narshe's item shop 44 after the
-- mission meeting).  Nothing sells Tonics again until Thamasa (Narshe's 44
-- and Albrook's 24 have none), so the Sealed Gate leg's field care comes out
-- of the Potion stack too: POTION to 60 (the band at the L25 that leg
-- reaches, 38, plus an allowance for that field care -- the seeded chain
-- walked the leg with an empty bag, gate_cave_save potion=0, so the next
-- re-cut downstream measures the spend and this target follows) and FENIX
-- DOWN to 23 (~level).  Jidoor's shop 22 sells both, so the grind's last
-- supply stop buys the departure stock instead of a second shop visit in
-- Narshe: one shop routine, two bands -- the grind band while pacing, the
-- departure band once the grind is done.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local SHOP_PROP = H.sym("ShopProp") & 0x3FFFFF   -- shop_prop.dat: 9 bytes per shop, items at +1
local function shopRow(shop, row) return H.readRomByte(SHOP_PROP + shop * 9 + 1 + row) end
local function maxLvl()
  local m = 0
  for c = 0, 15 do
    if partyOf(c) ~= 0 then
      local l = H.readByte(0x1600 + 37 * c + 8)
      if l > m then m = l end
    end
  end
  return m
end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

-- gen_vector_entry's grind-and-replan world walker: no edge is ever
-- condemned, so a battle-restored tile is retried (the gen_opera1
-- finding: worldNavTo reads a battle's snapshot/restore as a dead edge).
local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        plan = nil; H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs/battles absorbed); for trigger tiles and
-- scripted stretches where control flickers
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.driveUntil(function()
    calm = (shipX() == tx and shipY() == ty) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d) $c2=%02X",
          H.frame, shipX(), shipY(), H.readByte(0xc2)))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

-- ---- the grind's supply line (see the header) --------------------------
local TONIC, POTION, FENIX, TENT = 0xE8, 0xE9, 0xF0, 0xF7
-- the band the bag arrives at each fight with: Potions ~level x1.5 for the
-- L18-23 this grind spans (27-35), Fenix ~level (20), Tents for the rest
-- stops (10 -- the two measured grinds would each have used ~4-6)
local GRIND_BAND = { potion = 35, fenix = 20, tent = 10 }
-- what the party leaves the plains with for the Sealed Gate (the header)
local DEPART_BAND = { potion = 60, fenix = 23, tent = 10 }
local SHOP_PROP = H.sym("ShopProp") & 0x3FFFFF   -- shop_prop.dat: 9 bytes per shop, items at +1
local function shopRow(shop, row) return H.readRomByte(SHOP_PROP + shop * 9 + 1 + row) end
local function gil() return H.gil() end
local function bagLine(tag)
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  return string.format("[%s] %s | tonic=%d potion=%d fenix=%d tent=%d gil=%d",
    tag, table.concat(t, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX), H.invCountOf(TENT), gil())
end
-- the lowest living member's HP fraction (a dead member is the fight
-- driver's and the care stop's business, not the Tent's)
local function lowestHp()
  local low = 1
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if hp > 0 and mx > 0 and hp / mx < low then low = hp / mx end
  end
  return low
end
local function needTent() return H.invCountOf(TENT) > 0 and lowestHp() < 0.5 end
local function needRestock()
  return H.invCountOf(TENT) == 0 or H.invCountOf(POTION) < 10
      or H.invCountOf(FENIX) < 8
end

-- Use a Tent from the world menu: X -> main ($05, Item is row 0) -> item
-- list ($08, DP $4B is the bag slot) -> A picks the slot up ($19) -> A on
-- the same slot uses it; the item menu answers a Tent with return code $02
-- and terminates after its fade (item.asm @84f8), and the world module
-- runs the tent event (world_start.asm @02db: VehicleEvent_01), which
-- restores the party.  Measured by probe_jidoor.lua: 886 frames, every
-- member at max HP and MP, one Tent gone.
local function useTent(tag)
  local ph, calm, before, tentAt = 0, 0, nil, nil
  return H.seqStep({
    H.logStep(function() return bagLine(tag .. ": before") end),
    H.driveUntil(function()
      if before == nil then return false end
      local used = H.invCountOf(TENT) < before
      local back = H.worldMode() and H.readByte(0x59) == 0 and H.worldHasControl()
        and H.worldAligned() and bright() >= 15
      calm = (used and back) and calm + 1 or 0
      return calm >= 20
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 8
        if before == nil then before = H.invCountOf(TENT) end
        if H.invCountOf(TENT) < before then
          if tentAt == nil then
            tentAt = H.frame
            H.log(string.format("[%s] Tent consumed at f%d", tag, H.frame))
          end
          H.setPad({}); return
        end
        if H.readByte(0x59) == 0 then H.setPad(ph < 4 and { "x" } or {}); return end
        local st, cur = H.readByte(0x26), H.readByte(0x4b)
        if st == 0x05 then
          H.setPad(cur == 0 and (ph < 4 and { "a" } or {}) or { up = true }); return
        end
        local slot = H.invSlotOf(TENT)
        if st == 0x08 then
          if slot == nil then H.setPad({}); return end
          if cur == slot then H.setPad(ph < 4 and { "a" } or {})
          else H.setPad({ [cur < slot and "down" or "up"] = true }) end
          return
        end
        if st == 0x19 then
          H.setPad((slot and cur == slot) and (ph < 4 and { "a" } or {})
            or (ph < 4 and { "b" } or {}))
          return
        end
        H.setPad({})
      end),
    }, tag),
    H.call(function()
      for _, c in ipairs(H.partyMembers()) do
        H.assertEq(H.charHp(c), H.charMaxHp(c),
          string.format("%s: char %d at full HP after the Tent", tag, c))
      end
      H.log(bagLine(tag .. ": after"))
    end),
  })
end

-- The Jidoor supply stop, from anywhere on the plains and back to the world
-- at (27,129); the caller's next leg walks on from there.  Route coordinates
-- are the header's measured ones.  The walk to town is a worldNavTo leg
-- like the grind's own (its fights are fought, not fled).
local function fieldSettled(m)
  return function()
    return map() == m and H.hasControl() and H.tileAligned() and bright() >= 15
  end
end
local function jidoorRestock(tag, band)
  local what = "restock (" .. tag .. ")"
  return {
    H.logStep(function() return bagLine(what .. ": leaving the plains for Jidoor") end),
    H.worldNavTo(27, 129, { maxFrames = 45000, playBattles = "tactical",
      careThreshold = 0.7, healPercent = 45,
      summon = { [1] = { mp = 36 }, [4] = { mp = 50 }, [5] = { mp = 27 } } }),
    pressWalk("down", function() return not H.worldMode() and map() == 198 end,
      1200, what .. ": held DOWN into Jidoor (map 198)"),
    H.waitUntil(fieldSettled(198), 1800, what .. ": Jidoor control", 5),
    H.waitFrames(30),
    H.navTo(27, 42, { playBattles = "tactical", maxFrames = 12000,
      arrive = function() return map() == 201 end }),
    pressWalk("up", function() return map() == 201 end, 1200,
      what .. ": held UP into the item shop door 198 (27,41) -> map 201"),
    H.waitUntil(fieldSettled(201), 1800, what .. ": item shop control", 5),
    H.waitFrames(60),
    H.shopTalk(34, 15, "Jidoor item shop"),
    H.call(function()
      -- event command $9b parks the shop number at $0201; the rows come
      -- from the ROM table (the menu fills its row list only once drawn)
      H.assertEq(H.readByte(0x0201), 22, "the counter opened shop 22 ($0201)")
      H.assertEq(shopRow(22, 0), POTION, "shop 22 row 0 is Potion")
      H.assertEq(shopRow(22, 5), FENIX, "shop 22 row 5 is Fenix Down")
      H.assertEq(shopRow(22, 7), TENT, "shop 22 row 7 is Tent")
    end),
    -- essentials first, the Tent soak last, so a short purse shorts Tents
    H.buyItem(POTION, 0, function() return band.potion - H.invCountOf(POTION) end,
      "POTION to " .. band.potion),
    H.buyItem(FENIX, 5, function() return band.fenix - H.invCountOf(FENIX) end,
      "FENIX DOWN to " .. band.fenix),
    H.buyItem(TENT, 7, function() return band.tent - H.invCountOf(TENT) end,
      "TENT to " .. band.tent),
    H.shopClose("Jidoor item shop"),
    H.logStep(function() return bagLine(what .. ": bought") end),
    H.navTo(34, 20, { playBattles = "tactical", maxFrames = 6000,
      arrive = function() return map() == 198 end }),
    pressWalk("down", function() return map() == 198 end, 1200,
      what .. ": held DOWN out of the shop 201 (34,21) -> map 198"),
    H.waitUntil(fieldSettled(198), 1800, what .. ": Jidoor control again", 5),
    H.waitFrames(30),
    H.navTo(15, 62, { playBattles = "tactical", maxFrames = 20000,
      arrive = function() return H.worldMode() end }),
    pressWalk("down", function() return H.worldMode() end, 1200,
      what .. ": held DOWN off Jidoor's south edge -> the world"),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
         and bright() >= 15 and (H.worldX() ~= 0 or H.worldY() ~= 0)
    end, 2400, what .. ": world control", 5),
    H.waitFrames(30),
    H.logStep(function()
      return string.format("%s world (%d,%d) f%d", bagLine(what .. ": back on the"),
        H.worldX(), H.worldY(), H.frame)
    end),
  }
end

H.run({ maxFrames = 600000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the terra-returned world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900,
    "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    local t = {}
    for c = 0, 13 do t[#t + 1] = string.format("%02X", H.readByte(0x1850 + c)) end
    H.log("[roster] $1850+0..13 = " .. table.concat(t, " ")
      .. string.format("  $1EDE=%02X $1EDF=%02X", H.readByte(0x1EDE),
        H.readByte(0x1EDF)))
    H.assertEntryContract("terra-returned-v1")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "$11FA -- restored ON FOOT")
    H.assertEq(H.readByte(0x11F3), 0, "$11F3 -- not forced aboard")
    H.assertEq(H.worldX(), 24, "boot world x")
    H.assertEq(H.worldY(), 121, "boot world y")
    H.assertEq(shipX(), 24, "the Blackjack is parked under the party (x)")
    H.assertEq(shipY(), 121, "the Blackjack is parked under the party (y)")
  end),

  -- ---- the sanctioned grind, on the Vector plains ------------------------
  -- Six measured Sealed-Gate cave wipes with the complete kit say that
  -- area is a leveling gate at L18, and BOTH its approach pockets are
  -- door-to-door shelves with no pacing ground (censused) -- you arrive
  -- leveled or you don't.  The last open ground before it is right here:
  -- the plains under the parked Blackjack.  The engine censuses its own
  -- pacing pair; level-ups full-restore (the OT6 rule) so the loop
  -- part-sustains; capped legs; goal 21 (level-curve.md's
  -- reasonable-grind rule, which also narrows the documented FC gap).
  (function()
    local ax, ay, bx, by
    local steps = {
      H.call(function()
        local reach = {}
        for y = 112, 130, 2 do
          for x = 14, 40, 2 do
            if not (x == 24 and y == 121) then
              local p = H.worldBfs(x, y)
              if p then reach[#reach + 1] = { x, y, #p } end
            end
          end
        end
        H.assertEq(#reach >= 2, true, "the plains census found pacing ground")
        table.sort(reach, function(u, v) return u[3] > v[3] end)
        ax, ay = reach[1][1], reach[1][2]
        bx, by = reach[#reach][1], reach[#reach][2]
        H.log(string.format("[grind] pacing (%d,%d) <-> (%d,%d) "
          .. "(census: %d reachable; best level %d)", ax, ay, bx, by,
          #reach, maxLvl()))
      end),
    }
    local legOpts = {
      maxFrames = 45000, playBattles = "tactical",
      careThreshold = 0.7, healPercent = 45,
      -- probe_locke_bolt: this party has NO learned spells (magic
      -- opts would silently degrade to Fight), but three stones are
      -- worn -- Locke Carbunkl, Edgar Bismark, Sabin Shiva -- so the
      -- once-per-fight genju is the party's whole magic game.
      summon = { [1] = { mp = 36 }, [4] = { mp = 50 },
                 [5] = { mp = 27 } } }
    for leg = 1, 80 do
      steps[#steps + 1] = H.cond(function() return maxLvl() < 23 end, {
        -- rest first (a member under half HP after the last leg's care),
        -- then shop if the bag is under its band, then walk the leg
        H.cond(needTent, { useTent(string.format("leg %d: tent", leg)) }, {}),
        H.cond(needRestock, jidoorRestock(string.format("leg %d", leg), GRIND_BAND), {}),
        H.worldNavTo(function() return leg % 2 == 1 and ax or bx end,
                     function() return leg % 2 == 1 and ay or by end, legOpts),
      }, {})
    end
    return H.cond(function() return true end, steps)
  end)(),
  H.call(function()
    H.log(string.format("[grind] done: best level %d", maxLvl()))
    H.log(bagLine("grind done"))
    H.assertEq(maxLvl() >= 22, true, "the plains grind reached at least L22")
  end),
  -- the departure stock, bought at the same counter (the header)
  H.cond(function()
    return H.invCountOf(POTION) < DEPART_BAND.potion
        or H.invCountOf(FENIX) < DEPART_BAND.fenix
  end, jidoorRestock("departure", DEPART_BAND), {}),
  -- back to the ship on foot, fighting what the walk meets like the legs do
  H.worldNavTo(24, 121, { maxFrames = 45000, playBattles = "tactical",
    careThreshold = 0.7, healPercent = 45,
    summon = { [1] = { mp = 36 }, [4] = { mp = 50 }, [5] = { mp = 27 } } }),
  H.cond(needTent, { useTent("after the grind: tent") }, {}),
  worldGrind(24, 121, "back onto the parked ship (24,121)"),
  H.call(function()
    H.log(bagLine("leaving the plains"))
    H.assertEq(H.invCountOf(POTION) >= DEPART_BAND.potion - 10, true,
      "the party leaves the plains near the departure Potion stock")
    H.assertEq(H.invCountOf(FENIX) >= 20, true, "Fenix Downs at ~level")
  end),

  -- ---- board + lift off (one A tap does both) ---------------------------
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function()
    return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
  end, 900, "liftoff (the flight view zeroes $E0/$E2)", 5),
  H.waitFrames(240),
  H.call(function()
    H.log(string.format("[airborne] ship=(%d,%d)", shipX(), shipY()))
    H.screenshot("step_fg_airborne")
  end),

  -- ---- fly to Narshe and land beside the gate ---------------------------
  flyTo(84, 36),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(shipX(), 84, "hovering over the Narshe landing tile (x)")
    H.assertEq(shipY(), 36, "hovering over the Narshe landing tile (y)")
    H.assertEq(H.readByte(0xc2) & 0x02, 0,
      "$c2 bit1 CLEAR -- (84,36) is airship-landable (LandAirship, "
      .. "ff6/src/world/init.asm)")
  end),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "the ship grounds (world position cells rewritten)", 10),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.worldX(), 84, "grounded x")
    H.assertEq(H.worldY(), 36, "grounded y")
    H.screenshot("step_fg_grounded")
  end),

  -- ---- disembark and walk into Narshe -----------------------------------
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 84 and H.worldY() == 35 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ up = true }) end),
    }, "step off the grounded ship UP to (84,35)")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(0x11FA) & 3, 0, "on foot beside the ship")
  end),
  worldGrind(84, 34, "world walk -> the Narshe entry point (84,34)"),
  pressWalk("up", function() return not H.worldMode() and map() == 20 end,
    1200, "held UP onto (84,33) -> NARSHE (map 20)"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "Narshe control", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 20, "Narshe exterior is map 20")
    H.assertEq(H.fieldX(), 38, "Narshe arrival x (short entrance 0 (84,33))")
    H.assertEq(H.fieldY(), 61, "Narshe arrival y")
    H.assertEq(sw(0x0076), 0, "$0076 CLEAR -- the mission meeting is ahead")
  end),

  H.fieldCare({ tag = "care on arrival in Narshe", threshold = 0.55 }),

  -- ---- the escort trigger row and the mission meeting --------------------
  -- The trigger row is (37-39,51) (event_trigger.asm:114-116); park two
  -- tiles below it and enter with a held press, then ride the scene.
  H.navTo(38, 53, { playBattles = "tactical", maxFrames = 12000 }),
  pressWalk("up", function() return map() == 30 or not H.hasControl() end,
    2400, "held UP onto the escort trigger row (38,51)"),
  H.advanceStory(function() return map() == 30 and sw(0x0076) == 1 end, 60000, { playBattles = true }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting()
  end, 6000, "control after the mission meeting", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 30, "the meeting is on map 30 (upper Narshe)")
    H.assertEq(sw(0x0076), 1,
      "$0076 SET -- the mission handoff (event_main.asm:94170)")
    H.assertEq(sw(0x064E), 1, "$064E SET -- the meeting scene latch")
    H.assertEq(sw(0x045E), 0,
      "$045E CLEAR -- the Imperial-Base soldier NPCs were withdrawn "
      .. "(:94171-94180)")
    H.log(string.format("[meeting] done at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("step_fg_meeting")
  end),

  -- ---- out of Narshe to the world map ------------------------------------
  H.navTo(110, 25, { playBattles = "tactical", maxFrames = 12000,
    arrive = function() return map() == 20 end }),
  pressWalk("down", function() return map() == 20 end, 1200,
    "door 30 (110,26) -> map 20 (18,24)"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "map 20 control", 5),
  H.waitFrames(30),

  -- ---- Narshe's item shop on the way out (#176) ---------------------------
  -- The plains grind above spent the bag's Tonics (terra-returned-v1 carries
  -- 73, the seeded narshe_mission fixture 0) and the party arrives here with
  -- no Potions at L23 (band ~level x1.5 = 35, docs/design/level-curve.md).
  -- Narshe's item shop is the last shop before the Sealed Gate: the door
  -- (41,22) -> map 26 (44,13), shopkeeper (44,8); with $006B set (the
  -- factory escape) _ccd28c opens shop 44 -- rows POTION 0 / FENIX DOWN 2,
  -- and NO Tonic.  Nothing sells Tonics again until Thamasa (Albrook's 24
  -- has none either), so on this leg the care kernel's field heals come out
  -- of the Potion stack too.  POTION to 60: the band at the L25 the leg
  -- reaches (38) plus an allowance for that field care; the leg's own spend
  -- could not be measured -- the seeded chain walked it with an empty bag
  -- (gate_cave_save potion=0, vector_crash 3) -- so the next re-cut of the
  -- checkpoints downstream measures it and this target follows.  FENIX
  -- DOWN to 23 (~level).  Gil is deep (~173k).
  H.call(function()
    H.vars.shopStart = H.frame
    H.assertEq(sw(0x006B), 1, "$006B set -- the item shop opens as shop 44")
    H.assertEq(sw(0x00A4), 0, "$00A4 clear -- not shop 71")
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
    H.assertEq(H.readByte(0x0201), 44, "the counter opened shop 44 ($0201)")
    H.assertEq(shopRow(44, 0), POTION, "shop 44 row 0 is Potion")
    H.assertEq(shopRow(44, 2), FENIX_DOWN, "shop 44 row 2 is Fenix Down")
  end),
  H.buyItem(POTION, 0, function() return 60 - H.invCountOf(POTION) end, "POTION to 60"),
  H.buyItem(FENIX_DOWN, 2, function() return 23 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 23"),
  H.call(function()
    H.log(string.format("[shop] Narshe item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), H.gil(), H.frame))
  end),
  H.shopClose("Narshe item shop"),
  H.call(function()
    H.assertEq(H.invCountOf(POTION) >= 60, true,
      "the party leaves Narshe with 60 Potions -- the Sealed Gate leg's in-combat AND field heal")
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 23, true, "Fenix Downs at 23 (~level)")
    H.log(string.format("[shop] leaving the shop: gil=%d tonics=%d potions=%d fenix=%d",
      H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.crossDoor(44, 14, 20, 41, 24, "item shop door 26(44,14)->20(41,24), return"),
  H.call(function()
    H.log(string.format("[shop] Narshe stop cost %d frames (f%d -> f%d)",
      H.frame - H.vars.shopStart, H.vars.shopStart, H.frame))
  end),

  H.navTo(18, 61, { playBattles = "tactical", maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "the map-20 south-edge long entrance -> the world map"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 84 and H.worldY() == 34
  end, 2400, "back on the world at (84,34), the checkpoint-G tile", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.worldX(), 84, "checkpoint-G tile x")
    H.assertEq(H.worldY(), 34, "checkpoint-G tile y")
    H.log(string.format("[G tile] $1f64=%04X $1f66=%02X%02X ship=(%d,%d)",
      H.readWord(0x1f64), H.readByte(0x1f67), H.readByte(0x1f66),
      shipX(), shipY()))
    -- everything the boundary declares except the sram witnesses, which
    -- only the save itself can put into the battery
    H.assertExitContractPreSave("narshe-mission-v1")
    H.assertPartyStanding("narshe_mission exit")
    H.screenshot("step_fg_g_tile")
  end),
  H.saveState("narshe_mission.mss"),

  -- ---- the real Save UI, slot 3 ------------------------------------------
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) ~= 0) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open on foot at the checkpoint-G tile")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the narshe-mission checkpoint to slot 3")
    H.assertExitContract("narshe-mission-v1")
    H.screenshot("step_fg_saved")
  end),

  H.logStep(function()
    return string.format("narshe-mission-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; boundary G of the v0.7 range",
      H.frame, H.worldX(), H.worldY())
  end),
})

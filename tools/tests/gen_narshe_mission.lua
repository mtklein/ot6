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
-- a Tent on the world map when the leg gate says the party is worn (needTent
-- below: every summoner dry, or a member the care stop could not top up) --
-- a full party restore for 1200 gil, the save-point rest the world map
-- allows (item.asm @84f8: Tent needs $0201 bit7, which the world map sets).
-- Every purchase stop ends with the combat items arranged back on top of
-- the bag (#197).  Coordinates and menu flow measured by tools/tests/probe_jidoor.lua:
-- world (27,129) + DOWN -> map 198 (15,61); shop door 198 (27,41) -> map 201
-- (34,20), keeper at (34,15) (npc_prop NPCProp::_201, event _cb4460 = shop
-- 22); back out 201 (34,21) -> 198 (27,43); south edge (15,62)+DOWN -> the
-- world at (27,129).
--
-- The departure stock (#176; brought over by hand from ad7a0104 on
-- wt/potion-route, which bought it at Narshe's item shop 44 after the
-- mission meeting).  Nothing on foot from here sells Tonics (Narshe's 44,
-- Jidoor's 22 and Albrook's 24 have none), so the Tonics come by airship
-- from Nikeah (#210: TONIC to 99 before the grind and again on the way to
-- Narshe; see nikeahTonics below), and the Potion stack covers what the
-- Sealed Gate leg's field care spends past them: POTION to 60 (the band at the L25 that leg
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
  local W = H.newWalkFighter(what or string.format("worldGrind (%d,%d)", tx, ty))
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if W.frame() then plan = nil; return end
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

-- unconditional held walk (dialogs absorbed, battles fought -- #183); for
-- trigger tiles and scripted stretches where control flickers
-- maxFrames counts walking frames only: a battle the walk meets (and its
-- care) is uncounted, with a 20000-frame backstop over everything (#211's
-- Tent shape).  The #210 regeneration met a random on the step into Narshe
-- at shift 0 and shift 20 alike, and the fight alone ran the old 1200-frame
-- budget out (attempts 1 and 2: "timeout after 1200 frames driving toward
-- held UP onto (84,33) -> NARSHE").
local function pressWalk(dir, pred, maxFrames, what)
  local ph, walked = 0, 0
  local W = H.newWalkFighter("pressWalk: " .. what)
  return H.withReset(H.driveUntil(pred, maxFrames + 20000, {
    H.call(function()
      ph = (ph + 1) % 8
      if W.frame() then return end
      walked = walked + 1
      if walked > maxFrames then
        error(string.format("timeout after %d walking frames driving toward %s",
          maxFrames, what), 0)
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what), function() ph, walked = 0, 0 end)
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
local ANTIDOTE, REMEDY = 0xF2, 0xF5
local TINCTURE, REVIVIFY = 0xEB, 0xF1
-- the Tonic band (docs/design/level-curve.md: ~level x5, cap 99): L21 on
-- boot, L23 on departure, so the cap either way
local TONIC_BAND = 99
-- the stock under which the Nikeah flight is worth taking: the band is a
-- "~", and a trip of 5520 frames is not made for a handful of Tonics
local TONIC_TRIP = TONIC_BAND * 3 // 4
-- the band the bag arrives at each fight with: Potions ~level x1.5 for the
-- L18-23 this grind spans (27-35), Fenix ~level (20), Tents for the rest
-- stops (10 -- the two measured grinds would each have used ~4-6)
-- Tinctures at the MP band (~level / 4 at the L22-23 the grind ends at,
-- #231, docs/design/supply.md) and three Revivifies, the Zombie cure the
-- route otherwise never buys; both at every restock, after the revives
-- and before the Tents.
local GRIND_BAND = { potion = 35, fenix = 20, tincture = 6, revivify = 3, tent = 10 }
-- what the party leaves the plains with for the Sealed Gate (the header)
local DEPART_BAND = { potion = 60, fenix = 23, tincture = 6, revivify = 3, tent = 10 }
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
-- the care threshold the legs heal to (worldNavTo's careThreshold below)
local CARE = 0.7
-- probe_locke_bolt: this party has NO learned spells (magic opts would
-- silently degrade to Fight), but three stones are worn -- Locke Carbunkl,
-- Edgar Bismark, Sabin Shiva -- so the once-per-fight genju is the party's
-- whole magic game.  Keyed by character; the leg options hand the same
-- table to the fight driver.
local SUMMON = { [1] = { mp = 36 }, [4] = { mp = 50 }, [5] = { mp = 27 } }
-- the living stone-wearers, and how many of them can still pay their genju
local function summoners()
  local n, can = 0, 0
  for _, c in ipairs(H.partyMembers()) do
    local s = SUMMON[c]
    if s and H.charHp(c) > 0 then
      n = n + 1
      if H.charMp(c) >= s.mp then can = can + 1 end
    end
  end
  return n, can
end
-- When a person pitches one of the Tents in the bag (#199; measured on the
-- v0.17 grind, build/attempts/narshe-mission-shops/v017_gates.txt: 73 leg
-- gates).  Not on HP alone: the care stop after every battle heals to CARE
-- with Tonics, so no gate saw a member under 0.7, let alone the old 0.5
-- gate (0 of 73), and ten Tents rode the whole grind unused.  On MP: care
-- does not restore it, a level-up restores one member at a time, and the
-- genju is this party's whole magic game -- at 23 of the 73 gates no
-- summoner could pay for one (c1 16/128 vs 36, c4 34/138 vs 50, c5 7/135
-- vs 27 at the first such gate) and at 72 at least one could not.  So a
-- leg gate rests when the magic game is gone (every summoner dry) or when
-- the care stop left someone under its threshold (the bag at the Tonic
-- floor); the departure gate, before the Sealed Gate leg, rests when any
-- summoner is dry (the v0.17 party boarded at c1 3/183 and c4 4/182 MP
-- with tent=10).
local function needTent(anyDry)
  if H.invCountOf(TENT) == 0 then return false end
  if lowestHp() < CARE then return true end
  local n, can = summoners()
  return n > 0 and ((anyDry and can < n) or can == 0)
end
local function gateLine(tag, anyDry)
  local n, can = summoners()
  return bagLine(string.format("%s: lowest hp %.2f, %d/%d summoners can pay -> %s",
    tag, lowestHp(), can, n, needTent(anyDry) and "tent" or "walk"))
end
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
--
-- A battle that opens under the Tent (an encounter rolled on the step the
-- walk ended on, #211) is fought by the walkers' fighter (H.newWalkFighter,
-- #183) and its care stop, and the Tent then resumes from wherever the menu
-- stands; the old X/menu presses had no battle check and sat at the battle's
-- command menu until the 4000-frame budget ran out.  That budget pays for
-- the menu work only: battle and care frames are uncounted, with a 60000-
-- frame backstop over everything so a hung battle still ends the step.
local TENT_MENU_FRAMES = 4000
local function useTent(tag)
  local ph, calm, before, tentAt, menuN = 0, 0, nil, nil, 0
  local W = H.newWalkFighter(tag)
  return H.seqStep({
    H.logStep(function() return bagLine(tag .. ": before") end),
    H.withReset(H.driveUntil(function()
      if before == nil then return false end
      local used = H.invCountOf(TENT) < before
      local back = H.worldMode() and H.readByte(0x59) == 0 and H.worldHasControl()
        and H.worldAligned() and bright() >= 15
      calm = (used and back) and calm + 1 or 0
      return calm >= 20
    end, TENT_MENU_FRAMES + 60000, {
      H.call(function()
        ph = (ph + 1) % 8
        if before == nil then before = H.invCountOf(TENT) end
        if W.frame() then calm = 0; return end
        menuN = menuN + 1
        if menuN > TENT_MENU_FRAMES then
          error(string.format("timeout after %d frames driving toward %s "
            .. "(%d battle(s) fought under it, their frames uncounted)",
            TENT_MENU_FRAMES, tag, W.fought()) .. H.timeoutContext(), 0)
        end
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
    }, tag), function()
      ph, calm, before, tentAt, menuN = 0, 0, nil, nil, 0
      W = H.newWalkFighter(tag)
    end),
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
      careThreshold = CARE, healPercent = 45, summon = SUMMON }),
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
      H.assertEq(shopRow(22, 1), TINCTURE, "shop 22 row 1 is Tincture")
      H.assertEq(shopRow(22, 4), REVIVIFY, "shop 22 row 4 is Revivify")
    end),
    -- essentials first, the Tent soak last, so a short purse shorts Tents
    H.buyItem(POTION, 0, function() return band.potion - H.invCountOf(POTION) end,
      "POTION to " .. band.potion),
    H.buyItem(FENIX, 5, function() return band.fenix - H.invCountOf(FENIX) end,
      "FENIX DOWN to " .. band.fenix),
    H.buyItem(REVIVIFY, 4, function() return band.revivify - H.invCountOf(REVIVIFY) end,
      "REVIVIFY to " .. band.revivify),
    H.buyItem(TINCTURE, 1, function() return band.tincture - H.invCountOf(TINCTURE) end,
      "TINCTURE to " .. band.tincture),
    H.buyItem(TENT, 7, function() return band.tent - H.invCountOf(TENT) end,
      "TENT to " .. band.tent),
    H.shopClose("Jidoor item shop"),
    H.logStep(function() return bagLine(what .. ": bought") end),
    -- #197: the combat items back on top of the bag (without this the
    -- Potion rode at row 43 into the gate cave and the fight driver walked
    -- 43 rows to it every heal)
    H.bagArrange({ POTION, FENIX, TONIC, ANTIDOTE, REMEDY },
      { tag = "bag: combat items on top (" .. tag .. ")" }),
    H.call(function()
      H.assertEq(H.readByte(0x1869), POTION, what .. ": slot 0 is Potion")
      H.assertEq(H.readByte(0x186A), FENIX, what .. ": slot 1 is Fenix Down")
    end),
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

-- ---- the Tonic stop, by airship (#210) ----------------------------------
-- Field care runs on Tonics (level-curve.md's supply curve: ~level x5, cap
-- 99), and nothing on foot from here sells them: Jidoor's shop 22 and
-- Narshe's 44 (the swap $006B made) stock none.  The #198 re-cut booted
-- this step with tonic=4 (terra-returned-v1) and left the plains with 4 --
-- the care kernel's floor, i.e. no Tonics at all -- for the Sealed Gate.  A
-- person holding an airship and 115k gil flies to a town that sells them.
-- Measured by tools/tests/probe_tonic_airship.lua off this same checkpoint:
--   * South Figaro (shop 8) is still occupied: landable beside the gate at
--     (84,112), but its troopers wall the street to the shop (navTo read
--     no path 20 times).
--   * Nikeah (shop 15: Tonic row 0) is clean: the Blackjack lands on
--     (116,61) ($c2=44), world (117,61) -> town 169 (1,35), the counter
--     keeper at (24,39) talked from (23,39), and the x=0 column walks back
--     out onto the ship tile (116,61).  Plains -> Nikeah -> plains cost 5520
--     frames and 4750 gil for 95 Tonics (f1396 -> f6916).
-- Mobliz (220,115) and Thamasa are farther; Figaro Castle's merchants
-- refuse EDGAR and SABIN (_ca67de/_ca67e2), who are both in this party.
local function liftOff(what)
  return {
    H.pressButtons({ "a" }, 8),
    H.waitUntil(function()
      return H.worldMode() and H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
    end, 900, what .. ": liftoff (the flight view zeroes $E0/$E2)", 5),
    H.waitFrames(240),
    H.logStep(function()
      return string.format("[airborne] %s: ship=(%d,%d) f%d", what, shipX(), shipY(), H.frame)
    end),
  }
end
local function landAt(x, y, what)
  return {
    flyTo(x, y),
    H.release(),
    H.waitFrames(60),
    H.call(function()
      H.assertEq(H.readByte(0xc2) & 0x02, 0, string.format(
        "%s: $c2 bit1 CLEAR -- (%d,%d) is airship-landable", what, x, y))
    end),
    H.pressButtons({ "b" }, 8),
    H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
      1200, what .. ": the ship grounds (world position cells rewritten)", 10),
    H.waitFrames(120),
    H.call(function()
      H.assertEq(H.worldX(), x, what .. ": grounded x")
      H.assertEq(H.worldY(), y, what .. ": grounded y")
      H.assertEq(H.readByte(0x11FA) & 3, 0, what .. ": on foot on the ship tile")
    end),
  }
end
-- From the grounded ship, anywhere: fly to Nikeah, buy TONIC to the band,
-- and stand on foot on the grounded ship at (116,61) again.
local function nikeahTonics(tag)
  local what = "Tonic stop (" .. tag .. ")"
  local start = 0
  local steps = {}
  local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end
  add({ H.call(function()
    start = H.frame
    H.log(string.format("[shop] Nikeah stop begins f%d: gil=%d tonic=%d potion=%d fenix=%d",
      H.frame, H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX)))
  end) })
  add(liftOff(what))
  add(landAt(116, 61, what .. ": Nikeah"))
  add({
    worldGrind(117, 61, what .. ": world (117,61) -> Nikeah"),
    H.waitUntil(fieldSettled(169), 2400, what .. ": Nikeah control (map 169)", 5),
    -- the town's walkers cross the one street to the counter
    -- (gen_sabin_trench): wait, as a person would, for it to clear
    H.waitFrames(150),
    H.waitUntil(function() return H.bfsPath(24, 41) ~= nil end, 1800,
      what .. ": a walkable street to the Nikeah counter", 1),
    H.shopTalk(24, 39, "Nikeah item shop"),
    H.call(function()
      H.assertEq(H.shopId(), 15, "the counter opened shop 15 ($0201)")
      H.assertEq(H.shopRowOf(15, TONIC) ~= nil, true, "shop 15 sells Tonics")
    end),
    H.buyItem(TONIC, function() return TONIC_BAND - H.invCountOf(TONIC) end,
      "TONIC to " .. TONIC_BAND),
    H.shopClose("Nikeah item shop"),
    H.bagArrange({ POTION, FENIX, TONIC, ANTIDOTE, REMEDY },
      { tag = "bag: combat items on top (Nikeah item shop)" }),
    H.call(function()
      H.assertEq(H.readByte(0x1869), POTION, what .. ": slot 0 is Potion")
      H.assertEq(H.invCountOf(TONIC) >= TONIC_BAND, true,
        what .. ": Tonics at the band")
      H.log(string.format("[shop] Nikeah item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
        H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.gil(), H.frame))
    end),
    H.navTo(1, 35, { playBattles = "tactical", maxFrames = 20000,
      arrive = function() return H.worldMode() end }),
    pressWalk("left", function() return H.worldMode() end, 1200,
      what .. ": Nikeah's x=0 column -> the world (116,61)"),
    -- the world flags read true a few frames early on the way out; the
    -- position cells are what settle last (probe_tonic_airship)
    H.waitFrames(60),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
        and bright() >= 15 and H.worldX() == 116 and H.worldY() == 61
    end, 2400, what .. ": back on the ship tile (116,61)", 5),
    H.waitFrames(30),
    H.logStep(function()
      return string.format("[shop] Nikeah stop done: %d frames (f%d -> f%d)",
        H.frame - start, start, H.frame)
    end),
  })
  return steps
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

  -- ---- the Tonic stop before the grind (#210) ----------------------------
  -- ~75 fights of field care ahead and the bag at the kernel's floor: fly to
  -- Nikeah, then back to the plains under the ship's old tile
  H.cond(function() return H.invCountOf(TONIC) < TONIC_TRIP end, (function()
    local steps = nikeahTonics("before the grind")
    for _, s in ipairs(liftOff("Nikeah -> the plains")) do steps[#steps + 1] = s end
    for _, s in ipairs(landAt(24, 121, "back on the plains")) do steps[#steps + 1] = s end
    steps[#steps + 1] = H.logStep(function() return bagLine("before the grind") end)
    return steps
  end)(), {}),

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
      careThreshold = CARE, healPercent = 45, summon = SUMMON }
    for leg = 1, 80 do
      steps[#steps + 1] = H.cond(function() return maxLvl() < 23 end, {
        -- rest first (the gate above needTent), then shop if the bag is
        -- under its band, then walk the leg
        H.logStep(function() return gateLine(string.format("leg %d gate", leg)) end),
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
    careThreshold = CARE, healPercent = 45, summon = SUMMON }),
  -- the departure rest: any summoner dry before the Sealed Gate leg
  H.logStep(function() return gateLine("departure gate", true) end),
  H.cond(function() return needTent(true) end,
    { useTent("after the grind: tent") }, {}),
  worldGrind(24, 121, "back onto the parked ship (24,121)"),
  H.call(function()
    H.log(bagLine("leaving the plains"))
    H.assertEq(H.invCountOf(POTION) >= DEPART_BAND.potion - 10, true,
      "the party leaves the plains near the departure Potion stock")
    H.assertEq(H.invCountOf(FENIX) >= 20, true, "Fenix Downs at ~level")
  end),

  -- ---- the Tonic top-up on the way to Narshe (#210) ----------------------
  -- the grind drinks the pre-grind stop's Tonics; the Sealed Gate leg
  -- leaves from here, so the bag goes back to the band first
  H.cond(function() return H.invCountOf(TONIC) < TONIC_TRIP end,
    nikeahTonics("departure"), {}),

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

-- gen_fc_alcove.lua -- the Floating Continent descent: checkpoint R.
--
-- Cold-Continues the tracked `fc-landing-v1` battery (boundary Q: the
-- landing SavePoint 394 (7,12), TERRA LOCKE EDGAR fresh off the IAF
-- gauntlet -- gen_fc_landing.lua), dresses EDGAR from the bag, descends the
-- continent, collects SHADOW, and saves at the alcove SavePoint 358 (8,10)
-- -- the `fc-alcove-v1` checkpoint.  Reads and pad presses only; the
-- descent is fought for real.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

H.contracts["fc-landing-v1"] = {
  slot = 3,
  field = { map = 394, x = 7, y = 12 },   -- the landing SavePoint (the _394 trigger block)
  switches = {},
  party = {
    size = 3,                             -- TERRA LOCKE EDGAR: the IAF three
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x04, "EDGAR" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  items = {},
  sram = {},
}
H.contracts["fc-alcove-v1"] = {
  slot = 3,
  field = { map = 358, x = 8, y = 10 },   -- the alcove's SavePoint tile
  switches = {},
  party = {
    size = 4,                             -- TERRA LOCKE EDGAR SHADOW
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x03, "SHADOW" },
      { 0x04, "EDGAR" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  items = {},
  sram = {},
}

local ZMENUSTATE = 0x26
local POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY = 0xE9, 0xF0, 0xE8, 0xF2, 0xF5   -- item ids (the care kernel's)
local TERRA, LOCKE, SHADOW, EDGAR, STRAGO = 0x00, 0x01, 0x03, 0x04, 0x07
local RAMUH, SHIVA = 0x00, 0x02
local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function charPos(c) return function() return (H.readByte(0x1850 + c) >> 3) & 0x03 end end
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end


-- ---- the IAF / FC fight driver -----------------------------------------
-- The IAF trash (Sky Armor $043 pierce-class, Spit Fire $0E3 slash-class,
-- both bolt|WIND-weak with 2 authored pips; floating-continent-route.md
-- s3) is a DPS race the first cut lost with a poison tool and one Bolt
-- caster.  The keys P's roster holds: Bolt from TERRA (RAMUH) and LOCKE
-- (MADUIN) as party attack magic, LOCKE's dual blades (ThunderBlade
-- slash + Guardian pierce: one hand chips each machine), and EDGAR's
-- AutoCrossbow -- the driver's DEFAULT tool, four pierce hits that sweep
-- the Sky Armors and, later, the AirForce's pierce-class parts.  Bolt is
-- every FC boss's row too (Ultros IV, AirForce, Atma, Nerapa).
-- The descent pool (decoded at the RIGHT offsets, monster_prop +25 weak /
-- +23 absorb, per tools/check_boss_rows.py): Dragon ($083, 7000 HP) weak
-- BOLT; Behemoth ($020, 5800 HP) weak ice; Ninja ($003) weak bolt/holy;
-- Apokryphos/Brainpan bolt-weak too; nothing in the pool absorbs bolt.  So
-- Bolt is a GOOD element here -- an earlier comment claimed the opposite
-- off a mis-decode and is retracted.  This config is boost-Fight PHYSICAL
-- (break the pips, then hit with non-elemental weapons): whether that or a
-- boost-then-Bolt beats the 7000-HP Dragon more RELIABLY at this level is
-- the open question (the first R cut, raw-nuking Bolt unboosted, wiped;
-- this one won -- but one win is not reliability).  See the descent lab.
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
                healPercent = 50 }

-- ---- descent (probe_fc_descent -> probe_fc_alcove2) ----------------------
-- The route doc's VALIDATED crossing, in order (floating-continent-route.md
-- §4 "The crossing"): (4,8) -> (19,12) (25,19) (40,12) (40,6)-chute (36,28)
-- (67,39)-walk (40,24) (63,33) (59,39) (52,24) (82,30) (90,43) -> 358.
-- Visited IN ORDER, not nearest-first (the first cut wandered a 21-entry
-- superset nearest-first into (63,28), a tile with no walkable frontier).
-- Shadow is talked in AT THE LANDING (measured, probe_fc_shadow.lua: $035E
-- is already set there and he joins from (10,15)), so there is no (70,29)
-- return trip and no deck re-entry; (70,29) is avoided outright -- with
-- Shadow in, its Yes branch is his scripted REMOVAL.
local TRIG_LEG2 = {
  {19,12},{25,19},{40,12},{40,6},{36,28},{67,39},{40,24},{63,33},
  {59,39},{52,24},{82,30},{90,43},
}
local AVOID_LEG2 = { {60,11}, {70,29} }
local shadowIn = false
local visited, stuckN, preBurst, burst = {}, 0, nil, nil
local function key(c) return c[1] .. "," .. c[2] end
local function triggers() return TRIG_LEG2 end
local function avoid() return AVOID_LEG2 end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end

-- The (70,29) "return?" Yes lands the party on the Blackjack deck with
-- SHADOW posed: wheel right+A, steer dialog $0527 to row 0 ("Find the
-- Floating Continent" -- with $00A0=1 the quick re-arrival, no IAF), the
-- party select again, then talk SHADOW into the party beside (10,16).

-- the fight driver every inline loop below hands battles to
local seenBattles, lastActive = 0, false
local F = H.newFightDriver("fc", FIGHT)

local function round(r)
  local tile = nil
  return H.cond(function() return mapIs(394) end, flatten({
    H.cond(function()
      if not mapIs(394) then return false end
      for _, c in ipairs(H.partyMembers()) do
        if H.charHp(c) < H.charMaxHp(c) * 0.7 then return true end
      end
      return false
    end, { H.fieldCare({ tag = "fc-care r" .. r, threshold = 0.8 }) }, {}),
    H.call(function()
      tile = nil
      -- the next trigger in the leg's ORDER (the doc's validated crossing);
      -- a reachable one is walked, an unreachable one falls to the burst
      local best, bd = nil, 1e9
      for _, c in ipairs(triggers()) do
        local gated = (key(c) == "90,43") and not shadowIn
        if not visited[key(c)] and not gated then
          local p = H.bfsPath(c[1], c[2], nil, nil)
          if p then bd, best = #p, c end
          break
        end
      end
      if best then
        tile = best
        H.log(string.format("[fc r%d] trigger (%d,%d) dist=%d", r, best[1], best[2], bd))
      else
        local cands = {}
        for _, c in ipairs(triggers()) do
          local gated = (key(c) == "90,43") and not shadowIn
          if not visited[key(c)] and not gated then
            local dx, dy = c[1] - H.fieldX(), c[2] - H.fieldY()
            cands[#cands + 1] = { c, dx * dx + dy * dy }
          end
        end
        if #cands == 0 then error("fc r" .. r .. ": all triggers visited, not on 358") end
        table.sort(cands, function(a, b) return a[2] < b[2] end)
        if preBurst ~= nil and preBurst ~= H.fieldX() * 256 + H.fieldY() then stuckN = 0 end
        preBurst = H.fieldX() * 256 + H.fieldY()
        stuckN = stuckN + 1
        burst = cands[((stuckN - 1) % #cands) + 1][1]
        H.log(string.format("[fc r%d] no bfs frontier from (%d,%d); burst toward (%d,%d) (stuck %d)",
          r, H.fieldX(), H.fieldY(), burst[1], burst[2], stuckN))
        if stuckN >= 5 then error(string.format("fc r%d: descent stalled at (%d,%d)", r, H.fieldX(), H.fieldY())) end
      end
    end),
    H.cond(function() return tile == nil and burst ~= nil end, {
      (function()
        local t2, x0, y0, di, still, lastPos = 0, nil, nil, 1, 0, nil
        local dirs = { "right", "down", "left", "up" }
        return H.driveUntil(function()
          if x0 == nil then x0, y0 = H.fieldX(), H.fieldY() end
          if t2 >= 2200 then return true end
          if math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) >= 3 then return true end
          if t2 % 64 == 0 and t2 > 0 then
            for _, c in ipairs(triggers()) do
              local gated = (key(c) == "90,43") and not shadowIn
              if not visited[key(c)] and not gated and H.bfsPath(c[1], c[2], nil, nil) then
                return true
              end
            end
          end
          return false
        end, 2500, {
          H.call(function()
            t2 = t2 + 1
            if H.battleLoadStarted() or H.battleActive() then F.frame(); return end   -- a burst fights what it meets
            if H.dialogWaiting() then H.setPad(t2 % 16 < 4 and { "a" } or {}); return end
            local pos = H.fieldX() * 256 + H.fieldY()
            if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
            if still > 120 then di = di % #dirs + 1; still = 0 end
            local bx, by = burst[1] - H.fieldX(), burst[2] - H.fieldY()
            local d = (still < 60) and (math.abs(bx) >= math.abs(by)
              and (bx > 0 and "right" or "left") or (by > 0 and "down" or "up")) or dirs[di]
            H.setPad({ [d] = true })
          end),
        }, "burst r" .. r)
      end)(),
      H.release(),
      H.waitFrames(30),
      H.call(function() burst = nil end),
    }, {}),
    H.cond(function() return tile ~= nil and H.bfsPath(tile[1], tile[2], nil, nil) ~= nil end, {
      (function()
        local near = false
        return H.navTo(function() return tile[1] end, function() return tile[2] end,
          { maxFrames = 20000, playBattles = "tactical", 
            tool = FIGHT.tool, bank = FIGHT.bank, healPercent = FIGHT.healPercent,
            avoid = avoid(),
            arrive = function()
              if H.fieldX() == tile[1] and H.fieldY() == tile[2] then near = true end
              return near
            end })
      end)(),
      H.call(function() visited[key(tile)] = true; stuckN = 0 end),
    }, {
      H.call(function()
        H.log(string.format("  deferred (%s): unreachable at walk time", tile and key(tile) or "-"))
        tile = nil
      end),
    }),
    (function()
      local t, calm = 0, 0
      return H.driveUntil(function()
        if not mapIs(394) then return true end
        if (H.gameOverFired or 0) > 0 then
          error(string.format("a trigger-settle battle was LOST (r%d) -- a lab, not a retry", r), 0)
        end
        if not H.hasControl() or H.dialogWaiting() then calm = 0; return false end
        calm = calm + 1
        return calm >= 40
      end, 15000, {
        H.call(function()
          t = t + 1
          if H.battleLoadStarted() or H.battleActive() then F.frame(); return end   -- an encounter on the tile is fought
          local mx = H.readByte(0x056F)
          if mx > 0 then
            -- a choice box: the (70,29) return prompt wants YES (row 0) on
            -- leg 1 to go collect SHADOW; every other prompt here is the
            -- last row (the safe "no"/"wait" answers)
            -- the (70,29) prompt dlg $0857 lists "0: (No)  1: (Yes)"
            -- (event_main.asm _ca5a6c): before Shadow the answer is YES --
            -- the return is what makes him appear -- and with him in, NO.
            -- (The first cuts had the rows inverted and stayed on 394.)
            local want = shadowIn and 0 or 1
            local sel = H.readByte(0x056E)
            local ph = t % 24
            if sel < want then H.setPad(ph < 3 and { down = true } or {})
            elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
            else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
            return
          end
          if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
          else H.setPad({}) end
        end),
      }, "trigger settles r" .. r)
    end)(),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[fc r%d] after (%s): map %d (%d,%d)", r,
        tile and key(tile) or "-", map(), H.fieldX(), H.fieldY()))
      if tile ~= nil then
        local d = math.abs(H.fieldX() - tile[1]) + math.abs(H.fieldY() - tile[2])
        if d >= 4 then
          for _, c in ipairs(triggers()) do
            if not visited[key(c)]
               and math.abs(c[1] - H.fieldX()) + math.abs(c[2] - H.fieldY()) <= 2 then
              visited[key(c)] = true
              H.log(string.format("  chute twin (%s) marked visited", key(c)))
            end
          end
        end
      end
    end),
  }), {})
end

-- ---- best-effort kits (the wave-4 pattern) -------------------------------
-- EDGAR arrives from the bench bare; the ladders dress him from whatever
-- the bag holds (present -> worn, absent -> keep, logged).  Ids are the
-- ifrit-kit set, each mask-legal for its wearer.
local function kitSteps(char, name, pairs_)
  local steps = {}
  for _, p in ipairs(pairs_) do
    local slot, item = p[1], p[2]
    local tag = string.format("%s FC kit slot %d", name, slot)
    steps[#steps + 1] = H.cond(
      function() return H.invSlotOf(item) ~= nil end,
      { H.equipLoadout(char, { { slot, item } }, { tag = tag, optional = true }) },
      { H.logStep(string.format("%s: $%02X not in this lineage's bag; keeping current gear", tag, item)) })
  end
  return steps
end


H.run({ maxFrames = 600000 }, flatten({
  -- ---- 0. cold Continue of Q (fc-landing-v1), contract ---------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(394) and H.hasControl() end, 3000,
    "cold Continue to the FC landing SavePoint", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("fc-landing-v1") end),
  -- rows: TERRA (Magic) and EDGAR (Tools) back, LOCKE front -- a no-op once
  -- the seed carries them (gen_fc_landing's deck kit); the Behemoth that
  -- one-shot a front-row TERRA on the (67,39) walk is why it is here
  H.call(function()
    local function row(c) return (H.readByte(0x1850 + c) & 0x20) ~= 0 and "back" or "front" end
    H.log(string.format("[fc rows] before: TERRA %s, LOCKE %s, EDGAR %s", row(TERRA), row(LOCKE), row(EDGAR)))
  end),
  H.setRows({ [TERRA] = true, [EDGAR] = true, [LOCKE] = false }, { tag = "fc rows" }),
  -- ---- 1. SHADOW, at the landing -------------------------------------------
  -- His NPC stands at 394 (10,16) with the switch already on; the two
  -- walkable neighbours are (10,15) and (9,16) (probe_fc_bfs.lua's map
  -- dump: (10,17) and (11,16) are walls).  Walk there with navTo -- a real
  -- walk that fights what it meets -- face him, tap A until he joins.
  (function()
    local cands = { {10,15,"down"}, {9,16,"right"} }
    local out = {}
    for _, c in ipairs(cands) do
      local t3 = 0
      out[#out + 1] = H.cond(function() return not shadowIn end, {
        H.navTo(c[1], c[2], { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
                              items = true, bank = FIGHT.bank,
                              healPercent = FIGHT.healPercent }),
        H.driveUntil(function()
          if (H.gameOverFired or 0) > 0 then
            error("the Shadow talk walk was LOST (game over) -- a lab, not a retry", 0)
          end
          if partyOf(SHADOW) ~= 0 then shadowIn = true end
          return shadowIn or t3 > 600
        end, 1200, {
          H.call(function()
            t3 = t3 + 1
            if H.battleActive() or H.battleLoadStarted() then F.frame(); return end
            if H.dialogWaiting() then H.setPad(t3 % 24 < 3 and { "a" } or {}); return end
            if not H.hasControl() then H.setPad({}); return end
            if H.fieldX() ~= c[1] or H.fieldY() ~= c[2] then H.setPad({}); return end
            local ph = t3 % 40
            if ph < 2 then H.setPad({ [c[3]] = true })
            elseif ph >= 10 and ph < 14 then H.setPad({ "a" })
            else H.setPad({}) end
          end),
        }, string.format("SHADOW joins from (%d,%d)", c[1], c[2])),
      }, {})
    end
    out[#out + 1] = H.call(function()
      H.assertEq(shadowIn, true, "SHADOW joined at the (10,16) talk")
      H.assertEq(sw(0x02F3), 1, "$02F3: SHADOW available again")
      H.log(string.format("SHADOW in at f%d; party now %d", H.frame, #H.partyMembers()))
    end)
    return H.cond(function() return true end, out)
  end)(),
  H.fieldCare({ tag = "care after Shadow", threshold = 0.9 }),
  -- ---- 3. dress the continent party, then the descent ---------------------
  -- The seed carries the party dressed on the deck (gen_fc_landing's deck
  -- kit); verify rather than re-ladder (a ladder re-run would walk the
  -- weaker rungs first).
  H.call(function()
    local base = 0x1600 + 37 * EDGAR
    H.assertEq(H.readByte(base + 0x1F) ~= 0xFF and H.readByte(base + 0x22) ~= 0xFF, true,
      "EDGAR arrives dressed (weapon + armor) from the landing seed")
  end),
  H.fieldCare({ tag = "care on landing", threshold = 0.95 }),
  (function()
    local out = {}
    for r = 1, 24 do
      out[#out + 1] = round(r)
    end
    return out
  end)(),
  -- ---- 4. the alcove: checkpoint R ----------------------------------------
  H.call(function()
    H.assertEq(partyOf(SHADOW) ~= 0, true, "SHADOW in the party")
    H.assertEq(mapIs(358), true, "reached the save alcove (map 358)")
  end),
  -- SHADOW: the bag's spare Genji Glove makes him a second dual-dagger
  -- fighter (Assassin main, ThiefKnife off), Ninja Gear is his armor;
  -- relic first so the off-hand ladder sees a weapon slot, not a shield's
  kitSteps(SHADOW, "SHADOW", { { 4, 0xD1 },
                               { 0, 0x01 }, { 0, 0x04 }, { 0, 0x05 },
                               { 1, 0x01 }, { 1, 0x04 },
                               { 2, 0x69 }, { 2, 0x6B },
                               { 3, 0x84 }, { 3, 0x8A },
                               { 5, 0xB3 } }),
  H.navTo(8, 10, { maxFrames = 4000 }),
  H.fieldCare({ tag = "care at the alcove", threshold = 0.95 }),
  H.call(function()
    H.assertExitContractPreSave("fc-alcove-v1")
    H.assertPartyStanding("fc_alcove exit")
    H.screenshot("fc_alcove_q_tile")
  end),
  H.saveState("fc_alcove.mss"),
  H.saveGame({ slot = 3, tag = "fc-alcove-v1 save" }),
  H.call(function()
    H.assertExitContract("fc-alcove-v1")
  end),
  H.logStep(function()
    return string.format("fc-alcove-v1 saved via the real Save UI at frame %d -- map 358 (%d,%d), slot 3; boundary R",
      H.frame, H.fieldX(), H.fieldY())
  end),
}))

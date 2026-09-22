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

-- Choice windows on these rides go through H.newChoice (lib/ot6_field.lua):
-- steered from the moment $056F reads nonzero ("count", min 1), on this
-- file's 24-frame pulse (a steer press on phase 0-2, the confirm on 12-14),
-- the landed row asserted when the window closes.
local function choicePress(ph, kind)
  if kind == "confirm" then return ph >= 12 and ph < 15 end
  return ph < 3
end


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
-- for the swingers (break the pips, then hit with non-elemental weapons):
-- whether that or a boost-then-Bolt beats the 7000-HP Dragon more
-- RELIABLY at this level is the open question (the first R cut,
-- raw-nuking Bolt unboosted, wiped; this one won -- but one win is not
-- reliability).  See the descent lab.
--
-- TERRA's Vanish line.  The v0.17 requalification (2026-09-07 17:45,
-- build/v017-requal1.log) wiped this segment against a LONE Ninja ($003,
-- 1650 HP, 2 pips slash|pierce, weak bolt|holy) at 394 (57,48): SHADOW's
-- opening Fight took 87 and the Ninja answered with its retaliation
-- (ai_script.asm AIScript::_3: `if_cmd FIGHT / set_target SELF / attack
-- SPECIAL`, its Special is "Inviz"), after which every physical
-- action the party owned -- 42 Fights and 17 AutoCrossbows over 39,000
-- frames -- resolved "took 0 off the monsters (0 hit(s))" while the Ninja
-- hit for 220-839 a round.  This config carried NO magic line, so the
-- driver had nothing a Vanished target cannot dodge, and the party bled out
-- through 36 Potions, 11 Tonics and a Fenix Down (f60848).
--
-- The first fix (19a6de87) gave TERRA a Bolt line and was inert: at this
-- checkpoint NOBODY knows Bolt.  The learned table ($1A6E + 54*char,
-- $FF = learned) read off the regenerated alcove state shows TERRA (L25,
-- 228 MP, SHIVA worn) with $00 Fire, $04 Drain and $05 Fire 2 and no
-- $02; LOCKE, SHADOW and EDGAR know nothing in $00-$17.  spellCell finds
-- no cell and says nothing, so all 13 of her planned turns in that run
-- read "plan=fight" (build/attempts/fc_alcove-attempt1.log).  Her Fight
-- is not idle either -- it took 704, 808 and 1312 off broken targets in
-- the same run -- so a blanket cast line would trade real damage for MP.
--
-- "Inviz" is Vanish, not Image: STATUS1::INVISIBLE (bit 4 of $3ee4 +
-- entity*2, const.inc), under which every physical misses and a spell
-- lands.  A first cut of this gate read STATUS2::IMAGE and never fired
-- while two lab seeds wiped to the same all-zero Ninja fight
-- (worktree build/attempts/lab-try2-imagegate/, seeds p12 and p52), so the gate reads both and
-- says which it saw -- H.dodgerUp, the lib's read of the live status
-- cells (M.dodges on STATUS1 bit 4 / STATUS2 bit 2 of each monster on
-- stage, #190).
--
-- So the line is what a person does on seeing the Ninja fade out: while a
-- live monster is Vanished (or Imaged), TERRA casts Fire 2 (20 MP; the
-- plan-time absorb guard still refuses it on a fire absorber); otherwise
-- the lookup is empty and she Fights as before.
local FIRE2 = 0x05
local dodgeSaid = nil
local MAGIC = setmetatable({}, { __index = function(_, id)
  if id ~= TERRA then return nil end
  local s, what = H.dodgerUp()
  if s == nil then dodgeSaid = nil; return nil end
  if dodgeSaid ~= s then
    dodgeSaid = s
    H.log(string.format("[fc] slot %d wears %s (f%d): TERRA's attack turns go to Fire 2", s, what, H.frame))
  end
  return { spell = FIRE2 }
end })
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
                healPercent = 50, magic = MAGIC }

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
-- the descent reload sweep's state (see descentAttempt below): a lost
-- attempt sets `lost` and every later step of the crossing stands down
local lost, lostWhy, descentWon, landingBlob = false, nil, false, nil
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
  return H.cond(function() return mapIs(394) and not lost end, flatten({
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
          if (H.gameOverFired or 0) > 0 then
            lost, lostWhy = true, lostWhy or string.format("wiped in a burst battle, r%d", r)
            return true
          end
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
            magic = FIGHT.magic,
            -- a wipe ends the ride for the reload sweep instead of raising
            wipeEndsRide = true,
            avoid = avoid(),
            arrive = function()
              if H.fieldX() == tile[1] and H.fieldY() == tile[2] then near = true end
              return near
            end })
      end)(),
      H.call(function()
        visited[key(tile)] = true; stuckN = 0
        if (H.gameOverFired or 0) > 0 or H.partyWipedInBattle() then
          lost, lostWhy = true, lostWhy or string.format("wiped on the walk to (%s), r%d", key(tile), r)
        end
      end),
    }, {
      H.call(function()
        H.log(string.format("  deferred (%s): unreachable at walk time", tile and key(tile) or "-"))
        tile = nil
      end),
    }),
    (function()
      local t, calm = 0, 0
      -- a choice box: the (70,29) return prompt wants YES (row 0) on
      -- leg 1 to go collect SHADOW; every other prompt here is the
      -- last row (the safe "no"/"wait" answers)
      -- the (70,29) prompt dlg $0857 lists "0: (No)  1: (Yes)"
      -- (event_main.asm _ca5a6c): before Shadow the answer is YES --
      -- the return is what makes him appear -- and with him in, NO.
      -- (The first cuts had the rows inverted and stayed on 394.)
      local C = H.newChoice(function() return shadowIn and 0 or 1 end,
        { ready = "count", min = 1, press = choicePress, tag = "trigger settles r" .. r })
      return H.driveUntil(function()
        if lost then return true end
        if not mapIs(394) then return true end
        if (H.gameOverFired or 0) > 0 then
          -- a lost crossing is reloaded from the landing save (descentAttempt)
          lost, lostWhy = true, lostWhy or string.format("wiped in a trigger-settle battle, r%d", r)
          return true
        end
        if not H.hasControl() or H.dialogWaiting() then calm = 0; return false end
        calm = calm + 1
        return calm >= 40
      end, 15000, {
        H.call(function()
          t = t + 1
          if H.battleLoadStarted() or H.battleActive() then F.frame(); return end   -- an encounter on the tile is fought
          if C.frame(t % 24) then return end
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

-- ---- the descent reload sweep --------------------------------------------
-- The crossing is a save-point-to-save-point segment: a person who wipes
-- on 394 reloads the landing save at (7,12) and crosses again, and the
-- pool they cross is a gamble (Ninja, Behemoth packs, two 7000-HP
-- Dragons).  So the descent rides the gen_fc_escape shape: a complete
-- machine snapshot at the landing after care (docs/TESTING.md: restore a
-- coherent snapshot, never selected cells), up to ATTEMPTS crossings, each
-- loss reloaded from that snapshot with the battle seed's phase spread
-- (H.newSeedSweep: a repeated seed fails the report), and every attempt's
-- verdict and seed in the log.  A won attempt is a search-selected win --
-- the attempt table is the record, not a rate -- and the loss lines are
-- the balance finding.  H.run carries allowGameOver so the wipe canary
-- counts the loss without ending the run; each navTo carries
-- wipeEndsRide so the ride ends instead of raising; the burst and settle
-- loops set `lost` on the canary's counter.
local ATTEMPTS = 3
local LD = H.newSeedSweep("FC descent (394 crossing)", { attempts = ATTEMPTS })
local function seq(steps) return H.cond(function() return true end, steps) end

local function lossReload(n)
  local req
  return seq({
    H.call(function()
      H.log(string.format("[descent] attempt %d LOST at f%d (%s) -- reloading the landing snapshot, "
        .. "as a person reloads the 394 (7,12) save", n - 1, H.frame, lostWhy or "?"))
      req = H.requestLoadState(landingBlob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "descent: loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[descent] loss-reload done, GameOver cleared, f%d", H.frame))
    end),
    H.waitFrames(90),
  })
end

local function descentAttempt(n)
  local rounds = {}
  for r = 1, 24 do rounds[#rounds + 1] = round(r) end
  return H.cond(function() return descentWon end, {}, flatten({
    n > 1 and lossReload(n) or seq({}),
    H.call(function()
      lost, lostWhy = false, nil
      visited, stuckN, preBurst, burst = {}, 0, nil, nil
      H.log(string.format("[descent] attempt %d at f%d, map %d (%d,%d), fenix=%d potion=%d tonic=%d",
        n, H.frame, map(), H.fieldX(), H.fieldY(),
        H.invCountOf(FENIX_DOWN), H.invCountOf(POTION), H.invCountOf(TONIC)))
    end),
    LD.spread(n),
    rounds,
    H.call(function()
      if mapIs(358) and not lost then
        descentWon = true
        H.log(string.format("[descent] attempt %d reached the alcove (map 358) at f%d", n, H.frame))
      else
        H.log(string.format("[descent] attempt %d did not reach the alcove: map %d (%d,%d), lost=%s (%s)",
          n, map(), H.fieldX(), H.fieldY(), tostring(lost), lostWhy or "-"))
        lost = true
      end
    end),
  }))
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
      { H.logStep(string.format("%s: $%02X not in this run's bag; keeping current gear", tag, item)) })
  end
  return steps
end


-- allowGameOver: the descent ladder handles a wipe (a counted loss and a
-- reload of the landing snapshot); every step outside it still raises on
-- H.gameOverFired, so an unhandled game over is still a failed run.
H.run({ maxFrames = 600000, allowGameOver = true }, flatten({
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
                              items = true, bank = FIGHT.bank, magic = FIGHT.magic,
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

  -- ---- 2b. dress SHADOW and sit him down, HERE ----------------------------
  -- #221: these two steps used to happen at the save alcove, after the
  -- crossing was over, and H.setRows above runs before the (10,16) talk
  -- that adds him -- so SHADOW crossed the whole continent at
  -- `gear=FF,FF,FF,FF relics=FF,FF` in the FRONT row.  Three of the v0.18
  -- qualification's four deaths were his, and 15 of 24 across the lab's
  -- 12-seed spread.  Measured over that spread (docs/design/fc-alcove.md,
  -- logs under build/lab/fc-alcove/): 24 deaths / 20 Fenix / 1 lost
  -- crossing becomes 7 / 7 / 0, and the mean falls 45,020 -> 39,504 frames.
  --
  -- The ROW is the lever.  In the back row the median of every physical
  -- landing on him halves -- Brainpan Battle 279 -> 146, Wirey Drgn Wing
  -- 792 -> 409, Behemoth Take Down 1130 -> 565 -- and the Ninja's Fire
  -- Skean, which is magical, is unchanged.  Dressing him WITHOUT moving
  -- him measured worse than leaving both alone (17 deaths, 2 wipes in 6
  -- seeds), so the two steps travel together.
  --
  -- A player collects a naked guest, opens the menu on the spot and puts
  -- him where he will not be hit; nobody walks a bare-handed Shadow across
  -- a continent in the front row.  Both steps must land before the descent
  -- snapshot below, because the sweep reloads it on every attempt.
  kitSteps(SHADOW, "SHADOW", { { 4, 0xD1 },
                               { 0, 0x01 }, { 0, 0x04 }, { 0, 0x05 },
                               { 1, 0x01 }, { 1, 0x04 },
                               { 2, 0x69 }, { 2, 0x6B },
                               { 3, 0x84 }, { 3, 0x8A },
                               { 5, 0xB3 } }),
  H.setRows({ [SHADOW] = true }, { tag = "SHADOW to the back row" }),
  H.call(function()
    H.assertEq((H.readByte(0x1850 + SHADOW) & 0x20) ~= 0, true,
      "SHADOW is in the back row for the crossing (#221)")
    local base = 0x1600 + 37 * SHADOW
    H.assertEq(H.readByte(base + 0x1F) ~= 0xFF, true,
      "SHADOW carries a weapon into the crossing (#221)")
    H.assertEq(H.readByte(base + 0x22) ~= 0xFF, true,
      "SHADOW wears armor into the crossing (#221)")
  end),

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
  -- the landing snapshot the sweep reloads: the whole machine, taken on
  -- the field with control, after Shadow joined and the party was cared
  -- for (the state a person's landing save holds)
  (function()
    local ckReq
    return seq({
      H.waitUntil(function() return H.hasControl() and not H.dialogWaiting() end, 600,
        "the landing snapshot: field control", 10),
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "the landing snapshot")
        landingBlob = ckReq.blob
        H.log(string.format("[descent] landing snapshot taken at f%d, map %d (%d,%d), %d bytes",
          H.frame, map(), H.fieldX(), H.fieldY(), #landingBlob))
      end),
    })
  end)(),
  LD.watch(),
  (function()
    local out = {}
    for n = 1, ATTEMPTS do out[#out + 1] = descentAttempt(n) end
    return out
  end)(),
  -- the ladder's own audit runs as a step (every attempt that spread must
  -- have drawn a distinct battle seed) before the verdict
  LD.report(),
  H.call(function()
    if not descentWon then
      error(string.format("all %d descent attempts lost; the [descent] attempt lines above "
        .. "are the balance finding (a lab candidate for the owner)", ATTEMPTS), 0)
    end
  end),
  -- ---- 4. the alcove: checkpoint R ----------------------------------------
  H.call(function()
    H.assertEq(partyOf(SHADOW) ~= 0, true, "SHADOW in the party")
    H.assertEq(mapIs(358), true, "reached the save alcove (map 358)")
  end),
  -- SHADOW's kit (the bag's spare Genji Glove makes him a second
  -- dual-dagger fighter, Assassin main and ThiefKnife off, with Ninja Gear
  -- for armor) was put on at the landing instead -- see 2b.  Wearing it
  -- here, after the crossing, was #221.
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

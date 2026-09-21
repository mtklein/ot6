-- gen_fc_escape.lua -- from the Floating Continent's save alcove
-- (checkpoint Q, `fc-alcove-v1`) to the World of Ruin's first ground:
-- AtmaWeapon, the statues, the 6:00 escape past Nerapa, Shadow's wait,
-- and the airship's flight into the RUIN cutscene.  Generates
-- wor_landing.mss (no battery cut: nothing between the alcove and the
-- WoR landing is a save point, and the escape clock forbids the menu).
--
-- The step: cold-Continue `fc-alcove-v1` at map 358 (8,10), assert its
-- contract, top up, walk out onto 394 and up to AtmaWeapon's doorstep
-- (60,16) below his NPC at (60,15), talk with the clean gesture (face,
-- release, A while stationary), FIGHT him with the tactical driver until
-- switch $035F clears, heal back on 394, climb the stair spine onto the
-- (60,11) statue trigger, absorb the scene onto the escape map 393 at
-- (67,16) -- the 6:00 master clock and the 5:55 Shadow clock start at
-- Shadow's "Get outta here" and run through menus and battles, so no
-- field menu from here -- east to Nerapa at (108,15) (face right, A ->
-- battle 81), past (112,15) to the ledge (115,17), answer "Wait!!" (the
-- last choice row) and hold until Shadow arrives ($037D), then absorb the
-- exit flow as far as it goes and bank the landing.  Every fight is real;
-- nothing is written.
--
-- Technique sources (read-only probes): probe_fc_atma4/atma5 (doorstep
-- and talk), probe_fc_statues (the spine), probe_fc_escape (the route,
-- Nerapa, the wait).  Party: TERRA (no stone; Fire 2 is her attack spell),
-- LOCKE (MADUIN: Bolt -- Atma and Nerapa are bolt-weak; Nerapa ABSORBS
-- fire, and the driver's absorb guard keeps Fire2 off him), EDGAR (SHIVA),
-- SHADOW.  The stones are read off the checkpoint, not assumed: see the
-- learned-table note at FIGHT below.
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


local TERRA = 0x00
local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function atmaUp() return (H.readByte(0x1EEB) >> 7) & 1 == 1 end      -- $035F
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361
local function shadowSaved() return (H.readByte(0x1EEF) >> 5) & 1 == 1 end -- $037D

local LOCKE = 0x01
local EDGAR = 0x04            -- Shiva's bearer on the escape (the summon table)
-- The attack-magic lines, read off the learned table of the checkpoint this
-- boots ($1A6E + 54*char, $FF = learned; tools/savestate_party.py's shape
-- finder on fc-alcove-v1's payload, 2026-09-16) rather than assumed:
--   TERRA  L26, no stone (+$1E = $FF): $00 Fire, $04 Drain, $05 Fire 2,
--          $2A Warp, $2D Cure, $30 Life, $32 Antdot -- and no Bolt.
--   LOCKE  L28, MADUIN worn (+$1E = $06): nothing learned in $00-$35.
--   EDGAR  L27, SHIVA worn (+$1E = $02): nothing learned.
--   SHADOW L26, no stone: nothing learned.
-- The battle Magic list is the union of what the actor knows and the worn
-- stone's spells (spellCell's note in the lib), so LOCKE's Bolt is live for
-- as long as he wears Maduin (Fire/Ice/Bolt): the 2026-09-16 16:17 run cast
-- it five times at "cell 8, 6 MP", 465 and 9999 off AtmaWeapon.  The first
-- cut gave TERRA the same `spell = 2` and it was inert (#182): no Bolt in
-- her list, spellCell finds no cell, and all 10 of her planned turns in
-- that run read plan=fight.
--
-- TERRA's line is gen_fc_alcove's (f531997e): the 394 pool is the same
-- seven species, and the Ninja's "Inviz" is Vanish (STATUS1::INVISIBLE,
-- bit 4 of $3ee4 + entity*2), under which every physical misses and a
-- spell lands.  While a live monster is Vanished (or Imaged) her attack
-- turns cast Fire 2 ($05, 20 MP; the plan-time absorb guard still refuses
-- it on a fire absorber, and Nerapa absorbs fire); otherwise the lookup is
-- empty and she Fights as before -- on AtmaWeapon (weak fire|ice|bolt +
-- slash|pierce, 11 pips) her sword chips the slash row and unloaded 6964
-- on him broken in that run, which a blanket cast line would preempt.
-- Bolt stays the party nuke: Atma and Nerapa are bolt-weak, nothing on 394
-- absorbs it, and LOCKE is the one who can pay it.
local BOLT, FIRE2, ST1_INVISIBLE, ST2_IMAGE = 0x02, 0x05, 0x10, 0x04
local dodgeSaid = nil
local function dodgerUp()
  for s = 0, 5 do
    if H.readWord(0x3BFC + s * 2) > 0 then
      local e = 4 + s
      if (H.readByte(0x3EE4 + e * 2) & ST1_INVISIBLE) ~= 0 then return s, "Vanish" end
      if (H.readByte(0x3EE5 + e * 2) & ST2_IMAGE) ~= 0 then return s, "Image" end
    end
  end
  return nil
end
local MAGIC = setmetatable({ [LOCKE] = { spell = BOLT } }, { __index = function(_, id)
  if id ~= TERRA then return nil end
  local s, what = dodgerUp()
  if s == nil then dodgeSaid = nil; return nil end
  if dodgeSaid ~= s then
    dodgeSaid = s
    H.log(string.format("[fc] slot %d wears %s (f%d): TERRA's attack turns go to Fire 2", s, what, H.frame))
  end
  return { spell = FIRE2 }
end })
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
                healPercent = 60, magic = MAGIC, nuke = { BOLT } }
local FA = H.newFightDriver("fc", FIGHT)
-- AtmaWeapon under his own tag (the Fenix audit files it as the boss it is)
local FAtma = H.newFightDriver("AtmaWeapon", FIGHT)
-- The escape runs under the 6:00 master clock (21600 frames; it RUNS in
-- menus and battles, so no field care from here).  The 393 walks are
-- FOUGHT (playBattles="tactical", no BP banking, physical damage only):
-- measured 2026-09-07 from the escape_start snapshot, the map's pool is
-- one formation, Naughty ($169, 3000 HP, 5 pips), whose monster_prop +19
-- bit 3 is the no-run flag: $b1 reads $06 from frame 3 of every encounter
-- met, and the physical line wins each in ~1,200-1,900 frames -- four of
-- them cost 7,700-8,300 frames of clock and the party reached Nerapa's
-- doorstep at 3:41-3:51.  (The earlier "mustflee" walk could not run
-- here and said so: $b1 bit 1 is the escape command's own can't-run
-- gate, which is the bit the flee helper reads -- #150, measured on
-- camp_escaped where the same helper released the party from two
-- randoms.)  No nuke/summon on the walks: with nuke={2} the navTo
-- driver's Bolt plan parked in menu state $05 ("consumed 41 pulses ...
-- without landing", ten drops) and the party bled out over 12,000 frames
-- (lab V0/V1) -- Naughty's Mute greys LOCKE's Magic row and the command
-- cursor skips it; the driver now plans around a disabled row (#153).
-- Nerapa (2800 HP, 5 pips, weak ice|bolt|holy + slash|pierce, absorbs fire,
-- Condemned on the whole party at the open -- measured: all four carry it
-- by t=3000 with ~30 s on the count, and it kills at t~7,000): a damage
-- race of ~5,500 frames.  EDGAR wears SHIVA ($02: ice, his weakness) and
-- summons it once, LOCKE nukes Bolt (through MADUIN), EDGAR's crossbow
-- pierces, SHADOW fights; TERRA wears no stone (byte +$1E is $FF on the
-- fc-alcove-v1 payload, $02 on EDGAR's record -- an earlier note here had
-- them the other way round; the 2026-09-16 16:17 run's own lines are
-- "actor=2 char=4 plan=summon" and "summon refused for char 0: ...
-- stone=$FF", so the summon table's TERRA entry is inert and EDGAR's is
-- the live one).  On the current ROM this fight is a coin flip on its seed:
-- the 2026-09-07 gen run (mustflee walk, doorstep at 3:51) lost it with
-- two Fenix Downs and a wipe at t~7,800; the same policy from the same
-- snapshot with the fight walk (doorstep at 3:41) won it at t~6,000 with
-- 1:48 left (labs V2/V3 -- identical traces, so healPercent 20/40 and a
-- TERRA Bolt line changed no decision; the lethal-next-round heal rule
-- and the summon line dominate).
-- opts.summon = { [charId] = { mp = cost } }: Shiva's Diamond Dust is 27
-- MP (battle_magicite measures it); Ramuh's divine is listed at 30 as a
-- conservative affordability check (TERRA carries 228).
local FIGHT_ESCAPE = { tactical = true, boost = true, bank = 0, items = true,
                       healPercent = 40, nuke = { 2 },
                       summon = { [TERRA] = { mp = 30 }, [EDGAR] = { mp = 27 } } }
local FE = H.newFightDriver("Nerapa", FIGHT_ESCAPE)
-- the ledge wait's randoms: the same policy under another tag, so the
-- Fenix audit files them as randoms, not as the boss
local FW = H.newFightDriver("ledge", FIGHT_ESCAPE)
local ESCAPE_WALK = { playBattles = "tactical", bank = 0,
                      healPercent = 60, care = false }
-- Timer data (field-ram.txt:684-692): 4 records of 6 bytes at $1188 --
-- byte 0 flags "pfrm----" (p = pauses in menu and battle), +1 the frame
-- counter (word), +3 the event pointer.  Timer 0 is the master clock
-- (counts DOWN from 21600), timer 2 Shadow's arrival.
local function clock(tag)
  return H.call(function()
    local f0, c0 = H.readByte(0x1188), H.readWord(0x1189)
    local f2, c2 = H.readByte(0x1188 + 12), H.readWord(0x1189 + 12)
    H.log(string.format("[escape clock] %s: master=%d frames (%d:%02d) flags=%02X%s | shadow=%d flags=%02X | at (%d,%d) f%d",
      tag, c0, c0 // 3600, (c0 % 3600) // 60, f0, (f0 & 0x80) ~= 0 and " (pauses in menu/battle)" or " (runs in menu/battle)",
      c2, f2, H.fieldX(), H.fieldY(), H.frame))
  end)
end

-- ride a stretch: fights with the driver, dialogs A-tapped, choice boxes
-- steered to `row` (a function of the choice count), until pred()
local function absorb(pred, cap, tag, row, driver)
  local t = 0
  local C = H.newChoice(function(_, mx) return row and row(mx) or (mx - 1) end,
    { ready = "count", min = 1, press = choicePress, tag = tag })
  driver = driver or FA
  return H.driveUntil(function()
    t = t + 1
    if (H.gameOverFired or 0) > 0 then
      error(string.format("%s: the party was LOST (game over) -- a lab, not a retry", tag), 0)
    end
    return t >= cap or pred()
  end, cap + 500, {
    H.call(function()
      if t % 2400 == 0 then
        H.log(string.format("  [%s] t=%d map=%d (%d,%d) dlg=%s ctrl=%s", tag, t,
          map(), H.fieldX(), H.fieldY(), tostring(H.dialogWaiting()), tostring(H.hasControl())))
      end
      if H.battleLoadStarted() or H.battleActive() then driver.frame(); return end
      if C.frame(t % 24) then return end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, tag)
end

-- the clean talk gesture: tap `face` to turn, release, tap A while
-- stationary; retried on a cadence until a battle loads
local function talk(face, cap, tag)
  local t = 0
  return H.driveUntil(function()
    t = t + 1
    return t >= cap or H.battleActive() or H.battleLoadStarted()
  end, cap + 300, {
    H.call(function()
      local c = t % 48
      if c < 4 then H.setPad({ [face] = true })
      elseif c >= 24 and c < 28 then H.setPad({ a = true })
      else H.setPad({}) end
    end),
  }, tag)
end

-- ---- the Nerapa seed ladder ---------------------------------------------
-- Nerapa is a real loseable fight under two clocks (Condemned on the whole
-- party at the open, the 6:00 escape clock), and on the current ROM the
-- same policy wins or loses it on the battle seed alone (the 2026-09-07
-- attempts: lost at t~7,800 with two Fenix Downs from one doorstep
-- arrival, won at t~6,000 with none from another).  So it rides the
-- gen_massacre / gen_ultros shape: a savestate at the doorstep, a
-- 5-rung seed ladder (H.newSeedLadder spreads the battle seed's phase
-- across the rungs and fails on a repeated seed), each loss reloaded
-- from that snapshot -- the whole machine, clocks included, so every
-- attempt opens with the same time left -- and the ladder's report
-- names the seed of every attempt.  A won rung is a search-selected
-- win: the attempt table is the record, not a rate.
local L81 = H.newSeedLadder("Nerapa (battle 81)", { attempts = 5 })
local nerapaBlob, nerapaWon = nil, false
local function seq(steps) return H.cond(function() return true end, steps) end

local function lossReload(blobFn, tag)
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blobFn()) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, tag .. ": loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[%s] loss-reload done, GameOver cleared, f%d",
        tag, H.frame))
    end),
    H.waitFrames(90),
  })
end

-- A rung is LOST, and reloaded, on any of: the GameOver canary, a
-- battle-side wipe, the 30,000-frame cap, more than FENIX_BUDGET Fenix
-- Downs spent in the fight (a person whose party is being raised over
-- and over under Condemned does not grind the bag down -- the ninja run
-- of 2026-09-07 08:20 "won" a rung with thirteen and the clock at 0:00),
-- or a win that leaves the master clock under CLOCK_MARGIN (Shadow's
-- timer fires 300 frames before the master clock and the party must be
-- standing on the ledge, ~180 frames from the doorstep, when it does;
-- a Nerapa kill at 0:00 is the escape lost).
local FENIX_BUDGET, CLOCK_MARGIN = 3, 900
-- The field bag ($1969) is synced back from the battle module only at
-- teardown, so mid-fight the count comes from the battle inventory:
-- $2686, 256 records of 5 bytes, +0 item index, +3 quantity
-- (battle-ram.txt:456-475).  The first ninja run of the ladder read the
-- field bag and declared its rung lost at the fight's end, thirteen
-- Fenix Downs late.
-- Read only once the battle is ACTIVE, and hand back the rung's baseline
-- when no $F0 record is found: during battle load the table is not yet
-- populated, and the third ninja run scanned it two frames after seeding,
-- read "no Fenix Downs" as 27 spent, and threw all five rungs away.
local function fenixNow(baseline)
  if H.battleActive() then
    for i = 0, 255 do
      if H.readByte(0x2686 + i * 5) == 0xF0 then return H.readByte(0x2689 + i * 5) end
    end
    return baseline
  end
  if H.battleLoadStarted() then return baseline end
  return H.invCountOf(0xF0)
end
local function nerapaAttempt(n)
  local F = H.newFightDriver("Nerapa", FIGHT_ESCAPE)
  local wipedN, lost, why, fenix0 = 0, false, nil, nil
  return H.cond(function() return nerapaWon end, {}, {
    n > 1 and lossReload(function() return nerapaBlob end, "Nerapa") or seq({}),
    -- the bag is sampled AFTER the reload (the reload restores it): the
    -- second ninja run sampled it before and reported rung 2 at -11 spent
    H.logStep(function()
      fenix0 = H.invCountOf(0xF0)
      return string.format("[Nerapa] attempt %d at f%d, master clock %d, fenix=%d", n, H.frame, H.readWord(0x1189), fenix0)
    end),
    L81.spread(n),
    talk("right", 4000, string.format("Nerapa engaged (attempt %d)", n)),
    (function()
      local t = 0
      return H.driveUntil(function()
        t = t + 1
        if (H.gameOverFired or 0) > 0 then lost, why = true, "game over"; return true end
        -- the loss the canary misses: a battle-side wipe (attempt 1 of
        -- 2026-09-07 sat 22,000 frames past its wipe with no GameOver read)
        if H.partyWipedInBattle() then wipedN = wipedN + 1 else wipedN = 0 end
        if wipedN >= 300 then lost, why = true, "wiped"; return true end
        if t >= 30000 then lost, why = true, "30000-frame cap"; return true end
        if fenix0 - fenixNow(fenix0) > FENIX_BUDGET then
          lost, why = true, string.format("%d Fenix Downs spent (budget %d)", fenix0 - fenixNow(fenix0), FENIX_BUDGET)
          return true
        end
        if t % 300 == 0 then
          -- the count over each member (H.doomCount, #190: the number
          -- shown, nil when not condemned); the driver plans on it
          local st = {}
          for slot = 0, 3 do
            local count = H.doomCount({ s2 = H.readByte(0x3EE5 + slot * 2),
                                        count = H.readByte(0x3B05 + slot * 2) })
            st[#st + 1] = string.format("%d:%s", slot, count and ("C" .. count) or "-")
          end
          H.log(string.format("[Nerapa] attempt %d t=%d condemned %s master=%d", n, t,
            table.concat(st, " "), H.readWord(0x1189)))
        end
        return not nerapaUp() and not H.battleActive() and not H.battleLoadStarted()
      end, 30500, {
        H.call(function()
          if lost then H.setPad({}); return end
          if H.battleLoadStarted() or H.battleActive() then F.frame(); return end
          if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) else H.setPad({}) end
        end),
      }, string.format("Nerapa falls ($0361 clears), attempt %d", n))
    end)(),
    H.call(function()
      H.setPad({})
      local clock = H.readWord(0x1189)
      if not lost and not nerapaUp() and clock < CLOCK_MARGIN then
        lost, why = true, string.format("Nerapa fell with %d frames on the clock (margin %d)", clock, CLOCK_MARGIN)
      end
      if not lost and not nerapaUp() then
        nerapaWon = true
        H.log(string.format("[Nerapa] WON on attempt %d at f%d, master clock %d, fenix=%d (%d spent)",
          n, H.frame, clock, H.invCountOf(0xF0), fenix0 - H.invCountOf(0xF0)))
      else
        H.log(string.format("[Nerapa] attempt %d LOST at f%d: %s (master clock %d, fenix spent %d)",
          n, H.frame, why or "not won", clock, fenix0 - H.invCountOf(0xF0)))
      end
    end),
  })
end

H.run({ maxFrames = 600000, allowGameOver = true }, {
  -- ---- 0. cold Continue of Q -----------------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(358) and H.hasControl() end, 3000,
    "cold Continue to the alcove (358)", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fc-alcove-v1")
    H.assertEq(sw(0x01B5), 1, "$01B5 set: the (70,29) return prompt is dead (its event self-gates on it)")
    H.log(string.format("[escape] Q at 358 (%d,%d); atma=%s nerapa=%s",
      H.fieldX(), H.fieldY(), tostring(atmaUp()), tostring(nerapaUp())))
  end),
  H.fieldCare({ tag = "top-up at the alcove", threshold = 0.95 }),

  -- ---- 1. out onto 394 and up to AtmaWeapon's doorstep ---------------------
  -- the alcove's exit puts the party back on 394 beside the (90,43) reveal;
  -- the stairs revealed on the descent stay revealed (event bits), so the
  -- BFS walker climbs to the doorstep directly, avoiding the statue
  -- trigger (60,11) that only the post-Atma leg may step.
  -- the exit trigger is 358 (8,8), NORTH of the SavePoint (8,10)
  -- (event_trigger.asm:1753-1754: the party arrives at (8,7), walks down
  -- past it to save); the first cut held DOWN and never left
  H.navTo(8, 9, { maxFrames = 3000, playBattles = "tactical", healer = TERRA }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return mapIs(394) end, 1800, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "alcove (8,9) -> up through (8,8) -> 394")
  end)(),
  H.call(function()
    H.assertEq(mapIs(394), true, "back on the continent (394)")
    H.log(string.format("[escape] on 394 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- The reveals do NOT persist across a map load (measured, probe_fc_exit.lua
  -- on the R seed: (89,25) reads F7 until (82,30) is stepped again; the
  -- reveal event then takes control for a moment and the tiles change).
  -- So the approach is hop by hop: step a reveal, let its event settle,
  -- then walk what it opened.  The plateau (x56-64, y3-25) is entered only
  -- by the (63,28) reveal's ladder (63,25-27).  (70,29) -- the "return?"
  -- prompt whose Yes branch would be Shadow's scripted removal -- is DEAD
  -- on this seed: its event self-gates on $01B5, which the alcove's own
  -- entry (90,43) set (event_trigger.asm:1962); the link from the tunnel's
  -- (70,25) landing to (63,28) runs through it, so it is walked, not
  -- avoided (the boot log below records the switch).
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright() >= 15 end, 900, "control back on 394", 10),
  H.waitFrames(30),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] on 394 at (%d,%d) $b2=%02X: (82,30) %s (89,25) %s (63,28) %s",
      H.fieldX(), H.fieldY(), H.readByte(0x00b2), v(82, 30), v(89, 25), v(63, 28)))
  end),
  H.navTo(82, 30, { maxFrames = 20000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    arrive = function() return H.fieldX() == 82 and H.fieldY() == 30 end }),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 1800, "the (82,30) reveal settles", 10),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the (82,30) reveal: (89,25) %s", v(89, 25)))
  end),
  H.navTo(89, 25, { maxFrames = 20000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    arrive = function() return H.fieldX() < 80 or (H.fieldX() == 89 and H.fieldY() == 25) end }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return H.hasControl() and H.tileAligned() and H.fieldX() < 80 end, 3000, {
      H.call(function()
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the (89,25) tunnel lands west")
  end)(),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the tunnel at (%d,%d): (63,28) %s (63,33) %s (60,16) %s", H.fieldX(), H.fieldY(), v(63, 28), v(63, 33), v(60, 16)))
  end),
  H.navTo(63, 28, { maxFrames = 40000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    avoid = { { 60, 11 } }, arrive = function() return H.fieldX() == 63 and H.fieldY() == 28 end }),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 1800, "the (63,28) reveal settles", 10),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the (63,28) reveal at (%d,%d): (63,25) %s (60,16) %s (60,14) %s", H.fieldX(), H.fieldY(), v(63, 25), v(60, 16), v(60, 14)))
  end),
  -- the ladder (63,27..25): climb by holding UP (ladder tiles "always face
  -- up"); the BFS's verdict on (63,25) above says whether it could path it
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return H.hasControl() and H.fieldX() == 63 and H.fieldY() <= 25
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "climb the (63,25-27) ladder onto the plateau")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] on the plateau at (%d,%d): (60,16) %s, (60,14) %s", H.fieldX(), H.fieldY(), v(60, 16), v(60, 14)))
  end),
  -- the doorstep: (60,16) below the NPC at (60,15) (face UP), else (60,14)
  -- above it (face DOWN); (60,11) is the POST-Atma statue trigger, avoided
  H.cond(function() return H.bfsPath(60, 16, nil, nil) ~= nil end, {
    H.navTo(60, 16, { maxFrames = 40000, playBattles = "tactical", magic = FIGHT.magic,
      bank = FIGHT.bank, healPercent = FIGHT.healPercent, avoid = { { 60, 11 } },
      arrive = function() return H.fieldX() == 60 and H.fieldY() == 16 end }),
  }, {
    H.navTo(60, 14, { maxFrames = 40000, playBattles = "tactical", magic = FIGHT.magic,
      bank = FIGHT.bank, healPercent = FIGHT.healPercent, avoid = { { 60, 11 } },
      arrive = function() return H.fieldX() == 60 and H.fieldY() == 14 end }),
  }),
  H.fieldCare({ tag = "before AtmaWeapon", threshold = 0.95 }),
  H.call(function()
    H.assertEq(atmaUp(), true, "$035F set -- AtmaWeapon stands at (60,15)")
    H.screenshot("atma_doorstep")
  end),

  -- ---- 2. AtmaWeapon --------------------------------------------------------
  (function()
    return H.cond(function() return H.fieldY() == 16 end,
      { talk("up", 4000, "AtmaWeapon engaged (from the south)") },
      { talk("down", 4000, "AtmaWeapon engaged (from the north)") })
  end)(),
  absorb(function()
    return not atmaUp() and not H.battleActive() and not H.battleLoadStarted()
  end, 60000, "AtmaWeapon falls ($035F clears)", nil, FAtma),
  H.call(function()
    H.assertEq(atmaUp(), false, "$035F cleared -- AtmaWeapon defeated")
    H.log(string.format("[escape] post-Atma at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("atma_down")
  end),
  -- The win hands straight into a scripted stretch (Shadow's departure
  -- _cad9fc, then the statue scene); ride it -- dialogs A-tapped, any
  -- battle fought -- until the field hands control back, and only then
  -- heal (a scene that never does is exempt: the care is conditional).
  absorb(function() return H.hasControl() and not H.dialogWaiting() end, 6000,
    "post-Atma: the field hands control back"),
  H.cond(function() return H.hasControl() and not H.dialogWaiting() end, {
    H.fieldCare({ tag = "post-atma", threshold = 0.95 }),
    -- TERRA's Blizzard ($0E) is ICE, and the escape map's pool has an
    -- ice-absorber (species $0169: the lib's absorb guard failed the first
    -- run at its first 393 encounter).  The spare MithrilBlade ($0A,
    -- non-elemental) is hers for the escape; her Fight is not her damage.
    H.equipKit(TERRA, { { 0, 0x0A } }, { tag = "TERRA: MithrilBlade for the escape" }),
  }, {
    H.logStep(function() return "[escape] post-Atma: no field control (scripted); care skipped" end),
  }),
  H.release(),
  H.waitFrames(30),

  -- ---- 3. the statue spine onto (60,11) -> map 393 --------------------------
  (function()
    local wps = { { 60, 14 }, { 60, 12 }, { 60, 11 } }
    local wi, t, wt, lastK, lastT = 1, 0, 0, -1, 0
    -- any choice here takes row 0, pressed on phase 0-2; the check sits
    -- above the battle branch, as it always has, so it is not battle-gated
    local C = H.newChoice(0, { ready = "count", min = 1, inBattle = false,
      press = function(ph) return ph < 3 end, tag = "statue spine" })
    return H.driveUntil(function() t = t + 1; return mapIs(393) end, 60000, {
      H.call(function()
        if C.frame(t % 24) then return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if not H.hasControl() then H.setPad({}); return end
        local wp = wps[wi]
        if not wp then H.setPad({}); return end
        local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
        wt = wt + 1
        if (dx == 0 and dy == 0) or wt > 700 then wi, wt = wi + 1, 0; H.setPad({}); return end
        local px = dx > 0 and "right" or "left"
        local py = dy > 0 and "down" or "up"
        local k = H.fieldX() * 256 + H.fieldY()
        if k ~= lastK then lastK, lastT = k, t end
        if t - lastT > 240 then
          -- the y12-14 stairs are prop-3 tiles that only move on diagonal input
          local alts = dy ~= 0
            and { { [py] = true, left = true }, { [py] = true, right = true },
                  { [py] = true }, { left = true }, { right = true } }
            or { { [px] = true, up = true }, { [px] = true, down = true },
                  { [px] = true }, { up = true }, { down = true } }
          H.setPad(alts[(math.floor(t / 36) % #alts) + 1])
          return
        end
        H.setPad(math.abs(dx) >= math.abs(dy) and { [px] = true } or { [py] = true })
      end),
    }, "statue scene -> map 393")
  end)(),
  (function()
    local calm = 0
    return H.driveUntil(function()
      if H.hasControl() and not H.dialogWaiting() then calm = calm + 1 else calm = 0 end
      return calm >= 30
    end, 20000, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "escape start settled")
  end)(),
  H.call(function()
    H.assertEq(mapIs(393), true, "on the escape map (393)")
    H.log(string.format("[escape] clocks running: t0=%d t2=%d at (%d,%d)",
      H.readWord(0x1188), H.readWord(0x118C), H.fieldX(), H.fieldY()))
    H.screenshot("escape_start")
  end),
  -- escape_start: the lab fixture for the 6:00 clock (declared with
  -- also= in the graph): first control on 393 with both clocks running,
  -- so an escape-policy experiment branches here instead of replaying
  -- AtmaWeapon and the statue scene.
  H.saveState("escape_start.mss"),

  -- ---- 3b. dress CELES under the clock ---------------------------------------
  -- The statue scene hands CELES over as the escape's fourth with every
  -- slot $FF (benched bare since the Vector crash), and she fights the
  -- whole escape that way unless dressed here -- the field menu opens on
  -- 393 and the clock runs through it.  Measured (lab V4, 2026-09-07):
  -- one Equip session and one Relic session cost 1,349 frames of clock
  -- (21,537 -> 20,188), the Break Blade $11 and relics $B1/$B5 landed, and
  -- the shield/helm/armor rungs ($84, $5B/$5A, $6B/$69) were refused by
  -- her own list at ~120-150 frames each, so they are not asked for.
  H.call(function()
    local base = 0x1600 + 37 * 6
    H.log(string.format("[escape] CELES before the kit: %02X %02X %02X %02X %02X %02X master=%d",
      H.readByte(base + 0x1F), H.readByte(base + 0x20), H.readByte(base + 0x21),
      H.readByte(base + 0x22), H.readByte(base + 0x23), H.readByte(base + 0x24), H.readWord(0x1189)))
  end),
  H.equipKit(6, { { 0, 0x11 }, { 0, 0x0E }, { 0, 0x0A },
                  { 4, 0xB1 }, { 5, 0xB5 } }, { tag = "CELES escape kit", ladder = true }),
  H.call(function()
    local base = 0x1600 + 37 * 6
    H.log(string.format("[escape] CELES after the kit: %02X %02X %02X %02X %02X %02X master=%d",
      H.readByte(base + 0x1F), H.readByte(base + 0x20), H.readByte(base + 0x21),
      H.readByte(base + 0x22), H.readByte(base + 0x23), H.readByte(base + 0x24), H.readWord(0x1189)))
    H.assertEq(H.readByte(base + 0x1F) ~= 0xFF, true, "CELES holds a weapon for the escape")
  end),

  -- ---- 4. Nerapa, the ledge, the wait ---------------------------------------
  clock("out of the statue scene, CELES dressed"),
  H.navTo(106, 15, { maxFrames = 20000, playBattles = ESCAPE_WALK.playBattles,
    bank = ESCAPE_WALK.bank, healPercent = ESCAPE_WALK.healPercent, care = false }),
  clock("at Nerapa's doorstep"),
  -- (no doorstep care: the field care refuses under a live event timer,
  -- rightly -- the clock runs in menus -- so healing is the fight's own,
  -- in battle)
  H.release(),
  H.waitFrames(30),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "pre-Nerapa checkpoint")
        nerapaBlob = ckReq.blob
        H.log(string.format("[Nerapa] doorstep savestate captured at f%d, master clock %d", H.frame, H.readWord(0x1189)))
      end),
    })
  end)(),
  L81.watch(),
  nerapaAttempt(1),
  nerapaAttempt(2),
  nerapaAttempt(3),
  nerapaAttempt(4),
  nerapaAttempt(5),
  -- the ladder's own audit runs as a step (report() is a step: it asserts
  -- that every attempt drew a distinct battle seed, so five losses are five
  -- different fights and not one fight five times) before the verdict
  L81.report(),
  H.call(function()
    if not nerapaWon then
      error("all 5 Nerapa seed-ladder attempts lost; the per-attempt lines above "
        .. "are the balance finding (a lab candidate for the owner)", 0)
    end
    H.assertEq(nerapaUp(), false, "Nerapa defeated")
    H.log(string.format("[escape] post-Nerapa: (%d,%d) t0=%d", H.fieldX(), H.fieldY(), H.readWord(0x1188)))
  end),
  clock("post-Nerapa"),
  H.navTo(112, 15, { maxFrames = 8000, playBattles = ESCAPE_WALK.playBattles,
    bank = ESCAPE_WALK.bank, care = false }),
  (function()
    local near = false
    return H.navTo(115, 17, { maxFrames = 8000, playBattles = ESCAPE_WALK.playBattles,
      bank = ESCAPE_WALK.bank, care = false,
      arrive = function()
        if H.fieldX() == 115 and H.fieldY() == 17 then near = true end
        return near
      end })
  end)(),
  (function()
    local t = 0
    local C = H.newChoice(function(_, mx) return mx - 1 end,
      { ready = "count", min = 1, press = choicePress, tag = "the humane wait" })
    return H.driveUntil(function() t = t + 1; return t >= 26000 or shadowSaved() end, 26500, {
      H.call(function()
        if t % 2400 == 0 then
          H.log(string.format("  [wait] t=%d map=%d (%d,%d) dlg=%s t0=%d t2=%d", t,
            map(), H.fieldX(), H.fieldY(), tostring(H.dialogWaiting()),
            H.readWord(0x1188), H.readWord(0x118C)))
        end
        if H.battleLoadStarted() or H.battleActive() then FW.frame(); return end
        if C.frame(t % 24) then return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if x == 115 and y == 17 then H.setPad({}); return end
        local ph = t % 24
        if ph >= 3 then H.setPad({}); return end
        if x < 115 then H.setPad({ right = true })
        elseif x > 115 then H.setPad({ left = true })
        elseif y < 17 then H.setPad({ down = true })
        else H.setPad({ up = true }) end
      end),
    }, "the humane wait ($037D)")
  end)(),
  H.call(function()
    H.assertEq(shadowSaved(), true, "$037D set -- Shadow saved")
  end),

  -- ---- 5. the exit flow and the landing ---------------------------------------
  -- the landing: the opening's dialogs page for ~5,000 frames after the
  -- party reaches (100,38) before control returns (measured; the route
  -- doc s6), so the wait logs every control component while on 397
  (function()
    local t = 0
    local C = H.newChoice(0, { ready = "count", min = 1, press = choicePress,
      tag = "the landing" })
    return H.driveUntil(function()
      t = t + 1
      if (H.gameOverFired or 0) > 0 then error("the landing was LOST (game over)", 0) end
      return t >= 60000 or (mapIs(397) and H.hasControl() and not H.dialogWaiting())
    end, 60500, {
      H.call(function()
        if mapIs(397) and t % 1200 == 0 then
          local pobj = H.readWord(0x0803)
          H.log(string.format("[landing] t=%d (%d,%d) $1eb9=%02X $0084=%02X $0059=%02X pobj=%04X mvtype=%02X event=%s battle=%s dlg=%s ctrl=%s $ba=%02X $d3=%02X evpc=%02X%02X%02X",
            t, H.fieldX(), H.fieldY(), H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059), pobj,
            H.readByte(0x087c + pobj) & 0x0F, tostring(H.eventRunning()), tostring(H.battleLoadStarted()),
            tostring(H.dialogWaiting()), tostring(H.hasControl()), H.readByte(0x00ba), H.readByte(0x00d3),
            H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
        end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if C.frame(t % 24) then return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "the airship flees, the RUIN cutscene, the Solitary Island (397)")
  end)(),
  (function()
    local calm = 0
    return H.driveUntil(function()
      if H.hasControl() and not H.dialogWaiting() and mapIs(397) then calm = calm + 1 else calm = 0 end
      return calm >= 60
    end, 20000, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "landing settled")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp + 1] = tostring(H.charHp(c)) end
    H.log(string.format("landing: map=%d (%d,%d) party=%d hp=%s $00A4=%d $037D=%d",
      map(), H.fieldX(), H.fieldY(), #H.partyMembers(), table.concat(hp, "/"),
      (H.readByte(0x1E94) >> 4) & 1, (H.readByte(0x1EEF) >> 5) & 1))
    -- route doc s6: the WoR opening lands solo CELES at the Solitary
    -- Island bedside, map 397 {100,38}, WoR flag $00A4=1, after Cid's
    -- fish request hands control back -- the World of Balance's stop line
    H.assertEq(mapIs(397), true, "solo Celes at the Solitary Island bedside (map 397)")
    H.assertEq((H.readByte(0x1E94) >> 4) & 1, 1, "$00A4 set -- the World of Ruin")
    H.assertEq(#H.partyMembers(), 1, "the party is Celes alone")
    H.screenshot("wor_landing")
  end),
  H.saveState("wor_landing.mss"),
  H.logStep(function() return "wor_landing generated: the World of Balance is played through" end),
})

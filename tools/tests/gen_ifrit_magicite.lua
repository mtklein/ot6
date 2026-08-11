-- gen_ifrit_magicite.lua -- v0.6 step 8, the step OUT of boundary B (#25):
-- cold battery Continue from the tracked mrf-save-room-v1 checkpoint (the
-- map-270 save room, slot 3), the boundary's entry contract asserted
-- first, then down through the {3,5} door to the alcove ->
-- battle 70 -> the four-interaction esper hand-off -> both magicite in
-- the bag.  Generates magicite_ifrit_shiva.
--
-- Generated from a checkpoint (savestate_graph.py:
-- checkpoint="mrf-save-room-v1").  The step used to boot ifrit_entry.mss; it
-- now starts from power-on and lets Mesen load the checkpoint battery
-- run.sh materialized, so a ROM change re-runs this step from its own
-- checkpoint in parallel with every other step instead of behind the whole
-- serial trunk (docs/design/checkpoint-fixtures.md).  ifrit_entry stays
-- generated as A->B's terminal; the ~15-step walk from the save tile to the
-- fight is replayed here from the checkpoint instead.
--
-- The hand-off is four separate NPC interactions rather than one scene, and the
-- gates interlock (event_main.asm:95260-95385):
--
--   _cc7937  IFRIT {3,8}, sw $0646   first talk: walks SLOT_1 five tiles
--            RIGHT (so the party is left at {8,7} when the fight opens),
--            `battle 70`, then dlg $055F and `switch $0060=1 / $0273=1`
--   _cc7986  IFRIT, second talk      `switch $0272=1`; if $0274 also set,
--                                    fall into _cc79a4
--   _cc7992  SHIVA {9,6}, sw $0646   `if_switch $0060=0, EventReturn`, so
--                                    she will not talk before the fight;
--                                    then `switch $0274=1`; if $0272 also
--                                    set, fall into _cc79a4
--   _cc79a4  the hand-off            `$0646=0 / $0647=1 / $0648=1 / $0273=0`,
--                                    which swaps both esper NPCs for
--                                    MAGICITE NPCs on the same two tiles
--   _cc79cd  MAGICITE {3,8}, sw $0647   give_genju IFRIT, `$0647=0`
--   _cc79dd  MAGICITE {9,6}, sw $0648   give_genju SHIVA, `$0648=0`
--
-- `give_genju` (EventCmd_86, field/event.asm:3238) sets bit (id-$36) of
-- $1A69, and GENJU::RAMUH=$36 / IFRIT=$37 / SHIVA=$38 (include/const.inc
-- :564-566), so the receipts are $1A69 bits 1 and 2 and they are what this
-- step asserts, rather than a switch that only records that a scene ran.
--
-- Correction to the route recon's battle-70 decode, which read it as
-- formation 439 containing "species $0109 Ifrit only", said
-- "Shiva $0108 is NOT in the formation ... she is not in any formation in
-- the game -- I swept all 576", and listed "does Shiva enter via the AI
-- script?" as probe 1.  Measured live at the entry point, the formation
-- species words $57C0 read
--
--     0109 0108 0109 0108 FFFF FFFF
--
-- at battle start: **Shiva is in the formation from the first frame.**  No
-- AI-script entrance is involved.  (gen_ifrit_entry.lua's post-generation
-- verification is where that is measured; it is re-asserted below.)
--
-- THE FIGHT IS PLAYED, NOT WRITE-CLEARED (issue #75).  The
-- battle-clear-write helper this file carried is gone (bosses-wob.md
-- section 13: Ifrit 6 shields weak ice + piercing, Shiva 6 weak fire +
-- slashing, vanilla's tag fight):
--
--   * THE PARTY RE-EQUIPS FIRST -- H.equipOptimum through the real field
--     Equip menu.  The Vector infiltration's `remove_equip`
--     (event_main.asm:11979-11988) stripped everyone and returned the gear
--     TO INVENTORY, and no generator between there and here ever re-equipped,
--     so the checkpoint's party arrives with LOCKE and CELES bare-handed
--     (tools/audit_equipment.py names them).  A player opens the menu
--     before a boss; so does this step, pad input only.
--   * THE FIGHT IS THE LIBRARY FIGHTER'S -- H.newFightDriver, tactical +
--     boost bank + real Item heals and Fenix revival.  See the block over
--     ifritAttempt for why battle_brokendeath's Celes-Ice machine, which
--     the handoff called proven, is NOT reused: measured on today's
--     fixtures it wipes -- the tag keeps Ifrit off stage for most of the
--     fight and that machine has no heal plan.
--   * THE END IS THE SCRIPT'S OWN: Ifrit & Shiva do not end by dying --
--     killing Ifrit runs his `if_self_dead` block (the recognition scene,
--     ai_script.asm:4551-4562) and end_battle.  Neither _cc7937's tail nor
--     _cc79a4 reads a battle switch, so the win latches on control return
--     (recon probe 5) -- $0060/$0273 are asserted below.
--
-- THE RETRY LADDER (gen_tunnelarmr's): battle 70 is an event battle, so a
-- loss is GAME OVER, not a revive.  The entry point is captured as a blob
-- beside the walk, and each attempt reloads it and waits a different
-- number of frames before the A press -- the battle RNG seed is the frame
-- phase at battle init (gen_whelk_poweron's measurement), so each retry
-- genuinely plays a different fight.  Three attempts, then fail loudly.
-- The combat CONTRACT for this fight (break observed pre-kill, the
-- if_self_dead placement guard) stays in battle_brokendeath.lua, booted on
-- ifrit_entry.mss; this step only needs a real win banked.
--
-- Incidental traversal battles on the walk (there have never been any on
-- maps 270/264, but the branch exists) FLEE by the real L+R mechanic --
-- gen_ifrit_entry's idiom, zero writes.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this step understands (issue #25).  run.sh
--   reads the marker line above and refuses -- BEFORE the emulator boots,
--   naming both strings -- any OT6_SRAM_CHECKPOINT whose manifest.json declares
--   a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); H.cond with an always-true
-- predicate is the library's public way to wrap a list into ONE step
local function seq(steps) return H.cond(function() return true end, steps) end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hold off while a scene controls
-- it, edge-A through dialogs.  Used to walk into a trigger whose scene then
-- takes over; the tap keeps the party from sliding past the tile.
-- A battle here (never yet seen on these two maps) is FLED with the real
-- L+R run mechanic -- gen_ifrit_entry's idiom, zero writes.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- Stop tapping once the party is on the target tile.  The
        -- terminator needs 16 consecutive calm frames there, and a further
        -- tap walks off it before the count completes: the first version of
        -- this rode the chute correctly to (10,45), then tapped itself to
        -- (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end


-- Hold a direction into an NPC and edge-press A until `pred` latches.
-- The direction press is safe because every NPC this step talks to occupies
-- the destination tile, so the step is refused and only the facing takes
-- (the face-an-NPC idiom).  Hands off entirely while a scene owns control.
-- A battle mid-talk (never yet seen here) is FLED with the real L+R run.
local function talkTo(dir, pred, maxFrames, what)
  local ph, calm, hb = 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("talkTo(%s) f%d (%d,%d) ctl=%s dlg=%s batt=%s",
          dir, H.frame, H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.dialogWaiting()), tostring(H.battleLoadStarted())))
      end
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not settled() or pred() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a", dir } or { dir })
    end),
  }, what)
end

-- -------------------- battle 70, played with real input (issue #75) ------
-- The drive is the LIBRARY's shared observed-menu fighter, H.newFightDriver
-- -- tactical (EDGAR fires AutoCrossbow, SABIN Pummels), boost BANKED to 3
-- and unloaded (the break economy: a boosted hit chips a shield), real Item
-- heals and Fenix Down revival -- the same configuration that beat VARGAS
-- on attempt 1 (gen_kolts, 2026-08-09).
--
-- WHY NOT battle_brokendeath's Celes-Ice machine, which the handoff called
-- proven: it was MEASURED here first and it LOSES on today's fixtures.
-- Run on the fresh ifrit_entry (generated 2026-08-09), battle_brokendeath
-- itself wipes -- party 0/0/0/0 at f6309 with Ifrit still at 3057 hp and
-- 5 of 6 shields.  Traced on this step's checkpoint party, the mechanism is
-- the tag: its Ice/AutoCrossbow policy is gated on Ifrit being ON STAGE,
-- and in every run measured Ifrit took the stage for ~2400 frames, tagged
-- out, and stayed hidden for the next ~7800 while Shiva soaked the specials
-- (she got broken and RE-SEEDED her shields, 0 -> 6, mid-fight).  Exactly
-- one Ice ever fired (CELES mp 106 -> 101), the party had no heal plan, and
-- it died of attrition every time.  The library fighter has the heal
-- plan; its boosted Fights chip WHOEVER is up (slashing chips Shiva --
-- measured, sh 6 -> 3 under plain Fights -- and AutoCrossbow's pierce
-- chips Ifrit).  The tag means the fight is long; the budget carries it.
local IFRIT, SHIVA = 0x0109, 0x0108

local function eoff(m) return 8 + m * 2 end
local function mshields(m) return H.readByte(0x3E38 + eoff(m)) end
local function mticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)      return H.readWord(0x3BFC + m * 2) end
local function onfield(m)  return H.readByte(0x3AA8 + m * 2) & 1 end
local function mspecies(m) return H.readWord(0x57C0 + m * 2) end

local fightBlob, fightWon = nil, false

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Reloads the entry point blob (attempt 1
-- runs in place -- the live timeline IS the blob's timeline), offsets the
-- RNG phase, presses A into IFRIT, plays battle 70, and decides on $0060:
-- _cc7937's tail sets it within ~2000 frames of the teardown, while a loss
-- rides the Annihilated screen into GAME OVER and never sets it.
local function ifritAttempt(n)
  local loadReq
  local ISLOT, SSLOT = nil, nil
  local sawBreak, ideathFrame, ideathTicks, sdeathFrame = false, nil, nil, nil
  local hb, ph, giveUp = 0, 0, 0
  local F = H.newFightDriver("b70", { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, cadence = 12 })
  return H.cond(function() return fightWon end, {}, {
    H.logStep(function()
      return string.format("battle 70 attempt %d (phase offset %d) at f%d",
        n, (n - 1) * 37, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(fightBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "entry point reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 264, "reloaded onto map 264")
        H.assertEq(H.fieldX() == 3 and H.fieldY() == 7, true,
          "reloaded at the (3,7) entry point")
      end),
    }) or seq({}),
    H.waitFrames((n - 1) * 37),         -- vary the battle RNG seed
    -- A into IFRIT -> _cc7937 -> battle 70.  Confirm the formation before
    -- fighting it: this is the fight the step exists to pass through, and a
    -- win over the WRONG battle would look identical in the log without
    -- the assert.
    H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.hold({ "a", "down" }), H.waitFrames(4), H.hold({ "down" }), H.waitFrames(4),
    }, "A into IFRIT -> battle 70"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),
    H.call(function()
      local w = H.formationWords()
      H.log(string.format("[battle 70] formation = %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
      H.assertEq(H.formationHas({ [IFRIT] = true }), true, "battle 70 has IFRIT $0109")
      H.assertEq(H.formationHas({ [SHIVA] = true }), true,
        "battle 70 has SHIVA $0108 FROM THE FIRST FRAME -- the recon's "
        .. "'Shiva is in no formation in the game' is wrong")
      -- the LIVE monsters sit in slots 0/1; $57C0 repeats both species at
      -- 2/3 with dead entities behind them, so the LOWEST slot per species
      -- wins (battle_brokendeath's ghost-slot lesson)
      for m = 5, 0, -1 do
        if mspecies(m) == IFRIT then ISLOT = m end
        if mspecies(m) == SHIVA then SSLOT = m end
      end
      H.assertEq(ISLOT ~= nil, true, "an IFRIT slot resolved")
      H.assertEq(SSLOT ~= nil, true, "a SHIVA slot resolved")
      -- NO-STAGING CONTROLS (issue #75): both gauges seed FULL and both HP
      -- words read their authored values -- numbers a rigged run could
      -- never show (break-coverage-vector.md §2 "The bosses" / bosses-wob.md 13).
      H.assertEq(mshields(ISLOT), 6, "ifrit opens with his authored 6 shields")
      H.assertEq(mshields(SSLOT), 6, "shiva opens with her authored 6 shields")
      H.assertEq(mhp(ISLOT), 3300, "ifrit opens at his authored 3300 HP")
      H.assertEq(mhp(SSLOT), 3000, "shiva opens at her authored 3000 HP")
      H.assertEq(mticks(ISLOT), 0, "ifrit is NOT pre-broken")
      H.screenshot("ifrit_battle")
    end),
    -- hands OFF until Ifrit takes the stage (the fly-in; input during the
    -- window-open animation wedges the battle menu -- battle_break's lesson)
    H.waitUntil(function() return onfield(ISLOT) == 1 end, 3600,
      "ifrit takes the stage", 10),
    H.waitFrames(90),
    -- the input-driven fight: the library fighter, with gauge logging
    -- around it.  Its own menu==0 branch pages battle text, the recognition
    -- scene's dialogs and the victory teardown, so this one drive carries
    -- the whole battle from fly-in to field.
    H.driveUntil(function() return not H.battleLoadStarted() end, 90000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format(
            "f%d ifr hp=%d sh=%d tk=%d fld=%d | shv hp=%d sh=%d tk=%d | party %d/%d/%d/%d",
            H.frame, mhp(ISLOT), mshields(ISLOT), mticks(ISLOT), onfield(ISLOT),
            mhp(SSLOT), mshields(SSLOT), mticks(SSLOT),
            H.readWord(0x3BF4), H.readWord(0x3BF6),
            H.readWord(0x3BF8), H.readWord(0x3BFA)))
        end
        if not sawBreak and ((mshields(ISLOT) == 0 and mticks(ISLOT) ~= 0)
            or (mshields(SSLOT) == 0 and mticks(SSLOT) ~= 0)) then
          sawBreak = true
          H.log(string.format("first BREAK at f%d (ifr sh=%d tk=%d | shv sh=%d tk=%d)",
            H.frame, mshields(ISLOT), mticks(ISLOT),
            mshields(SSLOT), mticks(SSLOT)))
        end
        if not ideathFrame and mhp(ISLOT) == 0 then
          ideathFrame, ideathTicks = H.frame, mticks(ISLOT)
          H.log(string.format("IFRIT hp hit 0 at f%d (broken timer %d)",
            ideathFrame, ideathTicks))
        end
        if not sdeathFrame and mhp(SSLOT) == 0 then
          sdeathFrame = H.frame
          H.log(string.format("SHIVA hp hit 0 at f%d", sdeathFrame))
        end
        F.frame()
      end),
    }, "battle 70, played (tactical + boost bank + real items)"),
    H.call(function() F.idle(); H.setPad({}) end),
    H.logStep(function()
      return string.format(
        "battle 70 torn down at f%d (break %s; ifrit down %s; shiva down %s); deciding",
        H.frame, sawBreak and "observed" or "NOT observed",
        ideathFrame and ("f" .. ideathFrame .. " tk=" .. ideathTicks) or "no",
        sdeathFrame and ("f" .. sdeathFrame) or "no")
    end),
    -- won or lost?  Tap A while control is away (pages dlg $055F and, on a
    -- loss, the Annihilated screen); give the tail 3000 frames to flip
    -- $0060 before calling the attempt lost.
    H.driveUntil(function()
      giveUp = giveUp + 1
      return sw(0x0060) == 1 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        ph = (ph + 1) % 8
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the _cc7937 tail flips $0060 (or the loss shows itself)"),
    H.call(function()
      H.setPad({})
      if sw(0x0060) == 1 then
        fightWon = true
        H.log(string.format("battle 70 WON on attempt %d, f%d "
          .. "(tactical + boost bank + items, the if_self_dead ending)", n, H.frame))
      else
        H.log(string.format("attempt %d LOST (no $0060 after teardown), f%d",
          n, H.frame))
      end
    end),
  })
end

H.run({ maxFrames = 300000 }, {
  -- COLD BATTERY BOOT (issue #25): title -> Continue -> the sole valid
  -- slot (3) -> the map-270 save room, standing on the tile the checkpoint
  -- was saved on.  Repeated edge presses tolerate title timing; the entry
  -- contract below prevents a false landing.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- SOFT landing wait: a wrong-boundary checkpoint lands somewhere else, and
  -- the failure must be the entry contract NAMING the wrong map -- never a
  -- timeout here (checkpoint-fixtures.md, "fails loudly, naming what differed").
  H.waitUntilSoft(function()
    return map() == 270 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_b"),
  H.waitFrames(60),
  H.call(function()
    -- THE ENTRY CONTRACT (issue #25): everything this step requires of
    -- boundary B -- the save tile, slot, switches, the #21 party count and
    -- roster, and the bank-$31 codex witnesses -- declared as DATA in
    -- lib/ot6_contract.lua under "mrf-save-room-v1", the same table the
    -- step INTO B (gen_ifrit_entry) and the checkpoint generator
    -- (gen_mrf_save_room_checkpoint) assert as their EXIT contract.  A stale
    -- or wrong checkpoint fails HERE by naming what differed.
    H.assertEntryContract("mrf-save-room-v1")
    H.log(partyReport("mrf-save-room-v1 entry"))
  end),

  -- down through the save room's door and back to the fight's entry point
  tapInto("down", function() return map() == 264 end, 12000,
    "save room -> door -> map 264"),
  H.waitFrames(60),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(map(), 264, "at the Ifrit/Shiva alcove")
    H.assertEq(H.fieldX(), 3, "Ifrit entry point x")
    H.assertEq(H.fieldY(), 7, "Ifrit entry point y")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR at the entry point")
    H.assertEq(H.readByte(0x1A69) & 0x06, 0,
      "neither IFRIT nor SHIVA owned yet ($1A69 bits 1-2)")
    H.log(partyReport("ifrit entry point (walked from checkpoint B)"))
  end),

  -- 1. the player's prep: the checkpoint's party arrives with LOCKE and CELES
  --    bare-handed (the Vector remove_equip, never re-equipped since) --
  --    real field Equip -> Optimum per character, a no-op for anyone armed.
  --    BEFORE the retry blob, so every attempt replays an armed party.
  H.equipOptimum({ tag = "ifrit kit" }),
  -- 1b. the rest of the player's prep: HEAL.  The checkpoint battery was cut
  --    with EDGAR at 108/354 and SABIN at 113/363, both about 31%, and a cold
  --    Continue restores exactly that -- FF6's save point saves without
  --    healing, so the party walks in at the HP it was saved at.  Every
  --    comparable step already tops up first (battle_brokendeath:296 before
  --    THIS fight, gen_esper_tubes:331 before battle 72, gen_n128:469,
  --    gen_banquet_done:570); this one was the only boss step with no
  --    H.fieldCare at all, and that omission is what lost the ladder.
  --    Measured on the unhealed run: the fight driver's healPercent=60 is
  --    already unmet at the fight's first frame, so it opens in a heal
  --    deadlock and never leaves it -- 87 of 100 actions across all three
  --    attempts were item uses, LOCKE attacked exactly zero times, and
  --    attempts 1 and 2 ended with IFRIT untouched at 3300 hp / 6 shields.
  --    Threshold and tag match battle_brokendeath's call for this fight.
  H.fieldCare({ tag = "care before battle 70", threshold = 0.95 }),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 3 and H.fieldY() == 7, true,
      "back at the entry point, armed")
    H.log(partyReport("ifrit entry point, armed"))
    -- The prep above has to be checked, not assumed: a fieldCare that
    -- silently no-ops and an equipOptimum that silently no-ops both leave a
    -- party that loses the fight for a reason the battle log does not name.
    -- That is exactly how this step failed before -- it read as a balance
    -- wall.  Require the numbers the prep is supposed to produce.
    for _, c in ipairs(H.partyMembers()) do
      local base = 0x1600 + 37 * c
      local hp, maxhp = H.readWord(base + 0x09), H.readWord(base + 0x0B)
      H.assertEq(maxhp > 0, true, CHARS[c + 1] .. " has a max HP")
      H.assertEq(hp * 100 >= maxhp * 90, true, string.format(
        "%s enters battle 70 topped up (%d/%d, want >= 90%%)",
        CHARS[c + 1], hp, maxhp))
      H.assertEq(H.readByte(base + 0x1F) ~= 0xFF, true,
        CHARS[c + 1] .. " enters battle 70 holding a weapon")
    end
  end),
  -- capture the entry point as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry point retry blob")
        fightBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #fightBlob))
      end),
    })
  end)(),

  -- 2. battle 70, played with real input, on the phase-spread retry ladder
  ifritAttempt(1),
  ifritAttempt(2),
  ifritAttempt(3),
  H.call(function()
    H.assertEq(fightWon, true,
      "battle 70 won within 3 attempts (the library fighter: "
      .. "tactical + boost bank + real items)")
  end),
  -- ride the post-battle tail out to a settled field ($0060 already
  -- latched; playBattles=true -- no battle can occur here, and none ever has)
  H.advanceStory(function() return sw(0x0060) == 1 and settled() end, 12000,
    { playBattles = true }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x0060), 1, "$0060 SET -- battle 70 won (recon probe 5: the "
      .. "win latches on control return)")
    H.assertEq(sw(0x0273), 1, "$0273 SET -- the alcove is locked until the hand-off")
    H.log(string.format("[after battle 70] at (%d,%d)", H.fieldX(), H.fieldY()))
    H.log(partyReport("ifrit_won"))
    H.screenshot("ifrit_won")
  end),

  -- 3. SHIVA at {9,6}: stand at {9,7} and face UP.  $0274.
  H.navTo(9, 7, { maxFrames = 9000, playBattles = "flee" }),
  talkTo("up", function() return sw(0x0274) == 1 end, 12000,
    "talk SHIVA -> $0274"),

  -- 4. IFRIT again at {3,8}: $0272, which (with $0274 already set) falls
  --    straight into _cc79a4, the hand-off.
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  talkTo("down", function() return sw(0x0647) == 1 and sw(0x0648) == 1 end,
    16000, "talk IFRIT -> $0272 -> the hand-off _cc79a4"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x0272), 1, "$0272 SET -- IFRIT spoken to after the fight")
    H.assertEq(sw(0x0274), 1, "$0274 SET -- SHIVA spoken to after the fight")
    H.assertEq(sw(0x0646), 0, "$0646 CLEAR -- both dying espers are gone")
    H.assertEq(sw(0x0647), 1, "$0647 SET -- IFRIT's magicite is on {3,8}")
    H.assertEq(sw(0x0648), 1, "$0648 SET -- SHIVA's magicite is on {9,6}")
    H.assertEq(sw(0x0273), 0, "$0273 CLEAR -- the alcove is unlocked again")
    H.screenshot("mrf_handoff")
  end),

  -- 5. the two magicite pickups
  talkTo("down", function() return (H.readByte(0x1A69) & 0x02) ~= 0 end, 12000,
    "take the IFRIT magicite -> $1A69 bit1"),
  H.navTo(9, 7, { maxFrames = 9000, playBattles = "flee" }),
  talkTo("up", function() return (H.readByte(0x1A69) & 0x04) ~= 0 end, 12000,
    "take the SHIVA magicite -> $1A69 bit2"),
  H.waitFrames(60),

  H.call(function()
    H.assertEq(map(), 264, "still on map 264")
    H.assertEq(H.readByte(0x1A69) & 0x01, 0x01, "RAMUH still owned ($1A69 bit0)")
    H.assertEq(H.readByte(0x1A69) & 0x02, 0x02, "IFRIT owned (give_genju $37)")
    H.assertEq(H.readByte(0x1A69) & 0x04, 0x04, "SHIVA owned (give_genju $38)")
    H.assertEq(sw(0x0647), 0, "$0647 CLEAR -- IFRIT's magicite has been taken")
    H.assertEq(sw(0x0648), 0, "$0648 CLEAR -- SHIVA's magicite has been taken")
    -- the way onward was NO-PATH while Shiva stood on {9,6}; now it is not
    H.assertEq(H.bfsPath(9, 5) ~= nil, true,
      "the door to map 269 (9,5) is open now that {9,6} is clear")
    H.log(string.format("[magicite_ifrit_shiva] f%d map=%d (%d,%d) $1A69=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x1A69)))
    H.log(partyReport("magicite_ifrit_shiva"))
    H.screenshot("magicite_ifrit_shiva")
  end),
  H.saveState("magicite_ifrit_shiva.mss"),
  -- RELOAD-VERIFIED (gen_sabin_gau's pattern, a trap this program has paid
  -- for): capture-calm does NOT imply reload-calm, so reload the parked
  -- moment and require the consumer's boot to find it quiet.
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(map(), 264, "reload: still on map 264")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(H.dialogWaiting(), false, "reload: no dialog pending")
        H.assertEq(H.hasControl() and H.tileAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.readByte(0x1A69) & 0x07, 0x07,
          "reload: RAMUH+IFRIT+SHIVA still owned")
        H.log("generated-state verify: the reload stayed calm -- magicite_ifrit_shiva verified")
      end),
    })
  end)(),
  H.call(function()
    census("magicite_ifrit_shiva", {
      { 3, 5, "door -> map 270 (save room)" },
      { 9, 5, "door -> map 269 (onward)" },
      { 6, 6, "_cc75f6, back up to 263" },
    })
  end),
  H.logStep(function()
    return string.format("magicite_ifrit_shiva generated at frame %d -- map 264, "
      .. "$1A69=%02X (RAMUH+IFRIT+SHIVA)", H.frame, H.readByte(0x1A69))
  end),
})

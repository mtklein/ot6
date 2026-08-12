-- gen_n128.lua -- v0.6 step 13, the step OUT of boundary D (#25): the
-- minecart platform (map 272, CID at {9,51}) -> A -> `cutscene TRAIN` ->
-- the minecart's six forced battles, NUMBER 128 among them -> the Kefka
-- explosion on map 240 -> control with $0069=1 -> parked ON the escape
-- map's save point {58,7} (boundary E).  Generates n128_won.
--
-- One boot, from a checkpoint (issue #25; the dual-boot probe retired by
-- #30): every caller, both the ninja graph's generation edge and `make smoke`
-- (via the Makefile's SMOKE_CHECKPOINT_* map), supplies OT6_SRAM_CHECKPOINT=
-- minecart-platform-v1, so run.sh materializes the checkpoint .srm and SRAM
-- carries slot 3, the codex magic and the seeded ULTROS2 witness.  Cold
-- Continue -> the 272 save tile {3,55} -> entry contract -> walk to CID.
-- This file used to probe four SRAM bytes at runtime and fall back to
-- booting minecart_entry.mss when they were absent (smoke's old
-- checkpointless invocation).  With the checkpoint map there is no
-- checkpointless caller left, and a boot chosen by inspecting SRAM
-- contents was another way for a step to test something other than
-- what its edge declared.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this step understands (issue #25).  run.sh
--   reads the marker line above and refuses, before the emulator boots and
--   naming both strings, any OT6_SRAM_CHECKPOINT whose manifest.json declares
--   a different persistent_layout.
--
-- Why this step is not an event walk.  The route recon flagged this as the
-- beat most likely to consume the generating pass, and the reason is that
-- `battle 73` appears nowhere in `event_main.asm`.  The ride is opcode `$ae`, `CUTSCENE::TRAIN`
-- (include/event_cmd.inc:707), issued at event_main.asm:96580; it runs in
-- the world module's train engine off a fixed 5-byte-per-item course
-- (world/train_script.asm:615-660), and the fights are issued by ASM
-- writing the event-battle id straight to $0011E0:
--     item 3  cmd $e0 -> TrainCmd_e0 (:829) -> event battle $29 = battle 41
--     item 9  cmd $e1 -> TrainCmd_e1 (:864) -> event battle $90 = battle 144
--     item 14 cmd $e0 -> battle 41
--     item 24 cmd $e1 -> battle 144
--     item 31 cmd $e1 -> battle 144
--     item 36 cmd $e2 -> TrainCmd_e2 (:899) -> event battle $49 = battle 73
--                        = NUMBER 128 $010b + Left Blade $0140 + RightBlade $013f
-- so nothing in the event disassembly names the boss and no entry point
-- fixture can be parked in front of it.  This step therefore records every
-- battle the ride produces: the driver below logs each formation on
-- its rising edge and the assertions afterwards are about that record,
-- requiring six fights seen and one of them $010b with both blades.  A ride
-- that fought nothing would fail rather than pass.
--
-- It also answers recon probe 4 (ride duration), which the recon could
-- only guess at because it never traced where the train counter $36 is
-- decremented: the frame count from `cutscene TRAIN` to control on map 240
-- is logged below.
--
-- ############################################################################
-- ## The block below is history.  It was resolved on 2026-07-27 (#21).      ##
-- ## Everything from "this generator does not generate" to "party: LOCKE    ##
-- ## alone" described a ride fought solo because the fixture chain walked   ##
-- ## out of Zozo with two characters.  Its own "what would unblock this"    ##
-- ## has happened: gen_zozo5_ramuh seats SABIN and EDGAR at the leave       ##
-- ## cutscene's party_menu, the whole chain and the tracked post-opera-v1   ##
-- ## checkpoint were regenerated from it, and minecart_entry now boots      ##
-- ## LOCKE + SABIN + EDGAR (measured: $1850 LOCKE=$51 EDGAR=$C1 SABIN=$49,  ##
-- ## CELES=$00 after the tube room).  The solo measurements below are kept  ##
-- ## verbatim as the record of the earlier failure; the assertions at the   ##
-- ## entry point now require three.                                         ##
-- ############################################################################
--
-- Run against minecart_entry it rides the cutscene correctly and fights
-- all six battles in the scripted order --
--
--   1  f1281  0006 2A2A ...           Mag Roader           (battle 41)
--   2  f2450  0006 0006 ...           Mag Roader x2        (battle 144)
--   3  f3474  0006 2A2A ...           Mag Roader           (battle 41)
--   4  f5170  0006 0006 ...           Mag Roader x2        (battle 144)
--   5  f6546  0006 0006 ...           Mag Roader x2        (battle 144)
--   6  f7514  010B 0140 292A 013F     NUMBER 128 + blades  (battle 73)
--
-- which confirms the recon's decode of train_script.asm's course.  LOCKE
-- then died in fight 6.  Measured (probe_train_tail.lua), his battle
-- HP $3BF4 at the start of each fight:
--
--   fight 1: 501   fight 4: 385   fight 5: 261   fight 6: 151   -> 0
--
-- i.e. he enters the ride at full HP and the five Mag Roader fights take
-- ~70 HP each even though every one of them is write-cleared within three
-- frames of `battleLoadStarted()`; the boss finishes what is left.  The
-- screenshot `shots/train_after6.png` is the sighting: Number 128, Left
-- Blade and RightBlade all standing, LOCKE alone on 151.
--
-- The cause was upstream, in v0.5, and was not a balance problem to fix
-- here.  The party was one character because the fixture chain walked out of
-- Zozo with two.  `event_main.asm:26287` is
--
--     char_party LOCKE, 1 / char_party CELES, 1
--     party_menu 1, NO_RESET, {LOCKE, CELES}
--
-- which is a four-slot party menu with Locke and Celes forced and the other
-- two slots free.  Measured at the post-Opera checkpoint, $1EDE=$76 /
-- $1EDF=$88, so CYAN, EDGAR, SABIN and GAU are all available to fill them;
-- but $1850 reads LOCKE=$C1, CELES=$49 and every other character $00, so
-- nobody was added.  After the tube room takes Celes (`char_party CELES,
-- 0`, :96154) that leaves ONE.  docs/design/bosses-wob.md §13-§16 ("Locke,
-- Celes + two") is describing the intended area; the fixture chain is what
-- is wrong.
--
-- What would unblock this.  The v0.5 step that answers that party_menu has
-- to pick two more characters, and everything from there down, including
-- the tracked 32 KiB checkpoint at tools/tests/checkpoints/post-opera-v1/,
-- which is generated from blackjack.mss by gen_post_opera_checkpoint.lua, has
-- to be regenerated.  That is a v0.5 change rather than a v0.6 one, so this
-- generator is left in the tree as the evidence rather than being made to
-- pass by weakening what it checks.
--
-- Party: LOCKE alone.  Step 11 measured $1850 after the tube room and found
-- one character with a nonzero party nibble, so every fight on this ride,
-- Number 128 included, is a solo fight.  Asserted at the entry point so the
-- balance work has a measurement to stand on rather than
-- docs/design/bosses-wob.md §15's "three".
local H = dofile("tools/tests/lib/ot6.lua")
-- The retry ladder's spread and its collision check (issue #83): each
-- attempt is held until the game-time frame counter the battle seed is
-- made of reaches its own phase, and L.report() fails if two attempts
-- drew one seed, which would make this ladder one fight played twice.
local L = H.newSeedLadder("minecart ride")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

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

-- (a tapInto helper used to sit here, defined and never called, the same
-- unused battle toolkit every conversion in this wave has deleted; its only
-- battle handling was the battle-clear write)

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


-- a bare step list cannot be spliced into a step list; H.cond with an
-- always-true predicate is the library's public way to wrap one into a step
local function seq(steps) return H.cond(function() return true end, steps) end

-- Ride the cutscene with real input (issue #75): every one of the six forced
-- battles is fought with the library fighter.  These are event battles
-- the train engine issues by writing $0011E0, the ride waits on each win,
-- and fleeing is not part of the design.  Each fight's formation words are
-- recorded on the rising edge, so the assertions afterwards are about what
-- was fought.  Outside battle the ride is fixed: edge-A pages
-- the text, and a held direction would only work against the engine.
--
-- The ride is wrapped in gen_tunnelarmr's phase-spread retry ladder: six
-- input-driven fights back to back with no field care between them can lose
-- a party on a bad roll, a loss is game over, and the
-- RNG seed is the frame phase at battle init.  A wipe is detected inside the
-- drive (the party's battle HP all zero, debounced) so the ladder can
-- reload instead of riding the Annihilated screen into a timeout.
-- Fight 6 uses explicit targeting, and the reason is measured rather than
-- assumed: on the first input-driven attempt the fighter's default targeting
-- attacked the blades for 8500 frames.  Left Blade read 515/sh1 and then
-- 700/sh3 again, so the blades regenerate, while the body sat untouched at
-- 3276/sh7 and the party ran out of HP.  The body's authored break axis is
-- piercing (bosses-wob.md 15, as re-decoded by #23: the bolt/water row was
-- never written, so the physical class is the shipped axis), which is EDGAR's
-- AutoCrossbow.  The override below steers every single-target confirm
-- onto the live $010B slot so the crossbow chips the 7 shields and everyone's
-- damage lands on the body.  Items still target the party
-- (the override skips char-side selects), and a 40-frame give-up keeps
-- an untargetable state from deadlocking a turn.
local fights, rideStart = {}, nil
local function rideDriver(pred, lostRef, maxFrames, what)
  local ph, hb, battN, wipeN, tgtSpin = 0, 0, 0, 0, 0
  -- Policy, revised twice, both times after measured losses.  Round one (run
  -- N0mLGnDD, ladder failing at fights 6/4/6): healPercent 60 reacted too
  -- late to the Mag Roaders' whole-party bursts, and bank=3 wasted BP,
  -- because a chip is per boosted hit, so three boost-1 swings out-chip one
  -- boost-3 swing.  Round two (run R0crCD3T): healPercent 75 fixed the
  -- Roader attrition (the party reached fight 6 at full HP) and
  -- then heal-locked the boss fight: under the boss and two blades
  -- someone is always below 75%%, EDGAR spent every turn on the bag, the
  -- body took one chip in 4900 frames on attempt 1 and none on attempt 2,
  -- and the fight stalled until the bag ran dry.  So the policy is split:
  -- the five Roader fights heal at 75%% (they end quickly, so the bag
  -- spend is small), and the boss fight drops to 55%% so EDGAR's turns go
  -- to the AutoCrossbow that breaks the body.
  local Ftrash = H.newFightDriver("n128 trash", { tactical = true,
    boost = true, bank = 1, items = true, healPercent = 75, cadence = 12 })
  local Fboss = H.newFightDriver("n128 boss", { tactical = true,
    boost = true, bank = 1, items = true, healPercent = 55, cadence = 12 })
  return H.driveUntil(function() return lostRef.lost or pred() end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 600 == 0 then
        local mhp = {}
        if H.battleLoadStarted() then
          for m = 0, 5 do
            local id = H.readWord(0x57C0 + m * 2)
            if id ~= 0xFFFF and id ~= 0 then
              mhp[#mhp + 1] = string.format("%04X:%d/sh%d", id,
                H.readWord(0x3BFC + m * 2), H.readByte(0x3E40 + m * 2))
            end
          end
        end
        H.log(string.format("ride f%d map=%d (%d,%d) ctl=%s batt=%s "
          .. "fights=%d party %d/%d/%d | %s", H.frame, map(),
          H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), #fights,
          H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8),
          table.concat(mhp, " ")))
      end
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN == 3 then
        local w = H.formationWords()
        fights[#fights + 1] = w
        H.log(string.format("[ride battle %d] f%d formation = "
          .. "%04X %04X %04X %04X %04X %04X", #fights, H.frame,
          w[1], w[2], w[3], w[4], w[5], w[6]))
      end
      if battN >= 3 then
        -- a wipe never sets $0069; catch it here so the ladder can act.
        -- Debounced 120 frames: the HP table can read zero for a moment
        -- while a battle deals the party in.
        local alive = false
        for e = 0, 3 do
          if H.readWord(0x3BF4 + e * 2) > 0 then alive = true end
        end
        wipeN = (not alive) and wipeN + 1 or 0
        if wipeN >= 120 and not lostRef.lost then
          lostRef.lost = true
          H.log(string.format("[ride] PARTY WIPED in fight %d at f%d",
            #fights, H.frame))
        end
        local F = (#fights >= 6) and Fboss or Ftrash
        F.frame()
        -- fight 6: steer single-target confirms onto the body (header)
        if #fights >= 6 and H.readByte(0x7BC2) == 0x38 then
          local mons = H.readByte(0x7B7E)
          if mons ~= 0 then
            local body = nil
            for m = 0, 5 do
              if H.readWord(0x57C0 + m * 2) == 0x010B
                 and H.readByte(0x3AA8 + m * 2) % 2 == 1 then body = m; break end
            end
            if body then
              local want = 1 << body
              if mons == want then
                tgtSpin = 0
                H.setPad(ph < 4 and { a = true } or {})
              else
                tgtSpin = tgtSpin + 1
                if tgtSpin < 40 then
                  local cur = 0
                  for m = 0, 5 do
                    if mons & (1 << m) ~= 0 then cur = m; break end
                  end
                  H.setPad(ph < 4
                    and { [cur < body and "down" or "up"] = true } or {})
                else
                  H.setPad(ph < 4 and { a = true } or {})
                end
              end
            end
          end
        else
          tgtSpin = 0
        end
        return
      end
      -- Out of battle: a wipe that outruns the in-battle debounce shows
      -- up as the Game Over Continue landing back on the boot save
      -- tile (272 {3,55}), measured on the first input-driven attempt,
      -- where the A-taps paged the Game Over and the battery Continue
      -- parked the party there with the ride's pred permanently false.
      if #fights > 0 and map() == 272
         and H.fieldX() == 3 and H.fieldY() == 55 and not lostRef.lost then
        lostRef.lost = true
        H.log(string.format("[ride] LOSS: the Game Over Continue landed on "
          .. "the boot save tile after fight %d, f%d", #fights, H.frame))
      end
      if battN > 0 then Ftrash.idle(); Fboss.idle(); H.setPad({}); return end
      Ftrash.idle(); Fboss.idle()
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, what)
end

local rideBlob, rideWon = nil, false

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Attempt 1 runs in place; later attempts
-- reload the prepared CID entry point and shift the RNG phase.  The outcome
-- is the ride's own terminator: control on map 240 with $0069 set.
local function rideAttempt(n)
  local loadReq
  local lostRef = { lost = false }
  return H.cond(function() return rideWon end, {}, {
    H.logStep(function()
      return string.format("minecart ride attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function()
        fights = {}                    -- a lost attempt's record is void
        loadReq = H.requestLoadState(rideBlob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "ride entry point reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 272, "reloaded onto map 272")
        H.assertEq(H.fieldX() == 9 and H.fieldY() == 52, true,
          "reloaded beside CID")
      end),
    }) or seq({}),
    L.spread(n),                        -- spread the battle RNG phase (#83)
    -- A into CID -> _cc8022 -> ... -> `cutscene TRAIN`
    (function() local ph = 0
      return H.driveUntil(function() return sw(0x02BC) == 1 end, 20000, {
        H.call(function() ph = (ph + 1) % 8
          if H.dialogWaiting() or not settled() then
            H.setPad(ph < 4 and { "a" } or {})
          else
            H.setPad(ph < 4 and { "a", "up" } or { "up" })
          end
        end) }, "A into CID -> $02BC -> cutscene TRAIN")
    end)(),
    H.call(function()
      rideStart = H.frame
      H.assertEq(sw(0x02BC), 1, "$02BC SET -- the minecart cutscene has begun")
      H.log(string.format("[ride] cutscene TRAIN entered at frame %d", H.frame))
      H.screenshot("minecart_ride")
    end),
    -- ride it out; terminates early on a detected wipe so the ladder can
    -- reload instead of timing out
    rideDriver(function()
      return map() == 240 and sw(0x0069) == 1 and settled()
    end, lostRef, 120000, "the minecart ride -> map 240 with $0069"),
    H.call(function()
      H.setPad({})
      if not lostRef.lost and map() == 240 and sw(0x0069) == 1 then
        rideWon = true
        H.log(string.format("minecart ride SURVIVED on attempt %d, f%d "
          .. "(%d fights fought)", n, H.frame, #fights))
      else
        H.log(string.format("attempt %d LOST (wipe in fight %d), f%d",
          n, #fights, H.frame))
      end
    end),
  })
end

H.run({ maxFrames = 400000 }, {
  -- checkpoint boot: cold Continue into the 272 save tile {3,55}, entry
  -- contract, then walk back beside CID and face him.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- Soft landing wait: a wrong-boundary checkpoint should fail via the entry
  -- contract naming the wrong map rather than via a timeout here.
  H.waitUntilSoft(function()
    return map() == 272 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_d"),
  H.waitFrames(60),
  H.call(function()
    -- The entry contract (issue #25): declared once in
    -- lib/ot6_contract.lua under "minecart-platform-v1", the same
    -- table gen_minecart_entry (the step into D) and the checkpoint
    -- generator assert as their exit contract.
    H.assertEntryContract("minecart-platform-v1")
    H.log(partyReport("minecart-platform-v1 entry"))
  end),
  H.navTo(9, 52, { maxFrames = 9000, playBattles = "flee" }),
  -- face CID: his object occupies (9,51), so an UP press only turns
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(map(), 272, "booted on map 272")
    H.assertEq(H.fieldX(), 9, "boot x")
    H.assertEq(H.fieldY(), 52, "boot y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "booted facing CID")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR at boot")
    H.assertEq(sw(0x0069), 0, "$0069 CLEAR at boot")
    -- Three characters, not one; see the history block at the top of this
    -- file.  They are named as well as counted, because the count alone
    -- would still pass if the chain swapped EDGAR for CYAN somewhere
    -- upstream.  This is also the owner rule for Number 128, recorded on
    -- #75: the boss is fought by LOCKE + EDGAR + SABIN, seated through the
    -- real party menu at the Zozo leave cutscene (gen_zozo5_ramuh) and
    -- carried here by the checkpoint.  No party menu exists at this step
    -- (the ride follows from talking to CID), so the roster verification is
    -- the only check available.
    local cur, n, who = H.readByte(0x1A6D), 0, {}
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == cur then n = n + 1; who[c] = true end
    end
    H.assertEq(n, 3, "the minecart is ridden by THREE characters")
    H.assertEq(who[0x01] == true, true, "and they are LOCKE...")
    H.assertEq(who[0x05] == true, true, "...SABIN (the bludgeon slot)...")
    H.assertEq(who[0x04] == true, true, "...and EDGAR (pierce + Tools)")
    H.log(partyReport("minecart_entry"))
  end),

  -- 1. the player's prep, all through real menus, before the retry blob:
  --    the July-cut checkpoint delivers the party bare-handed and possibly
  --    hurt (which every checkpoint-booted step in this wave has
  --    measured), and the ride is six fights with no field access between
  --    them
  H.equipOptimum({ tag = "n128 kit" }),
  H.fieldCare({ tag = "care before the ride", threshold = 0.95 }),
  H.navTo(9, 52, { maxFrames = 9000, playBattles = "flee" }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.fieldX() == 9 and H.fieldY() == 52, true,
      "back beside CID, prepared")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "facing CID again")
    H.log(partyReport("ride entry point, prepared"))
  end),
  -- capture the prepared entry point as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "ride retry blob")
        rideBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #rideBlob))
      end),
    })
  end)(),

  -- 2. the ride, on the phase-spread retry ladder
  L.watch(),
  rideAttempt(1),
  rideAttempt(2),
  rideAttempt(3),
  H.call(function()
    H.assertEq(rideWon, true,
      "the minecart ride survived within 3 attempts (six real "
      .. "fights, the library fighter)")
  end),
  -- ...and they were three DIFFERENT fights: distinct battle RNG seeds,
  -- read off the seeder itself (#83).  A win is only evidence about the
  -- encounter if the attempts that lost were not the same fight replayed.
  L.report(),
  H.waitFrames(90),

  H.call(function()
    H.log(string.format("[ride] control on map 240 at frame %d "
      .. "(%d frames from `cutscene TRAIN`), %d battles fought",
      H.frame, H.frame - rideStart, #fights))
    for i, w in ipairs(fights) do
      H.log(string.format("  fight %d: %04X %04X %04X %04X %04X %04X", i,
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    -- Positive controls.  A ride that fought nothing would reach
    -- map 240 the same way, so the record is what is asserted.
    H.assertEq(#fights >= 6, true,
      "the ride fought at least six battles (train_script.asm's six cmd bytes)")
    local sawN128 = false
    for _, w in ipairs(fights) do
      for _, v in ipairs(w) do if v == 0x010b then sawN128 = true end end
    end
    H.assertEq(sawN128, true,
      "NUMBER 128 $010b was fought -- the boss TrainCmd_e2 issues by writing "
      .. "$0011E0, which no grep of event_main.asm can find")
    H.assertEq(map(), 240, "the escape map is 240")
    H.assertEq(mapTitleHere(), "",
      "map 240 has no map title (map_prop byte 0 = 0) -- it is a second "
      .. "copy of VECTOR used for the escape")
    H.assertEq(sw(0x0069), 1, "$0069 SET -- 262 (28,9) now exits to 240, not 242")
    H.assertEq(sw(0x0666), 1, "$0666 SET")
    H.assertEq(sw(0x06AE), 1, "$06AE SET -- the save point on 240 (58,7) is revealed")
    H.assertEq(sw(0x006B), 0, "$006B CLEAR -- the Setzer reunion is still ahead")
    H.log(string.format("[after the ride] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("after the ride"))
    H.screenshot("n128_after_ride")
  end),

  -- 3. park on boundary E: the escape map's save point {58,7}, revealed by
  --    $06AE.  n128_won is the D->E terminal, so it is generated standing on
  --    the boundary tile with the vector-escape-v1 table asserted (the
  --    same table gen_vector_escape_checkpoint saves under).  Map 240 is an
  --    encounter map (rate $0070); navTo write-clears any draw on the walk.
  --    The last step is a held RIGHT from (57,7).  A save tile flickers
  --    hasControl() (the SavePoint re-entry), so arrival is judged on
  --    position, $01BF and alignment.
  H.navTo(57, 7, { maxFrames = 15000, playBattles = "flee" }),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.fieldX() == 58 and H.fieldY() == 7 and sw(0x01BF) == 1
              and H.tileAligned() and not H.dialogWaiting()
              and not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if H.dialogWaiting() then H.setPad({ "a" }); return end
        if H.fieldX() == 58 and H.fieldY() == 7 then H.setPad({}); return end
        H.setPad({ right = true })
      end),
    }, "onto the save tile 240 (58,7)")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the $06AE-revealed save point works")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertExitContractPreSave("vector-escape-v1")
    H.log(string.format("[n128_won] f%d map=%d (%d,%d) -- ON boundary E",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("n128_won"))
    H.screenshot("n128_won")
  end),
  H.saveState("n128_won.mss"),
  -- Reload-verified (gen_sabin_gau's pattern).  The party is parked on a
  -- save tile, where hasControl() flickers (the SavePoint re-entry), so
  -- the reload is judged the way the park itself was: position, latch and
  -- alignment, not the control flag.
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
        H.assertEq(map(), 240, "reload: still on map 240")
        H.assertEq(H.fieldX() == 58 and H.fieldY() == 7, true,
          "reload: still on the save tile")
        H.assertEq(H.tileAligned(), true, "reload: at rest on the tile")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(sw(0x0069), 1, "reload: $0069 still SET -- the win held")
        H.log("generated-state verify: the reload stayed calm -- n128_won verified")
      end),
    })
  end)(),
  H.call(function()
    census("n128_won", {
      { 58, 7, "the save point revealed by $06AE" },
      { 52, 40, "the Setzer reunion trigger _cc817f" },
    })
  end),
  H.logStep(function()
    return string.format("n128_won generated at frame %d -- map 240 (%d,%d), "
      .. "$0069=1 after %d fights on the minecart", H.frame,
      H.fieldX(), H.fieldY(), #fights)
  end),
})

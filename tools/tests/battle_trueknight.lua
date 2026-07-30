-- @suite slow
-- battle_trueknight.lua -- issue #37 (playtester @TimRahaim): a True Knight
-- cover pays the BLOCKER +1 BP, once per round, on the block frame.
--
--   tools/tests/run.sh tools/tests/battle_trueknight.lua
--
-- VANILLA'S COVER PATH (battle_main.asm):
--   CalcAttackEffect calls CoverEffect (:8325).  CoverEffect (:2855) drops out
--   unless the attack can crit ($b2.1 clear, :2859-2861), has targets (:2862),
--   and the target is NEAR FATAL and not vanished ($3ee4,y bits $0200 / $0010,
--   :2875-2879).  It then builds the candidate mask -- every character except
--   the target and the attacker (:2882-2889) -- and walks all ten entities
--   looking for the True Knight relic bit, $3c58,x & $0040 (:2891-2893).
--   Survivors of CheckCoverTarget (:2931: presence, control, seize and status
--   gates, keeping the HIGHEST-hp candidate in $f2/$f4) reach SetCoverTarget
--   (:2911), which COMMITS the cover: past its `bmi` (no candidate) and its
--   `cpy $f8 / bne` (the original target moved), $f8/$a8/$b8 are retargeted
--   onto the blocker (:2916-2922).  That commit IS the block, and it is where
--   OT6 hooks Ot6CoverBP -- the same shape as Ot6RunicBP at RunicEffect's
--   enrolment instruction.
--
-- THE FIXTURE IS LABELLED, NOT NATURAL.  Nobody in the doorstep party wears
-- True Knight, so the blocker's relic-effect word is STAGED: $3c58,slot |= $40,
-- the bit LoadCharProp would have written from the relic (:6868).  The rest of
-- the staging only makes covers HAPPEN often enough to measure:
--   - VICTIM: hp 10 against a 3000 max AND status-2 bit 1 written directly.
--     Vanilla only recomputes NEAR FATAL inside a status update (:11444-11452)
--     and the whole point of the fixture is that this victim never takes a hit
--     to trigger one, so the flag is pinned rather than inferred.  Stopped, so
--     his own menu never opens.
--   - ATTACKER: a MUDDLED ally with a Fight-only command list (battle_runic's
--     idiom) -- swings arrive on a character ATB rather than monster AI, and
--     roughly one in three lands on the near-fatal victim.  The monsters are
--     left alive and unstopped and contribute covers too.
--   - BLOCKER: never stopped (CheckCoverTarget rejects $3ef8,x & $3210, :2944,
--     so stopping him would delete the mechanic under test -- battle_runic's
--     lesson) and held off the turn order by his ATB byte instead ($3219,x),
--     except in phase 4 where taking a turn is the point.
--   MEASURED DEAD END, recorded so it is not re-tried: marking every character
--   but the victim un-targettable ($2f4c) to force every swing into a cover
--   FREEZES the action queue -- 20949 frames, ATB full on four entities, zero
--   CalcAttackEffect calls (probe_cover).  Cover frequency is bought with
--   patience here, not with $2f4c.
--
-- The cover DETECTOR is the ROM's own commit condition, evaluated at
-- SetCoverTarget's ENTRY out of CPU state: $f4 valid (not $ff) and Y still ==
-- $f8.  H.sym() resolves the entry from ff6-en.dbg per build, so the same
-- script reads the pre-change and post-change ROMs.
--
-- Asserted, in order, so a fixture failure never masquerades as a product one:
--   1. the cover really commits, onto OUR knight;
--   2. the bank rises by exactly 1, in the SAME FRAME as the commit;
--   3. the PIP is deferred to the damage frame (issue #42): NOT armed on the
--      commit frame any more, banked into OT6_PIPPEND there and committed onto
--      the live cell on the numeral-counter edge -- with the measured gap
--      between the two named in the log's frame table;
--   4. ONCE PER ROUND: further covers in the same round still redirect the hit
--      but bank nothing;
--   5. and the round boundary is REAL -- after the blocker takes his own turn
--      (Ot6ActionEnd), the next cover pays again.  Without 5, "once per round"
--      and "once per battle" would both pass 4;
--   6. a scheduled pip is always DELIVERED -- the property that makes #42's
--      miss ruling safe (a covered attack that misses still pays, so it must
--      still paint; see that arm for the ruling and its ROM grounding).
--
-- #42 measured the pre-change timing with this same instrument: the commit
-- preceded the numeral by 83-147 frames while OT6_PIPTAIL is 32, so the pip
-- flashed and faded about two seconds before the block visibly landed.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local TRUE_KNIGHT = 0x40          -- $3c58 bit 6 (relic effects 4)
local STOP, MUDDLE, MAGITEK = 0x10, 0x20, 0x08
local NEAR_FATAL = 0x02           -- status 2 bit 1
local PIP = { [0] = 0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

local function bp(s)    return H.readByte(0x3E9C + s * 2) end
local function pend(s)  return H.readByte(0x3E9D + s * 2) end
local function hp(s)    return H.readWord(0x3BF4 + s * 2) end
local function st2(s)   return H.readByte(0x3EE5 + s * 2) end
local function alive(s) return H.readByte(0x3AA0 + s * 2) % 2 == 1 end

local knight, victim, attacker = nil, nil, nil
local msPresent = {}
local holdKnight = true

-- ---------------------------------------------------------------- staging --
local function pinField()
  if not knight then return end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      H.writeWord(0x3C1C + s * 2, 3000)                            -- real max hp
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & ~MAGITEK & 0xFF)
      if s == attacker then
        H.writeWord(0x3BF4 + s * 2, 2000)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | MUDDLE)
        H.writeByte(0x202E + s * 12, 0x00)                         -- Fight, alone
        H.writeByte(0x2031 + s * 12, 0xFF)
        H.writeByte(0x2034 + s * 12, 0xFF)
        H.writeByte(0x2037 + s * 12, 0xFF)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == victim then
        H.writeWord(0x3BF4 + s * 2, 10)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | NEAR_FATAL)
        H.writeByte(0x3EF8 + s * 2, H.readByte(0x3EF8 + s * 2) | STOP)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == knight then
        H.writeWord(0x3BF4 + s * 2, 2000)                          -- survives covers
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) | TRUE_KNIGHT)                -- the staged relic
        H.writeByte(0x3EF8 + s * 2,
          H.readByte(0x3EF8 + s * 2) & ~STOP & 0xFF)               -- never stopped
        if holdKnight then H.writeByte(0x3219 + s * 2, 0x60) end
      else
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)        -- exactly one knight
      end
    end
  end
  for _, m in ipairs(msPresent) do
    if H.readWord(0x3BFC + m * 2) ~= 3000 then H.writeWord(0x3BFC + m * 2, 3000) end
    H.writeWord(0x3C24 + m * 2, 3000)
  end
end

-- ------------------------------------------------------------- instruments --
local covers = {}        -- { f = frame, blocker = entity } per COMMITTED cover
local bpWrites = {}      -- { f = frame, v = value } for the knight's bank

local function armCover()
  local addr = H.sym("SetCoverTarget")
  emu.addMemoryCallback(function()
    local f4, f8 = H.readByte(0x00F4), H.readByte(0x00F8)
    if f4 == 0xFF then return end                     -- the `bmi` bail
    if (emu.getState()["cpu.y"] & 0xFF) ~= f8 then return end   -- the `bne` bail
    covers[#covers + 1] = { f = H.frame, blocker = f4 }
  end, emu.callbackType.exec, addr, addr)
  H.log(string.format("cover detector armed at SetCoverTarget $%06X", addr))
end

-- lastBp is sampled at every frame START, so a write recorded during the frame
-- carries the value the bank held going into it: an earn is v == prev + 1 no
-- matter what the absolute bank happens to be.
local lastBp = nil
local function armBank()
  emu.addMemoryCallback(function(_, v)
    bpWrites[#bpWrites + 1] = { f = H.frame, v = v, prev = lastBp }
  end, emu.callbackType.write, 0x7E3E9C + knight * 2, 0x7E3E9C + knight * 2)
end

-- ------------------------------------------------------- #42 instruments --
-- The three OT6 cells the deferral moves through (ot6_memory.inc):
--   OT6_PIPTAIL $57bb   frames of live pip painting left; a write of 32 IS an
--                       arm (Ot6ActionEnd and Ot6PipPending are its only ones)
--   OT6_PIPSLOT $ed6b   the slot that cell follows -- written just BEFORE the
--                       tail by both armers, so reading it in the tail's
--                       callback names who was armed
--   OT6_PIPPEND $ed74   #42's own deferral cell: blocker slot + 1 at the cover
--                       commit, back to 0 when the paint is delivered
local PIPTAIL, PIPSLOT, PIPPEND = 0x57BB, 0xED6B, 0xED74
local NUMCTR_SRC = 0x632E         -- the damage-numeral thread counter itself

local pipArms = {}    -- { f = frame, slot = who } per OT6_PIPTAIL arm
local pendWrites = {} -- { f = frame, v = value } per OT6_PIPPEND write
local numerals = {}   -- frames on which $632e changed -- the damage frames

-- THE NUMERAL SUPPRESSOR (arm 6b).  Ot6RevealPoll fires on a CHANGE in $632e
-- against its last-seen copy OT6_NUMCTR ($ed71); mirroring every write to
-- $632e straight into that copy means the poll never sees an edge, so the
-- numeral path is switched off deterministically and only Ot6ActionEnd's
-- backstop can deliver a pending pip.  This is how the numeral-LESS action --
-- the one real hole in "a scheduled pip is always delivered" -- gets exercised
-- without needing a script that happens not to draw a number.
local NUMCTR_SHADOW = 0xED71
local numSuppress = false

local function armPip()
  emu.addMemoryCallback(function(_, v)
    if numSuppress then H.writeByte(NUMCTR_SHADOW, v) end
  end, emu.callbackType.write, 0x7E0000 + NUMCTR_SRC, 0x7E0000 + NUMCTR_SRC)
  emu.addMemoryCallback(function(_, v)
    if v == 32 then
      pipArms[#pipArms + 1] = { f = H.frame, slot = H.readByte(PIPSLOT) }
    end
  end, emu.callbackType.write, 0x7E0000 + PIPTAIL, 0x7E0000 + PIPTAIL)
  emu.addMemoryCallback(function(_, v)
    pendWrites[#pendWrites + 1] = { f = H.frame, v = v }
  end, emu.callbackType.write, 0x7E0000 + PIPPEND, 0x7E0000 + PIPPEND)
end

-- The numeral EDGE, sampled the way Ot6RevealPoll sees it: once per frame,
-- from the main loop.  GfxCmd_0b's last act is `inc w7e632e`
-- (btlgfx_main.asm:24799) -- and the MISS arm reaches that same tail
-- (:24725-24735 `bra @a589`), so a missed attack raises this counter exactly
-- like a damaging one.  That is why #42's ruling is that a missed cover still
-- paints its pip, and why it needs no separate path to do so.
local lastNum = nil
local function sampleNumeral()
  local n = H.readByte(NUMCTR_SRC)
  if lastNum ~= nil and n ~= lastNum then numerals[#numerals + 1] = H.frame end
  lastNum = n
end

local function firstAtOrAfter(list, f)
  for _, x in ipairs(list) do if x >= f then return x end end
  return nil
end
local function armsFor(slot, f0, f1)
  local t = {}
  for _, a in ipairs(pipArms) do
    if a.slot == slot and a.f >= f0 and a.f <= f1 then t[#t + 1] = a.f end
  end
  return t
end

-- the blocker's party-window pip cell (both bands), battle_clockwork's reader
local function pipCells()
  local reg = H.readByte(0x897F)
  local base = ((reg - (reg % 4)) * 256) * 2
  local row
  for r = 0, 3 do if H.readByte(0x64D6 + r) == knight then row = r end end
  if not row then return nil end
  return emu.readWord(base + (1 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam),
         emu.readWord(base + (9 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam)
end

local watchGlyph, glyphFirstF, glyphMenu = nil, nil, nil
local function sample()
  pinField()
  sampleNumeral()
  if knight then lastBp = bp(knight) end
  if watchGlyph and not glyphFirstF then
    local lo, hi = pipCells()
    if lo and ((lo & 0xFF) == watchGlyph or (hi & 0xFF) == watchGlyph) then
      glyphFirstF = H.frame
      -- WHOSE paint was it?  With a battle menu open the party window stages
      -- every row's TRUE bank (Ot6PipGlyph_ext), which is correct and is not
      -- the live cell #42 governs -- so the glyph is corroboration, and the
      -- deferral is asserted on OT6_PIPPEND / OT6_PIPTAIL instead.
      glyphMenu = H.readByte(MENU) ~= 0
    end
  end
end

-- SERVICE FOREIGN MENUS: a ready character's open menu parks the whole action
-- queue (battle_runic's measurement).  Never the knight's own, except when
-- phase 4 wants his turn.
local serviceKnight = false
local function service()
  if H.readByte(MENU) ~= 0
     and (serviceKnight or H.readByte(ACTOR) ~= knight) then
    H.setPad({ "a" })
  else
    H.setPad({})
  end
end
local DRIVE = {
  H.call(service), H.waitFrames(4),
  H.call(function() H.setPad({}) end), H.waitFrames(13),
}

local function coversSince(n) return #covers - n end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),

  -- --------------------------------------------------------------- install --
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    H.assertEq(#msPresent > 0, true, "monsters on the field")
    local live = {}
    for s = 0, 3 do if alive(s) and hp(s) > 0 then live[#live + 1] = s end end
    H.assertEq(#live >= 3, true, "three live characters (attacker/victim/knight)")
    attacker, victim, knight = live[1], live[2], live[3]
    H.log(string.format("attacker=slot %d (muddled) victim=slot %d (near fatal) "
      .. "knight=slot %d (staged True Knight); %d monsters",
      attacker, victim, knight, #msPresent))
    pinField()
    armCover()
    armBank()
    armPip()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
  end),
  H.waitFrames(120),
  H.call(function()
    -- the fixture's own preconditions, named before anything leans on them
    H.assertEq(st2(victim) & NEAR_FATAL, NEAR_FATAL,
      "the victim is NEAR FATAL (the gate CoverEffect reads at :2875)")
    H.assertEq(H.readByte(0x3C58 + knight * 2) & TRUE_KNIGHT, TRUE_KNIGHT,
      "the blocker carries the True Knight relic bit ($3c58.6)")
    H.assertEq(H.readByte(0x3EF8 + knight * 2) & STOP, 0,
      "and is NOT stopped (CheckCoverTarget would drop him)")
    H.assertEq(H.readByte(0x3C58 + attacker * 2) & TRUE_KNIGHT, 0,
      "and he is the ONLY True Knight on the field")
    H.assertEq(H.readByte(PIPPEND), 0,
      "no deferred pip is pending before the first cover (InitBP cleared it)")
    H.writeByte(0x3E9C + knight * 2, 1)          -- a bank with room to grow
    H.writeByte(0x3E9D + knight * 2, 0)
    covers, bpWrites = {}, {}
    pipArms, pendWrites, numerals = {}, {}, {}
    watchGlyph = PIP[2]                          -- the glyph a +1 must produce
  end),

  -- ------------------------------------ 1/2/3. the first cover of a round --
  H.driveUntil(function() return #covers > 0 end, 24000, DRIVE,
    "a True Knight cover commits"),
  -- #42: the damage numeral for that hit is 83-147 frames further on, so the
  -- old flat 60-frame settle would now sample before the pip paints.  Drive to
  -- the numeral edge itself and then let the vram flush land.
  H.call(function() H.vars.cf = covers[1].f end),
  H.driveUntil(function() return firstAtOrAfter(numerals, H.vars.cf) ~= nil end,
    1200, DRIVE, "the damage numeral that follows the covered hit"),
  H.waitFrames(60),                              -- let the vram flush land
  H.call(function()
    local c = covers[1]
    H.log(string.format("first cover at f%d, blocker entity $%02x (knight is $%02x); "
      .. "bank writes: %s", c.f, c.blocker, knight * 2,
      (function() local t = {} for _, w in ipairs(bpWrites) do
        t[#t + 1] = string.format("f%d=%d", w.f, w.v) end
        return table.concat(t, " ") end)()))
    H.assertEq(c.blocker, knight * 2,
      "the cover committed onto OUR knight (the only True Knight on the field)")
    -- 2. the bank
    H.assertEq(bp(knight), 2, "the cover banked exactly +1 bp")
    H.assertEq(pend(knight), 0, "with nothing pending to spend")
    H.assertEq(#bpWrites, 1, "exactly one bank write")
    H.assertEq(bpWrites[1].f, c.f,
      "and it lands on the COMMIT frame -- the block frame, not near it")
    -- 3. THE PIP, DEFERRED TO THE DAMAGE FRAME (#42).
    --
    -- #37 armed OT6_PIPSLOT/OT6_PIPTAIL inside Ot6CoverBP, on the commit
    -- instruction itself.  Measured here, that commit precedes the damage
    -- numeral by 83-147 frames while the tail is 32 -- so the pip flashed and
    -- faded roughly two seconds BEFORE the block visibly landed.  The bank
    -- stays on the commit (asserted just above, unchanged); only the PAINT
    -- moves, banked into OT6_PIPPEND and committed off the numeral-counter
    -- edge by Ot6PipPending, the same shape Ot6RevealCommit/Ot6RevealPoll use.
    --
    -- The measurement is on the MECHANISM cells, not on the screen glyph: with
    -- a battle menu open the party window paints every row's true bank anyway
    -- (Ot6PipGlyph_ext), which is correct behaviour and not the live cell this
    -- issue governs.  So the glyph is logged as corroboration and the frames
    -- are asserted on OT6_PIPPEND / OT6_PIPTAIL.
    local nf = firstAtOrAfter(numerals, c.f)
    H.assertEq(nf ~= nil, true, "a damage numeral followed the covered hit")
    H.log(string.format(
      "FRAME TABLE: commit f%d | numeral f%d (+%d) | knight pip arms %s | "
      .. "glyph f%s | PIPPEND writes %s",
      c.f, nf, nf - c.f,
      "{" .. table.concat(armsFor(knight, c.f, nf + 30), ",") .. "}",
      tostring(glyphFirstF),
      (function() local t = {} for _, w in ipairs(pendWrites) do
        t[#t + 1] = string.format("f%d=%d", w.f, w.v) end
        return "{" .. table.concat(t, ",") .. "}" end)()))

    -- the deferral cell: armed on the COMMIT frame, consumed on the NUMERAL
    -- frame.  Both halves named, so a regression in either direction shows.
    H.assertEq(pendWrites[1] ~= nil and pendWrites[1].f == c.f, true,
      "OT6_PIPPEND is banked on the commit frame")
    H.assertEq(pendWrites[1].v, knight + 1,
      "and it holds the BLOCKER's slot + 1 (0 means nothing pending)")
    local cleared = nil
    for _, w in ipairs(pendWrites) do
      if w.v == 0 and w.f >= c.f then cleared = w.f; break end
    end
    H.assertEq(cleared, nf,
      "and it is consumed on the numeral frame, not before")

    -- THE REGRESSION #42 EXISTS FOR: no live-cell arm for the knight on the
    -- commit frame.  Before the fix there was exactly one, right there.
    H.assertEq(#armsFor(knight, c.f, c.f), 0,
      "the pip is NOT armed on the commit frame any more (it was, and faded "
      .. "83-147 frames before the hit landed)")
    H.assertEq(#armsFor(knight, nf, nf) >= 1, true,
      string.format("it is armed on the numeral frame f%d -- the frame the "
        .. "player sees the blow land on the blocker", nf))
    H.assertEq(nf - c.f > 32, true,
      string.format("and the gap the deferral closes is real: %d frames, "
        .. "against an OT6_PIPTAIL of 32", nf - c.f))

    H.assertEq(glyphFirstF ~= nil, true,
      "the party-window pip cell showed the new bank")
    H.log(string.format("pip glyph $%02x first seen at f%s (commit f%d, "
      .. "numeral f%d), battle menu %s at that frame -- an OPEN menu stages "
      .. "the true bank on every row and is not the live cell #42 defers",
      watchGlyph, tostring(glyphFirstF), c.f, nf,
      glyphMenu and "OPEN" or "closed"))
    H.screenshot("trueknight_covered")
  end),

  -- --------------------------------------------- 4. the once-per-round cap --
  H.call(function() H.vars.mark = #covers; H.vars.coversF0 = H.frame end),
  H.driveUntil(function() return coversSince(H.vars.mark) >= 2 end, 30000, DRIVE,
    "two more covers in the same round (the knight never acted)"),
  H.call(function()
    H.log(string.format("covers so far: %d; bank %d; bank writes %d",
      #covers, bp(knight), #bpWrites))
    H.assertEq(bp(knight), 2,
      "further covers in the SAME round protect but bank nothing (the cap)")
    H.assertEq(#bpWrites, 1,
      "and the bank was written exactly once across the whole round")

    -- 4b. THE FRAME-BUDGET CANARY, now asserted in its own words (#67).
    --
    -- This span is the fixture's most sensitive frame-budget probe, and it
    -- used to be measured only BY ACCIDENT: nothing asserted it, but a shift
    -- moved where phase 6a's hand-staged pip landed, so 6a failed instead --
    -- reporting a True Knight regression for what was a performance
    -- regression somewhere else entirely.  That made 6a a veto on bank $C2
    -- and cost a reverted feature (8d8a570) plus the investigation behind
    -- issue #67.  The measurement was always worth keeping; only the thing
    -- it was attached to was wrong.
    --
    -- WHAT MOVES IT: the battle main loop's per-iteration budget is close
    -- enough to full that a hair over makes WaitVblank miss and the whole
    -- iteration costs an extra hardware frame (ot6_memory.inc:206-230).  The
    -- penalty SATURATES -- 20 cycles and 110 cycles both cost exactly 163
    -- frames -- so this quantity is bimodal, not continuous:
    --
    --     budget intact ............................ 1635   (measured, four
    --                                                        separate builds)
    --     any overrun, however small ............... 1798   (= 1635 + 163)
    --
    -- The threshold therefore sits in an EMPTY region 163 frames wide, which
    -- is why it is a threshold and not a fudge factor.  1715 leaves 80 frames
    -- of headroom for legitimate drift below and still lands 83 frames clear
    -- of the cliff.  It is deliberately NOT an equality on 1635: this must
    -- survive a few bytes of honest growth off the per-battle-frame path (the
    -- v0.9 merge added ~49 bytes of $C2 at four per-action sites and this span
    -- did not move at all), and it must NOT survive a real overrun.
    --
    -- WATCHED TO FAIL, 2026-07-30, on the v0.9 ROM:
    --   80 bare NOPs before the OT6_BRKLIVE gate in Ot6BgHud_ext
    --   (ot6_hud.asm:221, the once-per-battle-frame site) -> 1798, and the
    --   hand-staged pip in 6a then lands at f4512 via the backstop -- the
    --   exact frame issue #67 records for every failing build.  So the
    --   mechanism here is the same one, caught by the right assertion now.
    --
    -- WHAT NO LONGER REPRODUCES, which matters for whoever reads #67 next:
    --   five bare NOPs in the $C2 ACTION path (immediately before
    --   `jsr CheckRetal` in _dispatcher, battle_main.asm:3146) -- #67's
    --   headline control -- came back 1635, PASS, with every frame number in
    --   the run byte-identical to the unmodified build.  That control was
    --   real when it was taken (8d8a570), but it does not reproduce on v0.9.
    --   It is the same direction as the correction comment on #67: the ~49
    --   bytes v0.9 added at per-action sites were free too.  Per-ACTION
    --   cycles are no longer near the cliff; per-battle-FRAME cycles still
    --   are.  Which is the rule this canary now states outright.
    H.vars.coversSpan = H.frame - H.vars.coversF0
    H.log(string.format("frame-budget canary: the covers phase took %d frames "
      .. "(intact 1635, missed-vblank cliff 1798, threshold 1715)",
      H.vars.coversSpan))
    H.assertEq(H.vars.coversSpan < 1715, true, string.format(
      "FRAME BUDGET: this phase took %d frames against ~1635 for an intact "
      .. "budget.  1798 = 1635 + 163 is the exact saturating cost of ONE "
      .. "missed vblank per battle-loop iteration (ot6_memory.inc:206-230), "
      .. "so cycles were added to a path that runs once per battle frame. "
      .. "This is NOT a True Knight failure -- nothing about covers, banks or "
      .. "pips has changed.  Look at what your change costs ONCE PER BATTLE "
      .. "FRAME (WaitFrame -> UpdateCharText -> Ot6BgHud_ext, "
      .. "btlgfx_main.asm:432-445), not at this test.  Per-action and "
      .. "per-menu-redraw cost does not move this number; measured on v0.9, "
      .. "80 NOPs in the per-frame path do and 5 NOPs in the $C2 action path "
      .. "do not (issue #67).",
      H.vars.coversSpan))
  end),

  -- ------------------------------------------ 5. the round boundary is real --
  H.call(function()
    holdKnight = false
    serviceKnight = true
    H.vars.acted = false
  end),
  H.driveUntil(function()
    -- his action goes live in $32cc (battle_main.asm:254: $ff = nothing queued)
    if H.readByte(0x32CC + knight * 2) ~= 0xFF then H.vars.acted = true end
    return H.vars.acted and H.readByte(0x32CC + knight * 2) == 0xFF
  end, 20000, DRIVE, "the blocker takes his own turn and it resolves"),
  H.waitFrames(150),
  H.call(function()
    holdKnight = true
    serviceKnight = false
    H.writeByte(0x3E9C + knight * 2, 1)          -- re-baseline the bank
    H.writeByte(0x3E9D + knight * 2, 0)
    H.vars.mark2 = #covers
    bpWrites = {}
    H.log("the blocker took a turn (Ot6ActionEnd ran); bank re-baselined to 1")
  end),
  H.driveUntil(function() return coversSince(H.vars.mark2) >= 1 end, 30000, DRIVE,
    "a cover in the NEXT round"),
  H.waitFrames(30),
  H.call(function()
    local c = covers[H.vars.mark2 + 1]
    H.log(string.format("next-round cover at f%d; bank %d; writes since the turn: %s",
      c.f, bp(knight),
      (function() local t = {} for _, w in ipairs(bpWrites) do
        t[#t + 1] = string.format("f%d:%s->%d", w.f, tostring(w.prev), w.v) end
        return table.concat(t, " ") end)()))
    -- assert on the WRITE, not the absolute bank: the blocker's own turn also
    -- pays him a regen tick, and a settle long enough to guarantee that landed
    -- first would be a timing bet.  prev+1 on the commit frame is the earn.
    local w = nil
    for _, x in ipairs(bpWrites) do if x.f == c.f then w = x end end
    H.assertEq(w ~= nil, true,
      "the earn re-arms at the blocker's own turn end -- a bank write lands on "
      .. "the NEXT round's commit frame (once per ROUND, not once per battle)")
    H.assertEq(w.v, (w.prev or -99) + 1,
      "and it is exactly +1 on that frame")
    H.screenshot("trueknight_next_round")
  end),

  -- ------------------------ 6. A SCHEDULED PIP IS ALWAYS DELIVERED (#42) --
  -- THE MISS RULING.  A cover whose attack then MISSES still pays the BP --
  -- the earn is banked at SetCoverTarget's commit, which is upstream of any
  -- hit roll, and that is deliberate: the knight stepped in front of his ally
  -- whether or not the blow connected.  So the pip must paint too; suppressing
  -- it would leave a silent +1 BP, which is a worse desync than the early pip
  -- #42 removes -- invisible rather than merely mistimed.
  --
  -- It needs no separate path.  FF6 draws "Miss" through GfxCmd_0b: the miss
  -- arm copies the glyph and branches into the very tail that increments the
  -- numeral counter (btlgfx_main.asm:24725-24735 -> :24799).  So a missed
  -- attack raises the counter exactly like a damaging one, and the deferred
  -- pip lands on the frame the word "Miss" appears over the blocker.
  --
  -- What CAN strand a pending paint is an action that issues no numeral at all
  -- (or a $ffff "hide numerals" one, :24707-24710), so Ot6ActionEnd flushes it
  -- for the same reason it flushes pending reveals.  This arm asserts the
  -- resulting property directly, on a hand-staged pending value: whatever the
  -- attack did, a scheduled pip is DELIVERED -- OT6_PIPPEND returns to 0 and
  -- the live cell is armed on the blocker.  The log names which path paid it.
  -- First let the round-5 cover's OWN deferred pip land -- which is itself the
  -- assertion that a real cover's pending value never stalls: arm 5 checked
  -- the bank 30 frames after the commit, and the numeral is ~85 frames out.
  H.driveUntil(function() return H.readByte(PIPPEND) == 0 end, 6000, DRIVE,
    "the next-round cover's deferred pip is delivered too"),
  H.call(function()
    H.vars.pipMark = #pipArms
    H.vars.stagedF = H.frame
    H.writeByte(PIPTAIL, 0)                      -- no live tail to confuse it
    H.writeByte(PIPPEND, knight + 1)             -- a paint owed to the knight
    H.log("staged a pending pip for the knight with no live tail")
  end),
  H.driveUntil(function() return H.readByte(PIPPEND) == 0 end, 6000, DRIVE,
    "the pending pip is delivered (numeral frame, or Ot6ActionEnd's backstop)"),
  H.call(function()
    local arms = armsFor(knight, H.vars.stagedF, H.frame)
    H.assertEq(#arms >= 1, true,
      "delivering the pending paint ARMED the live cell on the blocker -- a "
      .. "scheduled pip is never dropped, hit or miss")
    local at = arms[#arms]
    local viaNumeral = false
    for _, n in ipairs(numerals) do if n == at then viaNumeral = true end end
    H.assertEq(H.readByte(PIPSLOT), knight,
      "and the live cell points at the blocker")
    H.assertEq(H.readByte(PIPPEND), 0, "with nothing left pending")
    H.log(string.format("6a: delivered at f%d (staged f%d, +%d) via %s",
      at, H.vars.stagedF, at - H.vars.stagedF,
      viaNumeral and "the numeral frame (the damage/'Miss' path)"
                  or "Ot6ActionEnd's backstop (a numeral-less action)"))
    -- WHICH of the two paths pays a HAND-STAGED pip is not a property of the
    -- feature (#67).  This pip is written straight into OT6_PIPPEND at an
    -- arbitrary moment in the action cycle, so whether the next numeral edge
    -- or Ot6ActionEnd reaches it first depends on where in that cycle the
    -- staging happened -- which any shift in battle timing moves.  Asserting
    -- `viaNumeral` here therefore asserted the frame budget, in the wrong
    -- words: it failed as "the pip landed via the backstop" for changes that
    -- had nothing to do with pips, and vetoed a whole bank (8d8a570).
    --
    -- The property it was meant to protect -- the paint lands on the frame
    -- the player sees the blow -- is asserted where it is actually a
    -- property, on a REAL cover in phase 3 above: OT6_PIPPEND is consumed on
    -- the numeral frame (`cleared == nf`) and the live cell is armed on it
    -- (`#armsFor(knight, nf, nf) >= 1`).  Both are computed against the
    -- OBSERVED numeral frame rather than an absolute one, so they hold
    -- whatever the battle's frame count is.  Nothing is lost by dropping the
    -- duplicate here, and the frame-budget canary it was standing in for now
    -- lives in phase 4b, where it says what it means.
    --
    -- In its place, the path-INDEPENDENT half of what viaNumeral was reaching
    -- for, which is the half with teeth: whichever path pays the pip, the
    -- pending byte must be cleared ON the very frame the live cell is armed.
    -- The clear and the paint are one event or they are a bug -- a clear
    -- without an arm is exactly the "silent +1 BP" this phase's header calls
    -- a worse desync than a mistimed pip, because it is invisible rather than
    -- merely early.  Nothing here refers to an absolute frame, so a shift in
    -- battle timing moves both sides together and the assertion stands.
    local clearedAt = nil
    for _, w in ipairs(pendWrites) do
      if w.v == 0 and w.f >= H.vars.stagedF then clearedAt = w.f; break end
    end
    H.assertEq(clearedAt, at,
      "6a: OT6_PIPPEND is consumed on the very frame the live cell is armed "
      .. "-- the paint spent it, nothing else cleared it (a clear with no arm "
      .. "is a BP that was earned and never shown)")
  end),

  -- 6b. THE BACKSTOP, ISOLATED.  Switch the numeral trigger off (see the
  -- suppressor above) and stage another pending paint: now nothing but
  -- Ot6ActionEnd can deliver it, which is the numeral-less action -- the only
  -- way a scheduled pip could otherwise be stranded past the action that
  -- banked it.  Without this arm the backstop is code nothing ever runs.
  H.call(function()
    numSuppress = true
    H.writeByte(NUMCTR_SHADOW, H.readByte(NUMCTR_SRC))
    H.vars.pipMark2 = #pipArms
    H.vars.stagedF2 = H.frame
    H.writeByte(PIPTAIL, 0)
    H.writeByte(PIPPEND, knight + 1)
    H.log("numeral trigger suppressed; staged a second pending pip")
  end),
  H.driveUntil(function() return H.readByte(PIPPEND) == 0 end, 6000, DRIVE,
    "the pending pip is delivered with the numeral path switched off"),
  H.call(function()
    local at = H.frame
    local arms = armsFor(knight, H.vars.stagedF2, at)
    H.assertEq(#arms >= 1, true,
      "6b: Ot6ActionEnd's backstop armed the live cell on the blocker")
    for _, n in ipairs(numerals) do
      H.assertEq(n >= H.vars.stagedF2 and n <= at, false,
        "6b: no numeral edge reached the poll while it was suppressed")
    end
    H.assertEq(H.readByte(PIPSLOT), knight, "6b: pointing at the blocker")
    H.log(string.format("6b: backstop delivered at f%d (staged f%d, +%d) -- a "
      .. "pending paint never outlives the action that banked it",
      arms[#arms], H.vars.stagedF2, arms[#arms] - H.vars.stagedF2))
    numSuppress = false
  end),

  H.logStep(function()
    return string.format("battle_trueknight complete (%d committed covers)", #covers)
  end),
})

-- @suite slow
-- battle_trueknight.lua -- a True Knight cover pays the BLOCKER +1 BP,
-- once per round, on the block frame.

-- CoverEffect fires when the attack can crit, has targets, and the target is
-- near fatal and not vanished. It scans every character except the target
-- and the attacker for the True Knight relic bit ($3c58 bit 6), and
-- SetCoverTarget commits the cover, retargeting $f8, $a8 and $b8 onto the
-- blocker; that commit is where Ot6CoverBP hooks in.

-- The cover detector reads the ROM's own commit condition at SetCoverTarget's
-- entry: $f4 valid (not $ff) and Y still equal to $f8.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

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

-- lastBp is sampled at every frame start, so a write recorded during the frame
-- carries the value the bank held going into it: an earn is v == prev + 1
-- whatever the absolute bank happens to be.
local lastBp = nil
local function armBank()
  emu.addMemoryCallback(function(_, v)
    bpWrites[#bpWrites + 1] = { f = H.frame, v = v, prev = lastBp }
  end, emu.callbackType.write, 0x7E3E9C + knight * 2, 0x7E3E9C + knight * 2)
end

local PIPTAIL, PIPSLOT, PIPPEND = 0x57BB, 0xED6B, 0xED74
local COVERPAID = 0xED72         -- the once-per-round cover-earn flag
local NUMCTR_SRC = 0x632E         -- the damage-numeral thread counter itself

local pipArms = {}    -- { f = frame, slot = who } per OT6_PIPTAIL arm
local pendWrites = {} -- { f = frame, v = value } per OT6_PIPPEND write
local numerals = {}   -- frames on which $632e changed -- the damage frames

-- The numeral suppressor (arm 6b). Ot6RevealPoll fires on a change in $632e
-- against its last-seen copy OT6_NUMCTR ($ed71); mirroring every write to
-- $632e straight into that copy means the poll never sees an edge, so the
-- numeral path is switched off and only Ot6ActionEnd's backstop can deliver
-- a pending pip.
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

-- ------------------------------------------------- the frame budget (#236) --
-- WaitVblank (btlgfx_code) is `inc $47 / spin until the NMI clears it`, so
-- every call returns ON an NMI: consecutive calls sit exactly one hardware
-- frame apart while the battle loop fits its per-iteration budget, and two
-- apart when the work between them ran past vblank and had to wait for the
-- next one.  So the interval between calls, in frames, is the observation,
-- and an interval of 2 IS a dropped vblank rather than a proxy for one.
--
-- A battle is not only its loop -- a scene transition or a long animation
-- leaves it for several frames at a time -- so intervals longer than
-- VBLANK_GAP_MAX are not the loop running slowly, they are the loop not
-- running, and they are counted separately instead of being read as a
-- budget failure.  On an intact build they are a fixed handful (gaps of 7
-- and 8, six of each) and they do not move under a per-frame cost, which is
-- what makes them safe to exclude.
--
-- Measured (build/lab/canary/, probe_vblank.lua plus the poison*.sfc builds
-- it was calibrated against -- a delay loop of known length on the
-- per-battle-frame path, right after BtlGfx_01's own WaitVblank):
--
--   build            delay/iteration   loop intervals > 1 frame
--   intact                        0    ~1%
--   + ~10k cycles            ~10000    ~1%      (still fits the budget)
--   + ~20k cycles            ~20000    ~30%
--   + ~41k cycles            ~41000    ~40%
--
-- So the honest headline is that this loop's real headroom is THOUSANDS of
-- cycles per iteration, not the ~160 the old span-based canary implied, and
-- the separation between fitting and not fitting is a factor of thirty.
-- VBLANK_MAX sits in the middle of that gap: it cannot be reached by
-- scheduling and cannot be passed by a real per-frame overrun.
local VBLANK_BASE    = 1.0              -- % of loop intervals > 1, intact
local VBLANK_MAX     = 5.0              -- % that means a real overrun
local VBLANK_GAP_MAX = 4                -- frames: longer is "not in the loop"
local VBLANK_MIN_N   = 300              -- intervals needed for a verdict
local vblank = { on = false, last = nil, gaps = {}, loop = 0, missed = 0,
                 away = 0 }

local function armVblank()
  local wv = H.sym("WaitVblank@btlgfx_code")
  emu.addMemoryCallback(function()
    if not vblank.on then return end
    if vblank.last ~= nil then
      local g = H.frame - vblank.last
      vblank.gaps[g] = (vblank.gaps[g] or 0) + 1
      if g > VBLANK_GAP_MAX then
        vblank.away = vblank.away + 1
      else
        vblank.loop = vblank.loop + 1
        if g > 1 then vblank.missed = vblank.missed + 1 end
      end
    end
    vblank.last = H.frame
  end, emu.callbackType.exec, wv, wv)
end

local function vblankHist()
  local keys = {}
  for g in pairs(vblank.gaps) do keys[#keys + 1] = g end
  table.sort(keys)
  local t = {}
  for _, g in ipairs(keys) do t[#t + 1] = g .. ":" .. vblank.gaps[g] end
  return table.concat(t, " ")
end

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

-- the blocker's party-window pip cell (both bands)
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
      glyphMenu = H.readByte(MENU) ~= 0
    end
  end
end

-- Service other characters' menus: a ready character's open menu parks the
-- whole action queue. Never the knight's own, except when phase 4 wants his
-- turn.
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
  -- InitBP's own property, checked on the first frame the battle is live and
  -- NOT 360 frames later: by then a cover of the fight's own may legitimately
  -- have armed a pending pip, which is what this assertion used to read as a
  -- stale one.  It failed that way at 4 of 8 seed shifts on builds either
  -- side of #236 (build/sweeps/trueknight/), so it was measuring the fight.
  H.call(function()
    H.assertEq(H.readByte(0xED74), 0,
      "OT6_PIPPEND is clear the frame the battle goes live (InitBP)")
  end),
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
    armVblank()
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
    -- Put the ROUND BOUNDARY where the measurement starts.  This file is
    -- about "the first cover of a round pays, the rest of that round do
    -- not", and at 4 of 8 seed shifts a cover of the fight's own commits
    -- during the settle before any of it is staged: it arms a pending pip
    -- and, through OT6_COVERPAID, spends the round's one earn, so the first
    -- cover the file then measures banks nothing and the pending byte is
    -- already non-zero.  Both used to read as product failures on builds
    -- either side of #236 (build/sweeps/trueknight/), on the baseline as
    -- much as on the change.  They are staging, so they are staged: the
    -- earn flag and the deferred-pip cell start where the bank and the
    -- relic bit do.  InitBP's own clear of OT6_PIPPEND is asserted at the
    -- top of the run, on the frame the battle goes live, where no cover can
    -- have happened yet -- that property did not move, it moved earlier.
    if H.readByte(PIPPEND) ~= 0 or H.readByte(COVERPAID) ~= 0 then
      H.log(string.format("staging: the settle left OT6_PIPPEND = %d and "
        .. "OT6_COVERPAID = $%02X; both cleared, so the round starts here",
        H.readByte(PIPPEND), H.readByte(COVERPAID)))
    end
    H.writeByte(PIPPEND, 0)
    H.writeByte(COVERPAID, 0)
    H.writeByte(0x3E9C + knight * 2, 1)          -- a bank with room to grow
    H.writeByte(0x3E9D + knight * 2, 0)
    covers, bpWrites = {}, {}
    pipArms, pendWrites, numerals = {}, {}, {}
    watchGlyph = PIP[2]                          -- the glyph a +1 must produce
  end),

  -- ------------------------------------ 1/2/3. the first cover of a round --
  H.driveUntil(function() return #covers > 0 end, 24000, DRIVE,
    "a True Knight cover commits"),
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

    -- With a battle menu open, the party window paints every row's true bank
    -- (Ot6PipGlyph_ext), so the glyph is logged as corroboration; the frames
    -- are asserted on OT6_PIPPEND and OT6_PIPTAIL.
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

    -- the deferral cell: armed on the commit frame, consumed on the numeral
    -- frame.
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
  H.call(function()
    H.vars.mark = #covers; H.vars.coversF0 = H.frame
    vblank.on = true                    -- the frame-budget canary starts here
  end),
  H.driveUntil(function() return coversSince(H.vars.mark) >= 2 end, 30000, DRIVE,
    "two more covers in the same round (the knight never acted)"),
  H.call(function()
    H.log(string.format("covers so far: %d; bank %d; bank writes %d",
      #covers, bp(knight), #bpWrites))
    H.assertEq(bp(knight), 2,
      "further covers in the SAME round protect but bank nothing (the cap)")
    H.assertEq(#bpWrites, 1,
      "and the bank was written exactly once across the whole round")

    -- ------------------------------------------------ the frame budget --
    -- This canary used to assert the SPAN of this phase in frames: ~1635
    -- intact, red at 1715, with 1798 read as "one missed vblank per
    -- battle-loop iteration".  A span cannot carry that claim.  Measured
    -- (#236, logs under build/attempts/<branch>/):
    --
    --   * the span moves a whole ATB ROUND, 163 frames, when ANY change
    --     shifts one cover by one frame.  The first cover lands at f1558 on
    --     one build of this tree and f1559 on another, and the phase then
    --     reads 1635 or 1798 -- the same 163 the old message called a
    --     missed vblank (regress/trueknight-*.log).
    --   * the executed code that moved it was four calls of a ~30-cycle
    --     proc across the whole run (lab/uncontrolled/lab_trueknight_count.log),
    --     which cannot cost a per-frame budget.
    --   * 192 unreachable bytes in ot6_code move the span not at all
    --     (regress/trueknight-sizeonly.log), so it is not size either.
    --
    -- A missed vblank is an OBSERVABLE EVENT, so it is observed instead.
    -- WaitVblank (btlgfx_code) is `inc $47 / spin until the NMI clears it`,
    -- so every call returns ON an NMI: consecutive calls sit one hardware
    -- frame apart while the loop fits its budget and two apart when the
    -- work between them ran past vblank and had to wait for the next one.
    -- Over F frames of a running battle loop the call count is F when
    -- nothing is dropped, so `dropped = F - calls` IS the missed-vblank
    -- count, not a proxy for it.  That number does not care which frame a
    -- cover landed on.
    --
    -- Calibrated by putting a delay loop of known length on the per-frame
    -- path (right after BtlGfx_01's own WaitVblank) and running THIS file
    -- against each build (build/lab/canary/, probe_vblank.lua and the
    -- poison*.sfc it was measured with).  The table this threshold comes
    -- from is in the log line below; the honest headline of it is that the
    -- loop's real headroom is thousands of cycles per iteration, not the
    -- ~160 the old comment implied, and a canary pitched at 160 cycles was
    -- never measuring the budget.
    vblank.on = false
    H.vars.coversSpan = H.frame - H.vars.coversF0
    local vbRate = vblank.loop > 0 and (100.0 * vblank.missed / vblank.loop) or 0
    H.log(string.format("frame-budget canary: %d battle-loop intervals, %d of "
      .. "them longer than one frame (%.2f%%, intact ~%.1f%%, threshold "
      .. "%.1f%%); %d interval(s) longer than %d frames are the loop not "
      .. "running and are excluded; gaps %s.  The phase's own span was %d "
      .. "frames, which is INFORMATIONAL ONLY: it re-rounds by a whole ATB "
      .. "round (~163 frames) when anything shifts one cover by one frame",
      vblank.loop, vblank.missed, vbRate, VBLANK_BASE, VBLANK_MAX,
      vblank.away, VBLANK_GAP_MAX, vblankHist(), H.vars.coversSpan))
    H.assertEq(vblank.loop >= VBLANK_MIN_N, true, string.format(
      "the canary watched a real stretch of battle loop: %d intervals, at "
      .. "least %d needed for a verdict", vblank.loop, VBLANK_MIN_N))
    H.assertEq(vbRate < VBLANK_MAX, true, string.format(
      "FRAME BUDGET: the battle loop ran past vblank on %d of %d iterations "
      .. "(%.2f%%) against a threshold of %.1f%% and ~%.1f%% for an intact "
      .. "build.  Each one is an iteration that did not finish before its "
      .. "NMI and had to wait for the next, so cycles were added to a path "
      .. "that runs once per battle frame.  This is NOT a True Knight "
      .. "failure -- nothing about covers, banks or pips has changed.  Look "
      .. "at the per-frame path (BtlGfx_01 and WaitFrame -> UpdateCharText "
      .. "-> Ot6BgHud_ext, btlgfx_main.asm:415-445) and at the executed $C2 "
      .. "action path (ExecAction, ExecCmd, CheckRetal).  What this costs to "
      .. "trip is measured, not guessed: ~10k cycles per iteration there "
      .. "still misses nothing and ~20k misses a third of them, so a handful "
      .. "of instructions is NOT what brought you here -- look for real "
      .. "per-frame work (issues #66 and #67; #236 for why the old "
      .. "phase-span assertion was replaced by this one).",
      vblank.missed, vblank.loop, vbRate, VBLANK_MAX, VBLANK_BASE))
  end),

  -- ------------------------------------------ 5. the round boundary is real --
  H.call(function()
    holdKnight = false
    serviceKnight = true
    H.vars.acted = false
  end),
  H.driveUntil(function()
    -- his action goes live in $32cc ($ff = nothing queued)
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
    -- assert on the write rather than the absolute bank: the blocker's own
    -- turn also pays him a regen tick, and a settle long enough to guarantee
    -- that landed first would depend on timing.  prev+1 on the commit frame is
    -- the earn.
    local w = nil
    for _, x in ipairs(bpWrites) do if x.f == c.f then w = x end end
    H.assertEq(w ~= nil, true,
      "the earn re-arms at the blocker's own turn end -- a bank write lands on "
      .. "the NEXT round's commit frame (once per ROUND, not once per battle)")
    H.assertEq(w.v, (w.prev or -99) + 1,
      "and it is exactly +1 on that frame")
    H.screenshot("trueknight_next_round")
  end),

  -- Miss draws through the same tail that increments the numeral counter, so
  -- a missed attack raises the counter exactly like a damaging one, and the
  -- deferred pip lands on the frame the word "Miss" appears over the blocker.

  -- An action that issues no numeral at all (or hides numerals) would strand
  -- a pending paint, so Ot6ActionEnd flushes it the same way it flushes
  -- pending reveals. This arm asserts that directly, on a hand-staged
  -- pending value.
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

    -- whichever path pays the pip, the pending byte must be cleared on the
    -- frame the live cell is armed.
    local clearedAt = nil
    for _, w in ipairs(pendWrites) do
      if w.v == 0 and w.f >= H.vars.stagedF then clearedAt = w.f; break end
    end
    H.assertEq(clearedAt, at,
      "6a: OT6_PIPPEND is consumed on the very frame the live cell is armed "
      .. "-- the paint spent it, nothing else cleared it (a clear with no arm "
      .. "is a BP that was earned and never shown)")
  end),

  -- 6b. the backstop, isolated: switch the numeral trigger off and stage
  -- another pending paint, so only Ot6ActionEnd can deliver it.
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
    -- The suppressor mirrors every write to $632e straight into the poll's
    -- own last-seen copy, synchronously at the write, so Ot6RevealPoll
    -- cannot see an edge however many numerals the monsters happen to
    -- produce in the window.  THAT is what makes the delivery above the
    -- backstop's; so that is what is checked.  This arm used to assert that
    -- no numeral occurred in the window at all, which is a property of the
    -- fight and not of the code: it held on one build of this tree and
    -- failed on two others that only shifted the schedule -- including a
    -- build whose only change was a delay loop (#236,
    -- build/lab/canary/tk/{base,mine,poison800}.log).
    H.assertEq(H.readByte(NUMCTR_SHADOW), H.readByte(NUMCTR_SRC),
      "6b: the suppressor held -- the poll's last-seen copy still equals "
      .. "$632e, so no edge could reach it and only the backstop was left "
      .. "to deliver the pip")
    local inWindow = 0
    for _, n in ipairs(numerals) do
      if n >= H.vars.stagedF2 and n <= at then inWindow = inWindow + 1 end
    end
    H.log(string.format("6b: %d numeral(s) happened in the window and none "
      .. "of them could reach the poll", inWindow))
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

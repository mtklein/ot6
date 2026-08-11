-- @suite slow
-- battle_breakflash.lua -- issue #48: breaking an enemy is an audio-visual
-- MOMENT, it lands on the break frame, and it is LOCAL to the enemy broken.
--
-- Visual-only assertions have been unreliable in this tree, so every claim
-- here is made against the mechanism and the screenshots are corroboration:
--
--   1. THE FRAME.  The chip banks $FF in OT6_BRKTICK at damage CALC; the
--      flash arms on a DAMAGE-NUMERAL frame ($632E moving), strictly later.
--      #33's clockwork rule; the timeline is logged either way.
--   2. LOCALITY.  The broken guard's sprite-data byte (w7e80db + slot*2,
--      btlgfx_ram.inc:720) has its obj-palette bits driven to 3 -- the
--      engine's own flash/death scratch slot -- while its UNBROKEN sibling
--      is never armed and never leaves the 0/1/2 vanilla assigned it
--      (btlgfx_main.asm:4917-4921).  No screen-wide effect can do that.
--   3. THE PALETTE.  Obj palette 3 (w7e7e00::_11 = $7E7F60) holds $7FFF --
--      white -- while the broken monster points at it.
--   4. THE SOUND, ONCE.  Exactly one animation-sfx enable (w7ee9ec) carrying
--      OT6_BREAK_SFX ($BE) per break, panned to the broken monster's screen
--      x, however many hits the breaking action landed.
--   5. THE HAND-BACK.  Three 4-frame white pulses, then the sprite goes back
--      to its own palette bits, all inside OT6_BREAK_FLASH frames.
--   6. TWO AT ONCE.  Both guards armed for the same damage frame flash
--      together and share ONE cleave -- the multi-break case a single-target
--      beam on a two-monster formation cannot stage naturally.
--   6b. NO REVEAL TO RIDE (#63).  A break landing on a hit that reveals
--      NOTHING NEW still flashes and still cleaves -- asserted with both
--      revealed bytes byte-identical across the phase.  The arm hangs off
--      Ot6RevealCommit's tail, and #63 was filed on the theory that this made
--      it reveal-dependent; it does not, because Ot6RevealPoll calls that proc
--      on every damage-numeral edge whether anything is pending or not.  This
--      phase is a PIN on that, not a regression check -- it passes pre-fix too.
--   6c. THE BREAK THAT ALSO KILLS (#63, THE REGRESSION).  A breaking hit takes
--      elemental x2 AND broken x2, so in real play the break usually IS the
--      kill -- and pinLab's HP pin made that case unreachable here, which is
--      how v0.8-rc1 shipped answering it with nothing at all.  With the HP pin
--      LIFTED on the target: the white flash is correctly refused (the death
--      fade owns obj palette 3 and w7e80db) but the cleave still fires, on the
--      damage frame, panned to the monster, and is dispatched to the APU
--      before the death sound replaces it.  FAILS on the pre-fix ROM.
--   7. NMI BUDGET (#33's hard lesson).  Extra per-frame battle traffic once
--      pushed the engine's line transfers past vblank and froze every ATB
--      with menus wedged shut.  This effect adds no transfer at all (palette
--      3 and w7e80db ride DMAs btlgfx_main.asm:1512-1518 makes
--      unconditionally), so the fight must keep ticking across a live flash:
--      asserted directly, ATB gauges and a menu open.
--
-- LAB CONTROL, and it is load-bearing: VANILLA ALSO DRIVES THIS BYTE.  A
-- monster flashes palette 3 for 16 frames when it takes its turn
-- (btlgfx_main.asm:23384-23410, measured live on this very formation --
-- probe_sprdata saw C1/9B5D write $06/$00 to slot 3 at f545/f549/f553/f557).
-- Left alone that would forge exactly the observation this test is looking
-- for, so the per-monster once-a-battle latch that gates it (w7e618b, one
-- byte per slot, :23374) is pinned nonzero for both guards.  Every palette-3
-- frame observed after that is OT6's.
--
-- Otherwise battle_break.lua's proven laboratory: walk into the entry-point
-- guard fight, poke both guards fire-weak and tough, spam Fire Beam.  Guards
-- sit in monster slots 2/3 -> slot offsets 4/6.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local BRKTICK   = 0xED76        -- OT6_BRKTICK, stride 2 by slot offset
local FLASHPAL  = 0x7F60        -- w7e7e00::_11, obj palette 3
local SPRDATA   = 0x80DB        -- w7e80db, stride 2 by slot offset
local MONFLASH  = 0x618B        -- vanilla's per-monster turn-flash latch
local BROKEN    = 0x3E90        -- OT6_BROKEN_TICKS at the monster half
local MONHP     = 0x3BFC
local MONX      = 0x80C3
local NUMCTR    = 0x632E        -- damage-numeral thread counter
local ATB       = 0x3218        -- per-character atb gauge (battle-ram.txt:691)
local BREAK_SFX = 0xBE
local FLASH_LEN = 0x18

local SHIELD    = 0x3E40        -- OT6_SHIELD_CUR at the monster half
local REVE      = 0x3E91        -- OT6_REVEALED_ELEM at the monster half
local REVC      = 0x3EA5        -- OT6_BOOST_REVEALED at the monster half
local STATUS1   = 0x3EEC        -- monster status 1 (wound $80 / petrify $02)

local G = { [1] = 4, [2] = 6 }  -- guard 1/2 -> monster slot offsets
local function tick(g)    return H.readByte(BRKTICK + G[g]) end
local function live(g)    local t = tick(g); return t ~= 0 and t ~= 0xFF end
local function palBits(g) return H.readByte(SPRDATA + G[g]) & 0x0E end

-- ---------------------------------------------------------------- watchers
local sfx = {}                  -- one entry per queued animation sfx
local ecWrites = {}             -- EVERY write to the enable byte, zeroes too:
                                --   a zero means the engine consumed the queue,
                                --   which is how we can tell a queued cleave was
                                --   dispatched rather than overwritten by the
                                --   next sound (#63; we cannot hear it)
local hpWrites = {}             -- damage-CALC frames
local pendF, armF, offF = {}, {}, {}
local prevTick, eatenF = {}, {}          -- the frame a PENDING byte was consumed
local white   = { [1] = {}, [2] = {} }   -- our-flash frames on palette 3
local foreign = { [1] = 0, [2] = 0 }     -- palette 3 with no flash of ours
local palWhiteF, cgWhiteF = nil, nil
local oamP3live, oamP3idle = 0, 0
local numeralF, lastCtr = {}, nil
local watch = false
-- The corroborating screenshot has to be grabbed from INSIDE the sampler.
-- A drive step's predicate is only evaluated between its inner steps (~30
-- frames apart here), which is longer than the whole 24-frame flash -- the
-- first version of this test shot two perfectly normal-coloured guards.
local shot, shotAt = nil, nil

-- how many OAM entries are drawn with obj palette 3 right now.  This is the
-- one reading that proves the flash REACHED THE SCREEN rather than merely
-- reaching wram: the monster sprite builder folds w7e80db into each object's
-- attribute byte (one_mon_obj_set, btlgfx_main.asm:8027-8030).
local function oamPal3()
  local n = 0
  for i = 0, 127 do
    if ((emu.read(i * 4 + 3, emu.memType.snesSpriteRam) >> 1) & 0x07) == 3 then
      n = n + 1
    end
  end
  return n
end

-- obj palette 3 in CGRAM.  The PPU update DMAs w7e7e00::_8..15 as one fixed
-- $100-byte block to cgram $100 (btlgfx_main.asm:1512-1518), so palette 3
-- lands at cgram byte $160.
local function cgPal3() return emu.readWord(0x160, emu.memType.snesCgRam) end

local function sample()
  if not watch then return end
  local anyLive = false
  for g = 1, 2 do
    local t = tick(g)
    if t == 0xFF and not pendF[g] then pendF[g] = H.frame end
    if prevTick[g] == 0xFF and t ~= 0xFF and not eatenF[g] then
      eatenF[g] = H.frame          -- Ot6BreakStart looked at this slot HERE,
    end                            --   armed or refused
    prevTick[g] = t
    if live(g) then
      if not armF[g] then armF[g] = H.frame end
      anyLive = true
      if palBits(g) == 0x06 then
        white[g][#white[g] + 1] = H.frame
        if not palWhiteF and H.readWord(FLASHPAL) == 0x7FFF then
          palWhiteF = H.frame
        end
        if not cgWhiteF and cgPal3() == 0x7FFF then cgWhiteF = H.frame end
        if not shot and #white[g] >= 3 then
          local ok, png = pcall(emu.takeScreenshot)
          if ok and type(png) == "string" and #png > 0 then
            shot, shotAt = png, H.frame
          end
        end
      end
    else
      if armF[g] and not offF[g] then offF[g] = H.frame end
      if palBits(g) == 0x06 then foreign[g] = foreign[g] + 1 end
    end
  end
  -- the rendered frame lags the wram write by one, so an object count taken
  -- while the flash is live describes the frame before -- which is why the
  -- idle reading is only trusted once the flash has been over for a while
  if anyLive then
    local n = oamPal3()
    if n > oamP3live then oamP3live = n end
  end
  local ctr = H.readByte(NUMCTR)
  if lastCtr ~= nil and ctr ~= lastCtr then numeralF[#numeralF + 1] = H.frame end
  lastCtr = ctr
end

local function resetWatch()
  sfx, hpWrites, ecWrites = {}, {}, {}
  pendF, armF, offF = {}, {}, {}
  prevTick, eatenF = {}, {}
  white = { [1] = {}, [2] = {} }
  foreign = { [1] = 0, [2] = 0 }
  palWhiteF, cgWhiteF, numeralF, lastCtr = nil, nil, {}, nil
  oamP3live, oamP3idle = 0, 0
  shot, shotAt = nil, nil
end

-- emit whatever the sampler grabbed mid-flash
local function emitShot(tag)
  if shot then
    H.emitBlob(tag .. ".png", shot)
    H.log(string.format("screenshot '%s' taken on flash frame %d", tag, shotAt))
  else
    -- emu.takeScreenshot() has returned an empty string for the SECOND grab
    -- inside one run here; the phase's white frames are asserted at the
    -- cgram/oam level above either way, and probe_breakvis.lua carries a
    -- hand-checked picture of two guards flashing together.
    H.log("screenshot '" .. tag .. "' not captured (takeScreenshot returned "
      .. "nothing); the mechanism asserts above stand on their own")
  end
end

local function breakSfx()
  local hits = {}
  for _, s in ipairs(sfx) do
    if s.id == BREAK_SFX then hits[#hits + 1] = s end
  end
  return hits
end

-- the lab pin, re-applied every drive tick.
--
-- #63: BOTH of these pins hide a candidate cause of "the flash never fires in
-- real play", which is how that bug shipped green.  The HP pin means a break
-- can never coincide with a kill -- and a breaking hit collects elemental x2
-- AND broken x2, so in real play it usually IS the kill.  Phase 5 below is
-- deliberately run with the HP pin LIFTED on the target for exactly that
-- reason; nothing else in this file may quietly assume it applies.
local function pinLab(skip)
  for g = 1, 2 do
    H.writeByte(MONFLASH + (G[g] >> 1), 1)     -- vanilla turn-flash: spent
    if g ~= skip and H.readWord(MONHP + G[g]) < 2500 then
      H.writeWord(MONHP + G[g], 6000)          -- nobody dies mid-flash
    end
  end
end

-- put a guard back on the field with a full gauge, for another natural break
local function regauge(g)
  H.writeByte(BROKEN + G[g], 0)
  H.writeByte(BRKTICK + G[g], 0)
  H.writeByte(SHIELD + G[g], 2)
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from entry point"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    H.assertEq(H.readByte(0x3E44), 2, "guard 1 shields seeded")
    H.assertEq(H.readByte(0x3E46), 2, "guard 2 shields seeded")
    -- the stale/power-on control: OT6_BRKTICK and OT6_BRKPAL sit past
    -- InitBP's shadow clear, so Ot6SeedShields is their ONLY clear.  If it
    -- ever stopped zeroing them, junk here would flash a monster white on
    -- the opening frames of a fight and hand it back a junk palette.
    for g = 1, 2 do
      H.assertEq(tick(g), 0,
        string.format("guard %d break-flash cell seeded clean", g))
      H.assertEq(H.readByte(BRKTICK + 12 + G[g]), 0,
        string.format("guard %d banked palette seeded clean", g))
    end
    local t = {}
    for s = 0, 5 do
      t[#t + 1] = string.format("s%d=%02X", s, H.readByte(SPRDATA + s * 2))
    end
    H.log("w7e80db before the lab pin: " .. table.concat(t, " "))
    -- lab: fire-weak, tough, uniform casters (battle_break.lua's setup)
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    for c = 0, 2 do
      H.writeByte(0x3B18 + c * 2, 5)
      H.writeByte(0x3B41 + c * 2, 10)
    end
    pinLab()
    emu.addMemoryCallback(function()
      hpWrites[#hpWrites + 1] = H.frame
    end, emu.callbackType.write, 0x7E3BFC, 0x7E3C07)
    emu.addMemoryCallback(function(_, v)
      ecWrites[#ecWrites + 1] = { f = H.frame, v = v, id = H.readByte(0xE9E9) }
      if v == 0 then return end
      sfx[#sfx + 1] = { f = H.frame, id = H.readByte(0xE9E9),
                        cmd = H.readByte(0xE9E8), pan = H.readByte(0xE9EA) }
    end, emu.callbackType.write, 0x7EE9EC, 0x7EE9EC)
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    watch = true
    H.log("lab: guards fire-weak, hp pinned, vanilla turn-flash latched off")
  end),

  -- ---------------- phase 1: one natural break, on the damage frame -------
  H.driveUntil(function()
    pinLab()
    return offF[1] ~= nil or offF[2] ~= nil
  end, 30000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "a guard to break, flash, and hand its sprite back"),
  H.release(),

  H.call(function()
    watch = false
    local b = offF[1] and 1 or 2          -- the guard that broke
    local o = 3 - b                       -- its sibling
    H.log(string.format("broken guard %d: pend f%s -> arm f%s -> off f%s "
      .. "(broken timers %02X/%02X)",
      b, tostring(pendF[b]), tostring(armF[b]), tostring(offF[b]),
      H.readByte(BROKEN + G[1]), H.readByte(BROKEN + G[2])))
    H.log(string.format("hp-write (damage calc) frames: first %s last %s (n=%d)",
      tostring(hpWrites[1]), tostring(hpWrites[#hpWrites]), #hpWrites))
    do
      local t = {}
      for _, f in ipairs(numeralF) do
        if math.abs(f - (armF[b] or 0)) <= 60 then t[#t + 1] = tostring(f) end
      end
      H.log("numeral frames within 60 of the arm: " .. table.concat(t, ","))
    end
    H.log(string.format("white frames: guard %d n=%d (%s..%s); guard %d n=%d; "
      .. "foreign palette-3 frames %d/%d",
      b, #white[b], tostring(white[b][1]), tostring(white[b][#white[b]]),
      o, #white[o], foreign[1], foreign[2]))
    for i, s in ipairs(sfx) do
      H.log(string.format("sfx #%d f%d id=%02X cmd=%02X pan=%02X",
        i, s.f, s.id, s.cmd, s.pan))
    end

    -- 1. THE FRAME
    H.assertEq(pendF[b] ~= nil, true,
      "the chip banked the flash as PENDING ($FF) when the gauge emptied")
    H.assertEq(#hpWrites > 0, true, "damage landed")
    H.assertEq(armF[b] > pendF[b], true,
      "the flash arms strictly AFTER it was banked -- it is deferred to the "
      .. "damage frame, not fired at the chip hundreds of frames earlier")
    local onNumeral = false
    for _, f in ipairs(numeralF) do
      -- Ot6RevealPoll sees $632E move on its own main-loop tick; the arm is
      -- that tick or a few after (#33 measured the same slack for reveals)
      if armF[b] - f >= -2 and armF[b] - f <= 12 then onNumeral = true end
    end
    H.assertEq(onNumeral, true,
      "the flash arms on a damage-numeral frame -- the frame the player sees "
      .. "the break land")

    -- 2. LOCALITY
    H.assertEq(#white[b] > 0, true, "the broken guard flashed")
    H.assertEq(tick(o), 0, "the sibling was never even armed")
    H.assertEq(armF[o], nil, "...at any point during the break")
    H.assertEq(#white[o], 0, "and never flashed")
    H.assertEq(foreign[o], 0,
      "the UNBROKEN sibling never touched palette 3 at all -- the effect is "
      .. "local to the enemy that broke, not screen-wide")

    -- 3. THE PALETTE, ALL THE WAY TO THE PPU
    H.assertEq(palWhiteF ~= nil, true,
      "obj palette 3 held $7FFF (white) while the broken guard pointed at it")
    H.assertEq(cgWhiteF ~= nil, true,
      "and CGRAM held it too -- the white really reached the screen, not "
      .. "just wram (this is the reading a screenshot cannot be trusted for)")
    H.assertEq(oamP3live > 0, true,
      string.format("the broken monster's sprite objects were DRAWN with "
        .. "palette 3 (%d oam entries at peak)", oamP3live))
    oamP3idle = oamPal3()
    H.assertEq(oamP3idle, 0,
      string.format("and none are once the flash is over (%d)", oamP3idle))

    -- 5. CADENCE AND HAND-BACK
    H.assertEq(palBits(b) ~= 0x06, true,
      "the sprite is back on its own palette after the flash")
    H.assertEq(offF[b] - armF[b] <= FLASH_LEN + 4, true,
      string.format("the flash is over inside its %d-frame budget "
        .. "(arm %d, off %d)", FLASH_LEN, armF[b], offF[b]))
    H.assertEq(#white[b] >= 10 and #white[b] <= 14, true,
      string.format("three 4-frame white pulses (%d white frames)", #white[b]))

    -- 4. THE SOUND, ONCE
    local hits = breakSfx()
    H.assertEq(#hits, 1,
      string.format("exactly one break cleave queued for one break (%d)", #hits))
    H.assertEq(hits[1].cmd, 0x18, "queued as spc command $18 (play game sfx)")
    H.assertEq(math.abs(hits[1].f - armF[b]) <= 2, true,
      string.format("and on the arm frame (sfx f%d, arm f%d)",
        hits[1].f, armF[b]))
    H.assertEq(hits[1].pan, H.readByte(MONX + G[b]),
      "panned to the broken monster's screen x (a monster-local sound)")
    H.vars.oamOne = oamP3live
    H.vars.tgt = b               -- the guard the beam actually lands on;
    H.vars.sib = o               --   phases 4 and 5 restage on the same one
    emitShot("breakflash_white")
    H.screenshot("breakflash_handback")
  end),

  -- ---------------- phase 2: two armed at once share one cleave -----------
  -- The entry point is a two-monster formation and a single-target beam cannot
  -- break both in one action, so the multi-break case is staged at the
  -- mechanism: bank BOTH pending and let the next numeral arm them.
  H.call(function()
    resetWatch()
    for g = 1, 2 do
      H.writeByte(BROKEN + G[g], 0)            -- unbreak: no re-chip, no check
      H.writeByte(BRKTICK + G[g], 0xFF)        -- both pending
    end
    pinLab()
    watch = true
  end),
  H.driveUntil(function()
    pinLab()
    for g = 1, 2 do
      if H.readByte(BRKTICK + G[g]) == 0 and not armF[g] then
        H.writeByte(BRKTICK + G[g], 0xFF)      -- re-bank if a pass refused
      end
    end
    return armF[1] ~= nil and armF[2] ~= nil
  end, 12000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "both guards' pending flashes to arm"),
  H.release(),
  H.call(function() emitShot("breakflash_pair") end),
  H.waitFrames(40),
  H.call(function()
    watch = false
    local hits = breakSfx()
    H.log(string.format("pair: arm f%s/f%s, white frames %d/%d, cleaves %d",
      tostring(armF[1]), tostring(armF[2]), #white[1], #white[2], #hits))
    H.assertEq(armF[1], armF[2],
      "two enemies armed for the same damage frame flash on the SAME frame")
    H.assertEq(#white[1] > 0 and #white[2] > 0, true, "and both really flashed")
    H.assertEq(oamP3live > 0, true,
      string.format("both were drawn white (%d oam entries at peak, against "
        .. "%d for one guard in phase 1)", oamP3live, H.vars.oamOne or -1))
    H.assertEq(#hits, 1,
      string.format("sharing ONE cleave, not one each (%d)", #hits))
  end),

  -- ---------------- phase 3: the nmi budget stays inside vblank -----------
  H.call(function()
    resetWatch()
    pinLab()
    for g = 1, 2 do H.writeByte(BRKTICK + G[g], 0xFF) end
    watch = true
    H.vars.atb0 = {}
    for s = 0, 3 do H.vars.atb0[s] = H.readWord(ATB + s * 2) end
    H.vars.liveFrames = 0
    H.vars.atbMoved = 0
  end),
  H.driveUntil(function()
    pinLab()
    if live(1) or live(2) then
      H.vars.liveFrames = H.vars.liveFrames + 1
      local moved = 0
      for s = 0, 3 do
        if H.readWord(ATB + s * 2) ~= H.vars.atb0[s] then moved = moved + 1 end
      end
      if moved > H.vars.atbMoved then H.vars.atbMoved = moved end
    end
    return H.vars.liveFrames >= 12
  end, 12000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(1),
  }, "twelve frames sampled with a break flash live"),
  H.release(),
  H.call(function()
    watch = false
    H.log(string.format("nmi budget: %d frames with a flash live, %d/4 atb "
      .. "gauges moved during them", H.vars.liveFrames, H.vars.atbMoved))
    H.assertEq(H.vars.atbMoved > 0, true,
      "atb keeps running across a live break flash -- #33's signature (every "
      .. "gauge frozen, menus wedged shut) does not reproduce")
  end),
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 6000, {
    H.call(function() pinLab() end), H.waitFrames(4),
  }, "a battle menu still opens after the flash window"),

  -- ---------------- phase 4: a break that reveals NOTHING NEW -------------
  -- Phase 1 breaks a 2-shield guard, so its reveal already lands on chip ONE
  -- and its break on chip TWO -- but nothing here ever ASSERTED that, and a
  -- reader (and #63's filed hypothesis) could reasonably believe the effect
  -- rode the reveal.  This phase pins it: the guard goes in with its fire
  -- weakness already known, breaks, and the revealed bytes are asserted
  -- BYTE-IDENTICAL across the whole phase.  So the break moment cannot be
  -- riding a reveal -- there is none to ride.
  --
  -- FAIL-BEFORE, STATED PLAINLY: this phase passes on the pre-#63 ROM too.  It
  -- is a pin on a property that was already true, not the check that catches
  -- the bug -- phase 5 is.
  H.call(function()
    resetWatch()
    local b = H.vars.tgt
    regauge(1)
    regauge(2)
    pinLab()
    H.vars.rev0 = {}
    for g = 1, 2 do
      H.vars.rev0[g] = { e = H.readByte(REVE + G[g]), c = H.readByte(REVC + G[g]) }
    end
    H.log(string.format("phase 4: revealed going in E/C = %02X/%02X and "
      .. "%02X/%02X; target is guard %d",
      H.vars.rev0[1].e, H.vars.rev0[1].c, H.vars.rev0[2].e, H.vars.rev0[2].c, b))
    H.assertEq(H.vars.rev0[b].e & 0x01, 0x01,
      "the target guard's FIRE weakness is already revealed before this break "
      .. "-- so the breaking chip reveals nothing new")
    watch = true
  end),
  H.driveUntil(function()
    pinLab()
    return armF[1] ~= nil or armF[2] ~= nil
  end, 14000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "a break landing on a hit that reveals nothing new"),
  H.release(),
  H.waitFrames(40),
  H.call(function()
    watch = false
    local b = armF[1] and 1 or 2
    local hits = breakSfx()
    H.log(string.format("phase 4: guard %d pend f%s -> arm f%s, white %d, "
      .. "cleaves %d, revealed now E/C = %02X/%02X and %02X/%02X",
      b, tostring(pendF[b]), tostring(armF[b]), #white[b], #hits,
      H.readByte(REVE + G[1]), H.readByte(REVC + G[1]),
      H.readByte(REVE + G[2]), H.readByte(REVC + G[2])))
    for g = 1, 2 do
      H.assertEq(H.readByte(REVE + G[g]), H.vars.rev0[g].e,
        string.format("guard %d's revealed ELEMENTS did not change across this "
          .. "break -- nothing new was revealed by it", g))
      H.assertEq(H.readByte(REVC + G[g]), H.vars.rev0[g].c,
        string.format("guard %d's revealed CLASSES did not change either", g))
    end
    H.assertEq(#white[b] > 0, true,
      "the break still flashed even though no reveal accompanied it")
    H.assertEq(#hits, 1,
      string.format("and still cleaved exactly once (%d)", #hits))
  end),

  -- ---------------- phase 5: the breaking blow that also KILLS ------------
  -- THE CASE THE OWNER PLAYS, and the case pinLab's HP pin made unreachable.
  -- A breaking hit takes vanilla's elemental x2 and then Ot6BrokenDmg's x2 --
  -- 4x base -- so on ordinary bodies the break IS the kill.  v0.8-rc1 answered
  -- that with NOTHING: Ot6BreakStart's hp-already-zero refusal skipped the
  -- flash AND the cleave (probe_breakplay measured hp=0000, status $80, zero
  -- $BE queued).  The flash is still correctly refused -- the death animation
  -- loads MonsterDeathPal into this very palette slot and repoints w7e80db at
  -- it, btlgfx_main.asm:22259-22266 -- but the CLEAVE must fire.
  --
  -- FAIL-BEFORE OBSERVED: on the pre-fix ROM this phase fails at the cleave
  -- count with 0.
  H.call(function()
    resetWatch()
    local b, o = H.vars.tgt, H.vars.sib
    regauge(b)
    regauge(o)
    -- once the target dies the beam retargets to the sibling, and a SECOND
    -- break inside the assertion window would inflate the cleave count.  Six
    -- shields on the sibling puts that out of reach of the tail frames.
    H.writeByte(SHIELD + G[o], 6)
    pinLab()
    -- 450 hp: chip one (elemental x2 then shielded x0.5 ~ 1x base, measured
    -- ~134 in battle_break) leaves it alive; the breaking chip (x2 and x2
    -- unattenuated, ~536) kills it.  The SIBLING stays pinned so the battle
    -- does not end under the assertions.
    H.writeWord(MONHP + G[b], 450)
    H.vars.tgtX = H.readByte(MONX + G[b])
    H.log(string.format("phase 5: guard %d hp -> 450, hp pin LIFTED on it "
      .. "(screen x %02X); sibling %d stays pinned", b, H.vars.tgtX, o))
    watch = true
  end),
  H.driveUntil(function()
    pinLab(H.vars.tgt)                       -- pin the sibling ONLY
    local b = H.vars.tgt
    return H.readWord(MONHP + G[b]) == 0 and eatenF[b] ~= nil
  end, 14000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "a break whose blow also kills the monster"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    watch = false
    local b = H.vars.tgt
    local hits = breakSfx()
    H.log(string.format("phase 5: guard %d hp=%04X status1=%02X brokenTimer=%02X "
      .. "pend f%s -> consumed f%s; tick now %02X, white frames %d, cleaves %d",
      b, H.readWord(MONHP + G[b]), H.readByte(STATUS1 + G[b]),
      H.readByte(BROKEN + G[b]), tostring(pendF[b]), tostring(eatenF[b]),
      tick(b), #white[b], #hits))
    for i, s in ipairs(sfx) do
      H.log(string.format("  sfx #%d f%d id=%02X cmd=%02X pan=%02X",
        i, s.f, s.id, s.cmd, s.pan))
    end
    do
      local t = {}
      for _, w in ipairs(ecWrites) do
        t[#t + 1] = string.format("f%d:%02X(id %02X)", w.f, w.v, w.id)
      end
      H.log("  enable-byte writes: " .. table.concat(t, " "))
    end

    -- the coincidence really happened
    H.assertEq(pendF[b] ~= nil, true, "the gauge emptied: a flash was banked")
    H.assertEq(H.readWord(MONHP + G[b]), 0,
      "and the breaking blow left the monster at zero hp")
    H.assertEq(H.readByte(BROKEN + G[b]) ~= 0, true,
      "it really was a BREAK, not just a kill (the broken timer is up)")

    -- the flash is refused, deliberately: the death animation owns palette 3
    H.assertEq(#white[b], 0,
      string.format("the white flash is REFUSED on a kill -- the death fade "
        .. "owns obj palette 3 and w7e80db (%d white frames)", #white[b]))
    H.assertEq(tick(b), 0,
      "and the pending byte is consumed rather than left to outlive the action")

    -- ...but the break is still AUDIBLE.  This is the assertion #48 could not
    -- have made and the one that fails on the shipped ROM.
    H.assertEq(#hits, 1,
      string.format("the break still CLEAVES when its blow also kills -- one "
        .. "$%02X queued (%d)", BREAK_SFX, #hits))
    H.assertEq(hits[1].cmd, 0x18, "queued as spc command $18 (play game sfx)")
    H.assertEq(math.abs(hits[1].f - eatenF[b]) <= 4, true,
      string.format("on the frame the pending byte was consumed -- still the "
        .. "damage frame, not damage calc (sfx f%d, consumed f%s)",
        hits[1].f, tostring(eatenF[b])))
    H.assertEq(hits[1].pan, H.vars.tgtX,
      "panned to the broken monster's screen x, as on the surviving path")

    -- ...and it was DISPATCHED, not overwritten.  This is the one thing about
    -- the sound that can be established without hearing it, and it is worth
    -- establishing here specifically: the death animation queues its own $2D
    -- into these same four bytes a few frames later (btlgfx_main.asm:22292-
    -- 22296), so on the kill path a cleave that sat in the queue would be
    -- silently replaced by the death sound.  UpdateSfx runs from NMI, copies
    -- the three bytes to the APU ports and ZEROES the enable byte
    -- (btlgfx_main.asm:3189-3200) -- so a zero write following ours, before any
    -- other sound is queued, is proof the cleave reached hAPUIO0-2.
    local mine, consumed, stomped = nil, nil, false
    for _, w in ipairs(ecWrites) do
      if mine == nil and w.v ~= 0 and w.id == BREAK_SFX then
        mine = w.f
      elseif mine ~= nil and consumed == nil then
        if w.v == 0 then consumed = w.f else stomped = true end
      end
    end
    H.log(string.format("cleave queued f%s, enable byte zeroed f%s, "
      .. "stomped-before-dispatch=%s",
      tostring(mine), tostring(consumed), tostring(stomped)))
    H.assertEq(stomped, false,
      "nothing else queued a sound into those four bytes before the cleave was "
      .. "dispatched")
    H.assertEq(consumed ~= nil, true,
      "UpdateSfx consumed the cleave and wrote it out to the APU ports")
    -- what remains unverifiable, and is labelled rather than claimed: whether
    -- $BE SOUNDS like a break.  #48 chose it by grep and never auditioned it;
    -- neither can this test.  It is one constant, OT6_BREAK_SFX.
  end),

  H.logStep(function() return "battle_breakflash complete" end),
})

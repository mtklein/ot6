-- @suite slow
-- battle_breakflash.lua -- breaking an enemy is an audio-visual event, it
-- lands on the break frame, and it is local to the enemy broken.

-- Visual-only assertions have been unreliable in this tree, so every claim
-- here is made against the mechanism and the screenshots are corroboration:

-- Otherwise this uses battle_break.lua's laboratory: walk into the
-- entry-point guard fight, poke both guards fire-weak and tough, and spam Fire
-- Beam.  Guards sit in monster slots 2 and 3, at slot offsets 4 and 6.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

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
local hpWrites = {}             -- damage-CALC frames
local pendF, armF, offF = {}, {}, {}
local prevTick, eatenF = {}, {}          -- the frame a PENDING byte was consumed
local white   = { [1] = {}, [2] = {} }   -- our-flash frames on palette 3
local foreign = { [1] = 0, [2] = 0 }     -- palette 3 with no flash of ours
local palWhiteF, cgWhiteF = nil, nil
local oamP3live, oamP3idle = 0, 0
local numeralF, lastCtr = {}, nil
local watch = false
-- The corroborating screenshot has to be grabbed from inside the sampler.
-- A drive step's predicate is only evaluated between its inner steps (~30
-- frames apart here), which is longer than the whole 24-frame flash; the
-- first version of this test photographed two normally coloured guards.
local shot, shotAt = nil, nil

-- how many OAM entries are drawn with obj palette 3 right now.  This is the
-- one reading that shows the flash reached the screen rather than only
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
  -- while the flash is live describes the frame before, which is why the
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
    -- emu.takeScreenshot() has returned an empty string for the second grab
    -- inside one run here; the phase's white frames are asserted at the
    -- cgram and oam level above either way, and probe_breakvis.lua carries a
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
    -- the stale and power-on control: OT6_BRKTICK and OT6_BRKPAL sit past
    -- InitBP's shadow clear, so Ot6SeedShields is their only clear.  If it
    -- stopped zeroing them, junk here would flash a monster white on
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

    -- 1. the frame
    H.assertEq(pendF[b] ~= nil, true,
      "the chip banked the flash as PENDING ($FF) when the gauge emptied")
    H.assertEq(#hpWrites > 0, true, "damage landed")
    H.assertEq(armF[b] > pendF[b], true,
      "the flash arms strictly AFTER it was banked -- it is deferred to the "
      .. "damage frame, not fired at the chip hundreds of frames earlier")
    local onNumeral = false
    for _, f in ipairs(numeralF) do
      if armF[b] - f >= -2 and armF[b] - f <= 12 then onNumeral = true end
    end
    H.assertEq(onNumeral, true,
      "the flash arms on a damage-numeral frame -- the frame the player sees "
      .. "the break land")

    -- 2. locality
    H.assertEq(#white[b] > 0, true, "the broken guard flashed")
    H.assertEq(tick(o), 0, "the sibling was never even armed")
    H.assertEq(armF[o], nil, "...at any point during the break")
    H.assertEq(#white[o], 0, "and never flashed")
    H.assertEq(foreign[o], 0,
      "the UNBROKEN sibling never touched palette 3 at all -- the effect is "
      .. "local to the enemy that broke, not screen-wide")

    -- 3. the palette, all the way to the PPU
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

    -- 5. cadence and hand-back
    H.assertEq(palBits(b) ~= 0x06, true,
      "the sprite is back on its own palette after the flash")
    H.assertEq(offF[b] - armF[b] <= FLASH_LEN + 4, true,
      string.format("the flash is over inside its %d-frame budget "
        .. "(arm %d, off %d)", FLASH_LEN, armF[b], offF[b]))
    H.assertEq(#white[b] >= 10 and #white[b] <= 14, true,
      string.format("three 4-frame white pulses (%d white frames)", #white[b]))

    -- 4. the sound, once
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
  -- mechanism: bank both pending and let the next numeral arm them.
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

  H.call(function()
    resetWatch()
    local b, o = H.vars.tgt, H.vars.sib
    regauge(b)
    regauge(o)
    -- once the target dies the beam retargets to the sibling, and a second
    -- break inside the assertion window would inflate the cleave count.  Six
    -- shields on the sibling puts that out of reach of the tail frames.
    H.writeByte(SHIELD + G[o], 6)
    pinLab()
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

    -- the coincidence happened
    H.assertEq(pendF[b] ~= nil, true, "the gauge emptied: a flash was banked")
    H.assertEq(H.readWord(MONHP + G[b]), 0,
      "and the breaking blow left the monster at zero hp")
    H.assertEq(H.readByte(BROKEN + G[b]) ~= 0, true,
      "it really was a BREAK, not just a kill (the broken timer is up)")

    -- the flash is refused on purpose: the death animation owns palette 3
    H.assertEq(#white[b], 0,
      string.format("the white flash is REFUSED on a kill -- the death fade "
        .. "owns obj palette 3 and w7e80db (%d white frames)", #white[b]))
    H.assertEq(tick(b), 0,
      "and the pending byte is consumed rather than left to outlive the action")

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

    -- and it was dispatched rather than overwritten.  This is the one thing
    -- about the sound that can be established without hearing it, and it
    -- matters here: the death animation queues its own $2D
    -- into these same four bytes a few frames later (btlgfx_main.asm:22292-
    -- 22296), so on the kill path a cleave that sat in the queue would be
    -- replaced by the death sound with no sign of it.  UpdateSfx runs from
    -- NMI, copies the three bytes to the APU ports and zeroes the enable byte
    -- (btlgfx_main.asm:3189-3200), so a zero write following ours, before any
    -- other sound is queued, shows the cleave reached hAPUIO0-2.
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
  end),

  H.logStep(function() return "battle_breakflash complete" end),
})

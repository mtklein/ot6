-- probe_revealbeat.lua -- how far ahead of the damage numerals does a
-- weakness reveal actually land?
--
-- Playtest: "weaknesses reveal a little too early... i'd expect the ? to
-- turn into the revealed icon when the damage numbers pop up, but it
-- shows pretty much immediately when the action starts.  it's cosmetic
-- polish, no effect on the gameplay."
--
-- STATUS: HALF ANSWERED.  Committed as the instrument, not as a fix --
-- the fix was deliberately NOT written, because the beat it would have
-- to defer to is still unmeasured and guessing at it is exactly what
-- CONTRIBUTING.md forbids.
--
-- What this establishes, on battle_doorstep with every monster made
-- fire-weak and unrevealed (one representative run):
--     f00044  EXEC attack id 00
--     f00073  EXEC attack id 83  +  reveal mask $3e97 -> 01
--     f00074  monster 3 hp 4000 -> 3869   (damage applied)
--     f00076  hud glyph flips '?' -> fire
-- So the DISPLAY is not lagging the state: Ot6Chip writes the mask
-- during damage calculation and the under-monster hud picks it up three
-- frames later, two frames after the hp actually moves.  Any deferral
-- has to be measured against the numerals, not against the hp.
--
-- What this does NOT establish, and what the next attempt needs: the
-- frame a damage numeral for that same hit becomes visible.  Three
-- different signals were watched and none fired anywhere near f74 --
--   * w7e6316, the numeral vram-upload request (GfxCmd_0b,
--     btlgfx_main.asm:24702/:24786): fires at f10, f362, f759, a cadence
--     that lines up with none of the hits at f74/f479/f794;
--   * w7e631a-d, the single-numeral enable bytes (:24779);
--   * w7e7b3f,x and the w7e7b49,x display frame counter on the MASS
--     path (DrawDmgNumSprites, :6092-6119).
-- Something else is carrying monster-side numerals in this fixture.
-- Settle that first -- find the write that actually puts a number on
-- screen -- then measure the gap, and only then decide whether there is
-- one worth deferring.  If the reveal and the numeral turn out to share
-- a frame, the honest answer is that the playtester is perceiving
-- something else (the spell wind-up between "action starts" and "damage
-- lands" is ~29 frames here, which is itself a candidate).
--
-- Instrumentation notes worth keeping:
--   * monster weak elements are $3be8+slot*2 and revealed elements
--     $3e91+slot*2.  Ot6Chip reads them as $3be0,y / $3e89,y with y =
--     the ENTITY offset 8+slot*2 -- the same byte.  Adding the 8 twice
--     lands in party hp and the probe silently measures nothing.
--   * make EVERY live monster weak rather than the one you expect the
--     cursor to pick; the reveal answers the timing question whoever
--     lands the hit.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local ST = { spell = 0x0e, target = 0x38 }
local SPELL_FIRE = 0x00
local QMARK, FIRE_GLYPH = 0xbf, 0xeb

local actor, frames = nil, 0
local maskFrame, numFrame, glyphFrame = nil, nil, nil
local numAfterMask = nil          -- the numeral belonging to THIS hit
local hpDropFrame, hp0 = nil, nil
local lastHp = {}
local target
local events = {}

local function st() return H.readByte(0x7bc2) end
local function present(slot) return (H.readByte(0x3aa8 + slot*2) & 1) == 1 end

local SPELLBASE = { [0] = 0x0000, [1] = 0x013c, [2] = 0x0278, [3] = 0x03b4 }
local function magicCursor(slot, spellId)
  local base = 0x2092 + SPELLBASE[slot]
  for i = 0, 53 do
    if H.readByte(base + i*4) == spellId then
      local r, c = i // 2, i % 2
      local scroll = (r <= 3) and 0 or math.min(r - 3, 0x17)
      H.writeByte(0x8913 + slot, scroll)
      H.writeByte(0x8917 + slot, c)
      H.writeByte(0x891b + slot, r - scroll)
      return true
    end
  end
  return false
end

-- the four weakness cells on the target's hud line
local function wcell(slot, k) return H.readByte(H.shadowLine(slot) + 6 + k*2) end
local function anyRevealedGlyph(slot)
  for k = 0, 3 do if wcell(slot, k) == FIRE_GLYPH then return true end end
  return false
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.driveUntil(function()
    if H.readByte(0x7bca) == 0 then return false end
    return H.readByte(0x3ed8 + (H.readByte(0x62ca) & 3)*2) == 0
  end, 8000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "terra holds the menu"),
  H.call(function()
    actor = H.readByte(0x62ca) & 3
    for slot = 0, 5 do
      if present(slot) then target = target or slot end
    end
    H.assertEq(target ~= nil, true, "a monster is on the field")
    H.log(string.format("actor slot %d, target monster slot %d", actor, target))
    -- make EVERY live monster fire-weak and unrevealed, with hp to
    -- survive the hit: which one the target cursor lands on is not worth
    -- fighting, and a reveal on any of them answers the timing question
    for slot = 0, 5 do
      if present(slot) then
        -- monster weak elements are $3be8+slot*2 and revealed elements
        -- $3e91+slot*2 (battle_reveal.lua: slots 2/3 = $3bec/$3bee and
        -- $3e95/$3e97).  Ot6Chip reads them as $3be0,y / $3e89,y with y
        -- = the ENTITY offset 8+slot*2, which is the same byte -- adding
        -- the 8 twice lands in party hp instead.
        H.writeByte(0x3be8 + slot*2, 0x01)       -- weak: fire
        H.writeByte(0x3e91 + slot*2, 0x00)       -- nothing revealed yet
        H.writeWord(0x3bfc + slot*2, 4000)
      end
    end
    H.writeByte(0x3e9c + actor*2, 0)             -- no boost in play
    H.writeByte(0x3e9d + actor*2, 0)
    H.writeWord(0x3c08 + actor*2, 99)
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    local s1 = 0x3ee4 + actor*2
    H.writeByte(s1, H.readByte(s1) & 0xf7)       -- clear magitek
    for i = 0, 3 do H.writeByte(0x202e + actor*12 + i*3, 0x02) end
    -- watch every monster's reveal mask ($3e91-$3e9b, odd bytes of the
    -- $3e88 pairs -- entity offset 8+slot*2)
    emu.addMemoryCallback(function(addr, v)
      if v ~= 0 and not maskFrame then
        maskFrame = frames
        events[#events+1] = string.format("f%05d reveal mask %04x -> %02x",
          frames, addr & 0xffff, v)
      end
    end, emu.callbackType.write, 0x7e3e91, 0x7e3e9b)
    -- w7e631a..d are the four numeral threads' enable bytes: GfxCmd_0b
    -- writes `ora #$01 ; enable numeral` (btlgfx_main.asm:24779) and the
    -- display loop clears them when the numeral expires (:5654).  This
    -- is "a number is actually on screen", which w7e6316 (a vram-upload
    -- request) is not.
    emu.addMemoryCallback(function(_, v)
      if v ~= 0 then
        if not numFrame then numFrame = frames end
        -- the numerals that matter are the ones for THIS hit: earlier
        -- ones belong to whatever the monsters were doing already
        if maskFrame and not numAfterMask then numAfterMask = frames end
        if #events < 40 then
          events[#events+1] = string.format("f%05d damage numeral staged", frames)
        end
      end
    end, emu.callbackType.write, 0x7e631a, 0x7e631d)
    -- the MASS numeral path (GfxCmd_03 / DrawDmgNumSprites,
    -- btlgfx_main.asm:6092): w7e7b3f,x per target, cleared on expiry at
    -- :6111.  Monster-side damage numerals ride this one, not $631a.
    emu.addMemoryCallback(function(addr, v)
      if v ~= 0 and #events < 60 then
        events[#events+1] = string.format("f%05d MASS numeral on (%04x=%02x)",
          frames, addr & 0xffff, v)
        if maskFrame and not numAfterMask then numAfterMask = frames end
      end
    end, emu.callbackType.write, 0x7e7b3f, 0x7e7b48)
    -- w7e7b49,x is the per-target numeral frame counter, incremented on
    -- every frame a numeral is actually being drawn and cleared when it
    -- expires after 64 frames (btlgfx_main.asm:6108/:6113/:6119).  Its
    -- first tick from 0 is the frame the number appears on screen.
    emu.addMemoryCallback(function(addr, v)
      if v == 1 and #events < 60 then
        events[#events+1] = string.format("f%05d NUMERAL VISIBLE (%04x)",
          frames, addr & 0xffff)
        if maskFrame and not numAfterMask then numAfterMask = frames end
      end
    end, emu.callbackType.write, 0x7e7b49, 0x7e7b52)
    -- what actually executed, so numerals can be attributed
    emu.addMemoryCallback(function(_, v)
      if v ~= 0xff and #events < 60 then
        events[#events+1] = string.format("f%05d EXEC attack id %02x", frames, v)
      end
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  H.driveUntil(function() return st() == ST.spell end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "spell list open"),
  H.call(function()
    H.assertEq(magicCursor(actor, SPELL_FIRE), true, "cursor parked on Fire")
  end),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target select up"),
  H.call(function()
    local hidden = true
    for slot = 0, 5 do
      if present(slot) and anyRevealedGlyph(slot) then hidden = false end
    end
    H.assertEq(hidden, true,
      "positive control: weaknesses start hidden ('?')")
  end),
  H.driveUntil(function() return st() ~= ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target confirmed"),
  -- from here on, count frames and watch the glyph flip
  H.waitUntilSoft(function()
    frames = frames + 1
    local shown = false
    for slot = 0, 5 do
      if present(slot) and anyRevealedGlyph(slot) then shown = true end
    end
    if not glyphFrame and shown then
      glyphFrame = frames
      events[#events+1] = string.format("f%05d hud glyph flips '?' -> fire", frames)
    end
    -- per-monster hp, logged on every change
    for slot = 0, 5 do
      local h = H.readWord(0x3bfc + slot*2)
      if lastHp[slot] and lastHp[slot] ~= h and #events < 60 then
        events[#events+1] = string.format("f%05d monster %d hp %d -> %d",
          frames, slot, lastHp[slot], h)
      end
      lastHp[slot] = h
    end
    return frames >= 800
  end, 2400, "timeline captured", 1),
  H.call(function()
    for _, e in ipairs(events) do H.log(e) end
    H.log(string.format("mask frame %s, hud glyph frame %s, first numeral frame %s",
      tostring(maskFrame), tostring(glyphFrame), tostring(numFrame)))
    H.log(string.format("numeral for THIS hit: %s, hp drop: %s",
      tostring(numAfterMask), tostring(hpDropFrame)))
    if maskFrame and numAfterMask then
      H.log(string.format("GAP mask -> its numeral: %d frames",
        numAfterMask - maskFrame))
    end
    if glyphFrame and numAfterMask then
      H.log(string.format("GAP hud glyph -> its numeral: %d frames",
        numAfterMask - glyphFrame))
    end
  end),
})

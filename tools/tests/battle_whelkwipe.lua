-- @suite slow
-- battle_whelkwipe: the whelk head's retract cycle (monster entry/exit
-- FADE_DOWN/FADE_UP wipes) must render from vanilla's tiles only.
--
-- While DoMonsterEntryExit runs, the nmi flush writes the $01ee fill over
-- each live hud line instead of its cells, leaving the field map
-- word-identical to vanilla's for the whole animation; the shadow is
-- untouched, so the first flush afterward repaints the hud.  Loads
-- whelk_entry.mss, drives a passive Heal Force fight, and asserts the
-- field map cell-by-cell through both the FADE_DOWN and FADE_UP wipes.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"

local VR = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom

-- OT6-claimed font cells, read from the rom: 8 element icons, 16 hud
-- glyphs (the cell table precedes the glyph data), and $bf, the '?'
-- glyph weakness slots borrow.  During an entry/exit animation none of
-- these may be referenced by any field-map word.
local function claimedCharSet()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base + i - 1, ROM) ~= sig[i] then hit = false; break end
      end
      if hit then return base end
    end
    return nil
  end
  local icons = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                         0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  local bg    = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                         0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(icons ~= nil and bg ~= nil, true, "OT6 glyph data found in rom")
  local set = { [0xbf] = true }
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do
    set[c] = true
  end
  for k = 1, 16 do set[emu.read(bg - 17 + k, ROM)] = true end
  return set
end
local claimed = nil

local function fieldMapBase()             -- byte address of the field map
  local reg = H.readByte(0x897b)
  return ((reg - (reg % 4)) * 256) * 2
end

-- during-animation invariant: the field map sources no OT6 glyphs, and
-- every live hud line reads vanilla's $01ee junk fill
local function assertWipeVanilla(what)
  local base = fieldMapBase()
  for off = 0, 0x7fe, 2 do
    local lo, hi = emu.read(base + off, VR), emu.read(base + off + 1, VR)
    if (hi & 0x01) == 1 and claimed[lo] then
      error(string.format(
        "%s: field map word $%04x holds OT6 glyph char 1%02x (attr %02x)",
        what, (base + off) // 2, lo, hi), 0)
    end
  end
  for line = 0, 5 do
    local cur = H.readWord(H.shadowLine(line))
    if cur ~= 0 then
      for cell = 0, 4 do
        local w = emu.readWord((cur + cell) * 2, VR)
        if w ~= 0x01ee then
          error(string.format(
            "%s: veiled hud line %d cell %d at $%04x reads %04x, want 01ee",
            what, line, cell, cur + cell, w), 0)
        end
      end
    end
  end
end

-- trip wire on DoMonsterEntryExit (vanilla C2/E668); registered after
-- the savestate load, since loads do not detach callbacks
local trips = 0
local tripped = false
local function armTripWire()
  local addr = H.sym("DoMonsterEntryExit")
  emu.addMemoryCallback(function()
    if tripped then return end
    tripped = true
    trips = trips + 1
  end, emu.callbackType.exec, addr, addr)
end

-- passive driver: Heal Force every turn
local MENU = 0x7bca
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    mSeq, mIdx = { "a", "down", "down", "a", "a" }, 1
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0
    return { "b" }
  end
  return { "a" }
end
local pulseAge = 29
local function pulseTick()
  pulseAge = (pulseAge + 1) % 30
  if pulseAge == 0 then
    H.setPad(policyPulse())
  elseif pulseAge == 6 then
    H.setPad({})
  end
end

-- one transition: drive to the trip, then hold the invariant every
-- frame until the veil byte clears
local function transition(k, what)
  local checked = 0
  return {
    H.driveUntil(function() return trips >= k end, 9000, {
      H.call(pulseTick),
    }, what .. " begins"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.readByte(0x57be), 1, what .. ": veil raised")
    end),
    H.driveUntil(function()
      return H.readByte(0x57be) == 0
    end, 1200, {
      H.call(function()
        assertWipeVanilla(what)
        checked = checked + 1
      end),
    }, what .. " completes (veil drops)"),
    H.call(function()
      H.log(string.format("%s: wipe held vanilla-clean for %d frames",
        what, checked))
      H.assertEq(checked > 60, true, what .. ": animation actually ran")
      tripped = false              -- rearm for the next transition
    end),
  }
end

local aPhase = 0
local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function()
    return H.battleLoadStarted() and H.monstersPresent() > 0
  end, 2600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  -- The whelk's scripted battle intro dialogue re-uploads the small font,
  -- clobbering OT6's glyph tiles; the hud is veiled while it is up.  The
  -- first battle menu opening (7bca) means the dialogue is closed, the font
  -- is restored, and the hud is un-veiled.
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x64d5) == 0 and H.fieldHudPresent()
  end, 4000, {
    H.call(function() if H.readByte(0x7bca) == 0 then H.setPad({ "a" }) else H.setPad({}) end end),
    H.waitFrames(10), H.release(), H.waitFrames(10),
  }, "whelk intro dialogue dismissed, menu up, hud font whole"),
  H.waitFrames(120),
  H.call(function()
    claimed = claimedCharSet()
    local actor = H.readByte(0x62ca) & 3
    H.log(string.format("menu owner at settle: slot %d, char id $%02x",
      actor, H.readByte(0x3ed8 + actor * 2)))
    H.assertEq(H.formationHas({ [0x0134] = true }), true, "whelk head fight")
    H.assertEq(H.fieldHudPresent(), true, "hud up before the retract")
    H.assertEq(H.readByte(0x57be), 0, "veil idle before the retract")
    armTripWire()
  end),
}
for _, s in ipairs(transition(1, "FADE_DOWN (head hides)")) do
  steps[#steps + 1] = s
end
steps[#steps + 1] = H.waitFrames(60)
steps[#steps + 1] = H.call(function()
  -- the head left with the effect: its shield line must be gone
  H.assertEq(H.fieldHudPresent(), false, "hud line gone with the head")
  H.screenshot("whelkwipe_hidden")
end)
for _, s in ipairs(transition(2, "FADE_UP (head returns)")) do
  steps[#steps + 1] = s
end
steps[#steps + 1] = H.waitFrames(60)
steps[#steps + 1] = H.call(function()
  H.assertEq(H.fieldHudPresent(), true, "hud repainted after the return")
  H.glyphCanary()
  H.screenshot("whelkwipe_returned")
end)

H.run({ maxFrames = 30000 }, steps)

-- probe_whelkwipe.lua -- frame-by-frame capture of the whelk head's
-- hide/show transition (monster entry/exit FADE_DOWN/FADE_UP wipes).
--
-- The measurement instrument behind the whelk-wipe bug hunt: drive the
-- whelk fight passively (Heal Force every turn, whelkbal's settle
-- discipline), trip an exec callback on DoMonsterEntryExit (vanilla
-- C2/E668, byte-identical on base and ot6 images), then screenshot EVERY
-- frame of the transition while diffing the battle-field BG3 tilemap
-- (vram words $5400-$57ff) and the small-font tile region (vram words
-- $5800-$5fff) against pre-transition shadows.  Two transitions are
-- captured: the first FADE_DOWN (head hides) and the following FADE_UP
-- (head returns).
--
-- Run against build/ot6.sfc as-is (TAG "wo"); for the base-ROM ground
-- truth sed TAG to "wb" and point the runner at
-- build/states/base_rom_for_comparison.sfc.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local TAG = "wo"
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local BURST = 150                  -- frames captured per transition
local SHOT_EVERY = 1               -- screenshot cadence inside a burst

-- ------------------------------------------------------------ trip wire --
-- DoMonsterEntryExit entry point (vanilla bank-C2 code, verified
-- byte-identical in both images).  Fires once per entry/exit animation.
-- Registered AFTER the savestate load (loads can detach memory callbacks).
local TRIP_PC = 0xC2E668
local trips = {}                   -- { {frame=, type=, mask=}, ... }
local tripped = false
local function armTripWire()
  emu.addMemoryCallback(function()
    if tripped then return end    -- one latch per burst; rearmed after
    tripped = true
    local ptr = H.readWord(0x76)  -- battle script command pointer
    trips[#trips + 1] = {
      frame = H.frame,
      type = H.readByte(ptr + 1), -- entry/exit type (8=FADE_DOWN 9=FADE_UP)
      mask = H.readByte(ptr + 2), -- affected monster mask
    }
  end, emu.callbackType.exec, TRIP_PC, TRIP_PC)
end

-- ------------------------------------------------------- vram shadowing --
local VR = emu.memType.snesVideoRam
local MAP0 = 0x5400 * 2            -- battle-field BG3 tilemap, byte address
local FONT0 = 0x5800 * 2           -- small font tiles, byte address
local mapShadow, fontShadow = {}, {}

local function snapShadows()
  for i = 0, 0x3ff do mapShadow[i] = emu.readWord(MAP0 + i * 2, VR) end
  for i = 0, 0x7ff do fontShadow[i] = emu.readWord(FONT0 + i * 2, VR) end
end

-- diff the live map against the shadow; log up to `cap` changed words and
-- update the shadow.  returns the change count.
local function diffMap(label, cap)
  local n, lines = 0, {}
  for i = 0, 0x3ff do
    local v = emu.readWord(MAP0 + i * 2, VR)
    if v ~= mapShadow[i] then
      n = n + 1
      if n <= cap then
        lines[#lines + 1] = string.format("%04x:%04x>%04x",
          0x5400 + i, mapShadow[i], v)
      end
      mapShadow[i] = v
    end
  end
  if n > 0 then
    H.log(string.format("%s map words changed=%d %s%s", label, n,
      table.concat(lines, " "), n > cap and " ..." or ""))
  end
  return n
end

local function diffFont(label, cap)
  local n, lines = 0, {}
  for i = 0, 0x7ff do
    local v = emu.readWord(FONT0 + i * 2, VR)
    if v ~= fontShadow[i] then
      n = n + 1
      if n <= cap then
        lines[#lines + 1] = string.format("%04x:%04x>%04x",
          0x5800 + i, fontShadow[i], v)
      end
      fontShadow[i] = v
    end
  end
  if n > 0 then
    H.log(string.format("%s FONT words changed=%d %s%s", label, n,
      table.concat(lines, " "), n > cap and " ..." or ""))
  end
  return n
end

-- ------------------------------------------------------- passive driver --
-- whelkbal's menu-episode machine, pinned to the Heal Force sequence
-- (self-target heal: never hits the head or shell, so the only
-- transitions are the shell's own timer cycle).
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

-- pulse cadence carrier: one policyPulse per 30 frames, pad held 6
local pulseAge = 29                -- fire on the first frame
local function pulseTick()
  pulseAge = (pulseAge + 1) % 30
  if pulseAge == 0 then
    H.setPad(policyPulse())
  elseif pulseAge == 6 then
    H.setPad({})
  end
end

-- ------------------------------------------------------ burst capturing --
local function burst(k)
  local i = 0
  local trip = nil
  return {
    tick = function()
      if i == 0 then
        H.setPad({})
        trip = trips[#trips]
        H.log(string.format(
          "burst %d armed: trip frame=%d type=%02x mask=%02x",
          k, trip.frame, trip.type, trip.mask))
      end
      local pre = string.format("%s_t%d_f%03d", TAG, k, i)
      if i % SHOT_EVERY == 0 then H.screenshot(pre) end
      H.log(string.format(
        "%s state 201e=%02x 61ab=%02x 2f2f=%02x 7bca=%02x 57b9=%02x",
        pre, H.readByte(0x201e), H.readByte(0x61ab),
        H.readByte(0x2f2f), H.readByte(MENU), H.readByte(0x57b9)))
      diffMap(pre, 20)
      diffFont(pre, 20)
      i = i + 1
      if i >= BURST then
        tripped = false            -- rearm the trip wire for the next one
        return "done"
      end
      return "frame"
    end,
  }
end

-- ------------------------------------------------------------ the run --
local aPhase, strayN = 0, 0
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  -- walk into the whelk trigger (battle_dlgmenu's doorstep walk; the
  -- route is one step, so any battle that comes up is the whelk)
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
  H.waitFrames(240),
  H.call(function()
    local sp = {}
    for i = 0, 5 do
      sp[#sp + 1] = string.format("%04X", H.readWord(0x57c0 + i * 2))
    end
    H.log("formation words: " .. table.concat(sp, " "))
    armTripWire()                  -- battle-load entrances are behind us
    snapShadows()
    H.screenshot(TAG .. "_baseline")
  end),
  -- drive passively until the first transition (the shell's timer hide)
  H.driveUntil(function() return #trips >= 1 end, 9000, {
    H.call(function()
      pulseTick()
      -- track quiet-time tilemap churn so burst diffs read against a
      -- fresh shadow (menus repaint rows constantly; only keep count)
      if H.frame % 32 == 0 then
        for i = 0, 0x3ff do mapShadow[i] = emu.readWord(MAP0 + i * 2, VR) end
        for i = 0, 0x7ff do fontShadow[i] = emu.readWord(FONT0 + i * 2, VR) end
      end
    end),
  }, "first transition (hide)"),
  burst(1),
  -- and until the second (the head fades back in)
  H.driveUntil(function() return #trips >= 2 end, 9000, {
    H.call(function()
      pulseTick()
      if H.frame % 32 == 0 then
        for i = 0, 0x3ff do mapShadow[i] = emu.readWord(MAP0 + i * 2, VR) end
        for i = 0, 0x7ff do fontShadow[i] = emu.readWord(FONT0 + i * 2, VR) end
      end
    end),
  }, "second transition (show)"),
  burst(2),
  H.call(function()
    for k, t in ipairs(trips) do
      H.log(string.format("trip %d: frame=%d type=%02x mask=%02x",
        k, t.frame, t.type, t.mask))
    end
    H.log("capture complete")
  end),
})

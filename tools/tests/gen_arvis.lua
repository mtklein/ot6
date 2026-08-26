-- gen_arvis.lua -- win the Whelk and ride the esper scene to Terra's
-- wake-up in Arvis's house.  From whelk_entry.mss (party calm at (42,6),
-- map 41): step onto the trigger at (42,5), page the guard dialogs, then
-- play the Whelk fight.  Head up: everyone attacks the head; at one
-- shield remaining, TERRA casts TekMissile to break it.  Head hidden:
-- the party casts Heal Force.  The event sets switch $0135 ($1EA6 bit
-- $20).  North of the fight, (41..43, y=4) exits to the Tritoch chamber
-- (map 0x2A); the trigger at (87,12) starts the esper scene (Tritoch
-- spared), ending with Terra waking in Arvis's house (map 30).  Saves
-- arvis_wake.mss at the first calm control point.
local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/whelk_entry.mss.lua"

-- goal-fight signature: 0x134 "Head" is the distinctive word; $57C0 is
-- battle scratch, so gate every read on battleLoadStarted
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- the esper zap (event battle 77) contains Tritoch, species 0x114/0x115/
-- 0x144 depending on version; spare them all, since the set-piece ends
-- itself
local TRITOCH = { 0x0114, 0x0115, 0x0144 }

-- pred factory: n consecutive calm frames (control, at rest), optionally
-- with an extra condition, so a one-frame control blip cannot generate a
-- state
local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- pred factory: n consecutive frames of a running event script, so one-frame
-- event-PC pulses from map setup do not count as the scene
local function eventFor(n)
  local cnt = 0
  return function()
    cnt = H.eventRunning() and cnt + 1 or 0
    return cnt >= n
  end
end

-- FF3us text encoding, enough for character names
local function decodeName(addr, len)
  local s = ""
  for i = 0, len - 1 do
    local b = H.readByte(addr + i)
    if     b >= 0x80 and b <= 0x99 then s = s .. string.char(b - 0x80 + 65)
    elseif b >= 0x9A and b <= 0xB3 then s = s .. string.char(b - 0x9A + 97)
    elseif b >= 0xB4 and b <= 0xBD then s = s .. string.char(b - 0xB4 + 48)
    elseif b == 0xBE then s = s .. "!"
    elseif b == 0xBF then s = s .. "?"
    elseif b == 0xFF then s = s .. " "
    else s = s .. "."
    end
  end
  return s
end

local CMDNAME = {
  [0x00]="Fight", [0x01]="Item", [0x02]="Magic", [0x03]="Morph",
  [0x04]="Revert", [0x05]="TresHnt", [0x06]="Capture", [0x07]="SwdTech",
  [0x08]="Throw", [0x09]="Tools", [0x0A]="Blitz", [0x0B]="Runic",
  [0x0C]="Lore", [0x0D]="Sketch", [0x0E]="Control", [0x0F]="Slot",
  [0x10]="Rage", [0x11]="Leap", [0x12]="Mimic", [0x13]="Dance",
  [0x14]="Row", [0x15]="Def", [0x16]="Jump", [0x17]="X-Magic",
  [0x18]="GPRain", [0x19]="Summon", [0x1A]="Health", [0x1B]="Shock",
  [0x1C]="Possess", [0x1D]="Magitek", [0xFF]="--",
}
local function cmdName(b) return CMDNAME[b] or string.format("%02X?", b) end

-- roster + command lists: character data blocks ($1600 + 37n; commands at
-- +$16), party/battle-slot byte $1850+n, and the battle command table at
-- $202E (12 bytes/char, 4 x [cmd,cmd,targeting]; battle scratch, so on the
-- field it shows the previous battle's menus rather than the next)
local function logPartyDump()
  H.log(string.format("chars available $1EDC=%04X $1EDE=%04X",
    H.readWord(0x1edc), H.readWord(0x1ede)))
  for c = 0, 15 do
    local pb = H.readByte(0x1850 + c)
    if (pb & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      local cmds = {}
      for i = 0, 3 do cmds[i + 1] = cmdName(H.readByte(base + 0x16 + i)) end
      H.log(string.format(
        "char %2d '%s' actor=%02X level=%d party-byte=%02X commands=%s/%s/%s/%s",
        c, decodeName(base + 2, 6), H.readByte(base), H.readByte(base + 8),
        pb, cmds[1], cmds[2], cmds[3], cmds[4]))
    end
  end
  for slot = 0, 3 do
    local base = 0x202e + 12 * slot
    local hex = {}
    for i = 0, 11 do hex[i + 1] = string.format("%02X", H.readByte(base + i)) end
    H.log(string.format("$%04X (battle cmd slot %d, stale on field): %s",
      base, slot, table.concat(hex, " ")))
  end
end

local aPhase = 0

local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone/hidden)
local SPEC  = 0x57c0               -- formation species words
local CHID  = 0x3ed8               -- char id, +slot*2 (0 = terra)

local hs, terra                    -- head slot, terra's char slot
local function broken() return H.readByte(TIMER + hs * 2) > 0 end
local function shields() return H.readByte(SHLD + hs * 2) end
local function headAlive()
  return (H.readByte(ALIVE + hs * 2) & 1) == 1
     and (H.readByte(MSTAT + hs * 2) & 0xc2) == 0
end

local lastShow, lastUp = nil, nil
local hitsSinceShow = 0
local lastHp, lastSh = nil, nil
local FRESH = 1400
local function observeHead()
  if hs == nil then return end
  local up = headAlive()
  if up and lastUp == false then
    lastShow, hitsSinceShow = H.frame, 0
    lastHp, lastSh = nil, nil
  end
  lastUp = up
  if up then
    local hp, sh = H.readWord(MHP + hs * 2), shields()
    if (lastHp and hp < lastHp) or (lastSh and sh < lastSh) then
      hitsSinceShow = hitsSinceShow + 1
    end
    lastHp, lastSh = hp, sh
  end
end

local function seqFor(actor)
  local freshWindow = headAlive() and lastShow
    and (H.frame - lastShow) < FRESH and hitsSinceShow < 2
  if not freshWindow then
    if actor == terra then
      return { "a", "right", "a", "a" }                        -- Heal Force
    end
    return { "a", "down", "down", "a", "a" }                   -- Heal Force
  end
  if actor == terra and not broken() and shields() == 1 then
    return { "a", "down", "down", "down", "right", "a", "a" }  -- TekMissile
  end
  return { "a", "a", "a" }                            -- first beam, head
end

-- Battle menus ignore input during their open animation, so presses only
-- start after the menu flag holds 4 consecutive pulses; when no menu is up,
-- A is edge-tapped every other pulse.
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local function policyPulse()
  if hs == nil or H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    local actor = H.readByte(ACTOR)
    mSeq, mIdx = seqFor(actor), 1
    H.log(string.format(
      "whelk cast f%d actor=%d seq=%s | head hp=%d sh=%d tmr=%d up=%s | party %d/%d/%d",
      H.frame, actor, table.concat(mSeq, ","),
      H.readWord(MHP + hs * 2), shields(), H.readByte(TIMER + hs * 2),
      tostring(headAlive()),
      H.readWord(0x3bf4), H.readWord(0x3bf6), H.readWord(0x3bf8)))
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0              -- back out; rebuild from scratch
    return { "b" }
  end
  return { "a" }
end

-- Slots are found on the first open menu (formation words and char ids
-- are battle scratch, read only once the battle module owns them); until
-- then the no-menu branch pages the opening dialog.  Terminates on battle
-- teardown; the caller asserts the whelk-done switch to distinguish a win
-- from a game-over teardown.
local function winWhelk()
  return H.driveUntil(function()
    return hs ~= nil and not H.battleLoadStarted()
  end, 40000, {
    H.call(function()
      -- $7bca is field-written scratch through the load, so this arms
      -- early and stamps lastShow before the first real menu, making the
      -- opening spread come out as heals.
      if hs == nil and H.battleLoadStarted() and H.monstersPresent() > 0
         and H.readByte(MENU) ~= 0 then
        for slot = 0, 5 do
          if H.readWord(SPEC + slot * 2) == 0x0134 then hs = slot end
        end
        for c = 0, 3 do
          if H.readByte(CHID + c * 2) == 0 then terra = c end
        end
        H.assertEq(hs ~= nil and terra ~= nil, true,
          "whelk head + terra found at the first menu")
        H.log(string.format(
          "whelk armed: head slot %d (hp=%d sh=%d), terra char slot %d",
          hs, H.readWord(MHP + hs * 2), shields(), terra))
        -- the boot state of the window tracker: the head is up at battle
        -- start, and that opening spread counts as a fresh window
        lastUp, lastShow, hitsSinceShow = true, H.frame, 0
      end
      observeHead()
      H.setPad(policyPulse())
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "whelk beaten (tutorial policy)")
end

H.run({ maxFrames = 120000 }, {
  H.loadState(ENTRY),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "entry point control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 41, "boot map is the Narshe mines")
    H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true, "at the entry point (42,6)")
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0, "whelk-done switch clear")
  end),

  -- stepping onto (42,5) force-walks the party to (42,7) and opens the
  -- guard dialogs; a random encounter on the step is fought inline by the
  -- same edge-tapped A; the goal fight is left for whelk()/winWhelk.
  H.driveUntil(function() return whelk() end, 8000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelk() then H.setPad({}); return end       -- pred fires next frame
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then                        -- $0B6E then $0B6F
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),

  -- Real menus, real target defaults, real turns; the retract cycle sets
  -- the fight's pace and Heal Force spends the hidden phases.
  H.logStep("whelk battle up; playing it (tutorial policy)"),
  winWhelk(),
  H.call(function()
    H.setPad({})
    H.log(string.format("whelk fight torn down at frame %d", H.frame))
  end),

  -- event epilogue: fade back in, switch $0135 set, control returns
  H.advanceStory(calm(30), 3000, { playBattles = true }),
  H.call(function()
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0x20, "whelk-done switch $0135 set")
    H.log(string.format("whelk won; back on field at (%d,%d) map=%d",
      H.fieldX(), H.fieldY(), H.mapId()))
    H.screenshot("arvis_whelk_won")
  end),

  -- north through the y=4 exit line into the Tritoch chamber
  H.navTo(42, 4, { arrive = function() return H.mapId() == 0x2A end,
                   maxFrames = 6000, playBattles = true }),
  H.waitUntil(calm(30), 900, "tritoch chamber control"),
  H.call(function()
    H.assertEq(H.mapId(), 0x2A, "in the tritoch chamber (map 0x2A)")
    H.log(string.format("chamber entry at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("arvis_chamber")
  end),

  -- approach the esper: the single trigger at (87,12) starts the scene
  H.navTo(87, 12, { arrive = eventFor(30), maxFrames = 12000, playBattles = true }),
  H.logStep("tritoch scene fired; hands off"),

  -- the long automatic stretch: zap battle (spared), flashback, wake-up.
  -- done = calm on a map that is neither mines (41) nor chamber (42)
  H.advanceStory(calm(60, function()
    return H.mapId() ~= 41 and H.mapId() ~= 42
  end), 45000, { spare = TRITOCH, playBattles = true }),

  H.call(function()
    H.log(string.format("awake: map=%d (0x%X) at (%d,%d)",
      H.mapId(), H.mapId(), H.fieldX(), H.fieldY()))
    H.screenshot("arvis_wake")
  end),
  H.saveState("arvis_wake.mss"),
  H.call(logPartyDump),
  H.logStep(function()
    return string.format("arvis_wake generated at frame %d", H.frame)
  end),
})

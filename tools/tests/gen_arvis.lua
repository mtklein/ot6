-- gen_arvis.lua -- WIN the Whelk and ride the esper scene to Terra's wake-up
-- in Arvis's house.  From whelk_doorstep.mss (party calm at (42,6), map 41):
-- step onto the trigger at (42,5), edge-tap the guard dialogs $0B6E/$0B6F,
-- then clearBattle the Whelk (formation words 0x0100/0x0134 -- NO spare list
-- this time, the win is the point).  The event epilogue sets switch $0135
-- ($1EA6 bit $20, asserted).  North of the fight, tiles (41..43, y=4) exit
-- to map 0x2A at (86,28), the Tritoch chamber; the single event trigger at
-- (87,12) starts the long automatic esper scene: the party is zapped
-- (scripted battle 77 -- Tritoch, spared so it plays itself out), flashback,
-- and Terra wakes alone in Arvis's house (map 30).  advanceStory rides all
-- of it out.  Emits arvis_wake.mss at the first calm control point, plus
-- progress screenshots, and logs the roster + command lists the fixture has.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOORSTEP = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"

-- goal-fight signature (same as gen_whelk): 0x134 "Head" is the distinctive
-- word; $57C0 is battle scratch, so gate every read on battleLoadStarted
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- the esper zap (event battle 77) contains Tritoch -- species 0x114/0x115/
-- 0x144 depending on version; spare them all, the set-piece ends itself
local TRITOCH = { 0x0114, 0x0115, 0x0144 }

-- pred factory: n consecutive calm frames (control, at rest), optionally
-- with an extra condition -- one-frame control blips mustn't mint states
local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- pred factory: n consecutive frames of a running event script (one-frame
-- event-PC pulses from map plumbing mustn't count as the scene)
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
  [0x04]="Revert", [0x05]="Steal", [0x06]="Capture", [0x07]="SwdTech",
  [0x08]="Throw", [0x09]="Tools", [0x0A]="Blitz", [0x0B]="Runic",
  [0x0C]="Lore", [0x0D]="Sketch", [0x0E]="Control", [0x0F]="Slot",
  [0x10]="Rage", [0x11]="Leap", [0x12]="Mimic", [0x13]="Dance",
  [0x14]="Row", [0x15]="Def", [0x16]="Jump", [0x17]="X-Magic",
  [0x18]="GPRain", [0x19]="Summon", [0x1A]="Health", [0x1B]="Shock",
  [0x1C]="Possess", [0x1D]="Magitek", [0xFF]="--",
}
local function cmdName(b) return CMDNAME[b] or string.format("%02X?", b) end

-- roster + command lists: character data blocks ($1600 + 37n; commands at
-- +$16, battle_main.asm), party/battle-slot byte $1850+n, and the battle
-- command table at $202E (12 bytes/char -- 4 x [cmd,cmd,targeting]; battle
-- scratch, so on the field it shows the LAST battle's menus, not the next)
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

H.run({ maxFrames = 60000 }, {
  H.loadState(DOORSTEP),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "doorstep control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 41, "boot map is the Narshe mines")
    H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true, "at the doorstep (42,6)")
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0, "whelk-done switch clear")
  end),

  -- the deliberate step onto (42,5); the event force-walks us to (42,7) and
  -- opens the guard dialogs; a random encounter on the step is cleared
  -- inline, the goal fight is not (whelk() stops the loop; clearBattle wins it)
  H.driveUntil(function() return whelk() end, 2200, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelk() then H.setPad({}); return end       -- pred fires next frame
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
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

  -- WIN the fight: no spare list, kill-bits take the Whelk and its Head
  H.logStep("whelk battle up; winning it"),
  H.clearBattle(6000),

  -- event epilogue: fade back in, switch $0135 set, control returns
  H.advanceStory(calm(30), 3000),
  H.call(function()
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0x20, "whelk-done switch $0135 set")
    H.log(string.format("whelk won; back on field at (%d,%d) map=%d",
      H.fieldX(), H.fieldY(), H.mapId()))
    H.screenshot("arvis_whelk_won")
  end),

  -- north through the y=4 exit line into the Tritoch chamber
  H.navTo(42, 4, { arrive = function() return H.mapId() == 0x2A end,
                   maxFrames = 3000 }),
  H.waitUntil(calm(30), 900, "tritoch chamber control"),
  H.call(function()
    H.assertEq(H.mapId(), 0x2A, "in the tritoch chamber (map 0x2A)")
    H.log(string.format("chamber entry at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("arvis_chamber")
  end),

  -- approach the esper: the single trigger at (87,12) starts the scene
  H.navTo(87, 12, { arrive = eventFor(30), maxFrames = 9000 }),
  H.logStep("tritoch scene fired; hands off"),

  -- the long automatic stretch: zap battle (spared), flashback, wake-up.
  -- done = calm on a map that is neither mines (41) nor chamber (42)
  H.advanceStory(calm(60, function()
    return H.mapId() ~= 41 and H.mapId() ~= 42
  end), 45000, { spare = TRITOCH }),

  H.call(function()
    H.log(string.format("awake: map=%d (0x%X) at (%d,%d)",
      H.mapId(), H.mapId(), H.fieldX(), H.fieldY()))
    H.screenshot("arvis_wake")
  end),
  H.saveState("arvis_wake.mss"),
  H.call(logPartyDump),
  H.logStep(function()
    return string.format("arvis_wake minted at frame %d", H.frame)
  end),
})

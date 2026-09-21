-- gen_arvis.lua -- win the Whelk and ride the esper scene to Terra's
-- wake-up in Arvis's house.  From whelk_entry.mss (party calm at (42,6),
-- map 41): step onto the trigger at (42,5), page the guard dialogs, then
-- play the Whelk fight.  Head up: everyone fires a Fire Beam at the head
-- boosted with the whole bank; at one shield remaining, TERRA fires
-- TekMissile to break it.  Head hidden: the party casts Heal Force, one
-- pip on it when the bank is at 2, so nobody ever ends a turn holding 3
-- (#246).  The event sets switch $0135 ($1EA6 bit
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
local MSTATE = 0x7bc2              -- battle menu state ($05 = command select)
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone/hidden)
local SPEC  = 0x57c0               -- formation species words
local CHID  = 0x3ed8               -- char id, +slot*2 (0 = terra)
local BP    = 0x3e9c               -- boost bank, +slot*2 (OT6_BP_CLASS)

local hs, terra                    -- head slot, terra's char slot
local function broken() return H.readByte(TIMER + hs * 2) > 0 end
local function shields() return H.readByte(SHLD + hs * 2) end
local function headAlive()
  return (H.readByte(ALIVE + hs * 2) & 1) == 1
     and (H.readByte(MSTAT + hs * 2) & 0xc2) == 0
end
local function bank(actor) return H.readByte(BP + actor * 2) end

-- The Magitek list, two columns filled row by row, so the same cells
-- serve Terra's eight beams and the soldiers' four: Fire Beam is the
-- first cell, Heal Force row 2 left, TekMissile row 3 right.  Measured
-- 2026-09-21 from the ExecCmd ledger in build/attempts/wt-whelk-boost/
-- probes/whelk_probe_old.log, where the old a,right,a,a fired Bolt Beam
-- ($84) at whatever the cursor sat on -- the shell, once the head hid,
-- and the shell answers any hit with Mega Volt.
local FIRE_BEAM  = { "a", "a", "a" }
local HEAL_FORCE = { "a", "down", "down", "a", "a" }
local TEKMISSILE = { "a", "down", "down", "down", "right", "a", "a" }

-- A beam planned while the head is up lands 170-890 frames later (the
-- same ledger: plan f9394, ExecCmd f9874), and the head hides again
-- 1200-1750 frames after it shows, with one or two beams landed; a beam
-- that lands after the hide hits the shell instead, and the shell's
-- counter Mega Volt is what killed both members of the old run.  So
-- beams are planned only inside the first FRESH frames of a show.
local lastShow, lastUp = nil, nil
local hitsSinceShow = 0
local lastHp, lastSh = nil, nil
local FRESH = 500
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

-- What this turn fires and how many pips go on it.  A beam takes the
-- whole bank (the boost-Fight default; R is live in the Magitek command
-- window, and one boost-3 Fire Beam took the head from 1500 to 0 in
-- build/attempts/wt-whelk-boost/probes/whelk_probe_boost.log).  A Heal
-- Force takes one pip when the bank is at 2: the pip that would otherwise
-- make 3 at the turn's end.  Both together keep every bank under 3, so
-- no member can fall holding the pips tools/audit_boost.py flags (#246).
local function turnFor(actor)
  local freshWindow = headAlive() and lastShow
    and (H.frame - lastShow) < FRESH and hitsSinceShow < 2
  local b = bank(actor)
  if not freshWindow then
    return "Heal Force", HEAL_FORCE, b >= 2 and 1 or 0
  end
  if actor == terra and not broken() and shields() == 1 then
    return "TekMissile", TEKMISSILE, math.min(3, b)
  end
  return "Fire Beam", FIRE_BEAM, math.min(3, b)
end

-- R raises the pending boost by one per press while the command window
-- is open (Ot6Boost, ot6_hud.asm), so the presses go in front of the cell.
local function seqFor(actor)
  local name, cell, boost = turnFor(actor)
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  for _, b in ipairs(cell) do seq[#seq + 1] = b end
  return seq, name, boost
end

-- The lib fight driver's battle-open and [death] lines (newFightDriver,
-- lib/ot6.lua) for a fight this file drives itself, so tools/audit_boost.py
-- sees the pips a member held when they fell and tools/audit_fenix.py the
-- fight a Fenix Down answered (#220).  Ticks count from the first frame the
-- battle table is live with monsters present.  The killer is the monster
-- action ExecCmd is running when the HP reaches 0 (its slot and the $b5/$b6
-- command and attack), the way the lib's hit ledger names one; a drop
-- with no monster action running is nobody's.
local function newDeathWatch(tag)
  local W = {}
  function W.reset()
    W.tick, W.opened, W.hp, W.said, W.act = 0, false, {}, {}, nil
  end
  W.reset()
  local execCmd, saveForMimic = H.sym("ExecCmd@battle_code"), H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x >= 8 and x < 20 and x % 2 == 0 then
      W.act = { slot = x // 2 - 4, cmd = H.readByte(0xB5), atk = H.readByte(0xB6) }
    end
  end, emu.callbackType.exec, execCmd, execCmd)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if W.act ~= nil and x // 2 - 4 == W.act.slot then W.act = nil end
  end, emu.callbackType.exec, saveForMimic, saveForMimic)
  function W.frame()
    if not H.battleLoadStarted() then W.reset(); return end
    if not W.opened and H.monstersPresent() == 0 then return end
    W.tick = W.tick + 1
    local pbp = {}
    for p = 0, 3 do pbp[#pbp + 1] = tostring(H.readByte(BP + p * 2)) end
    local party_bp = table.concat(pbp, ",")
    if not W.opened then
      W.opened = true
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("[%s] battle f+%d partyhp=%s party_bp=%s monsters=%d",
        tag, W.tick, table.concat(hp, ","), party_bp, H.monstersPresent()))
    end
    for e = 0, 3 do
      local hp, maxhp = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
      local last = W.hp[e]
      if last ~= nil and last ~= 0xFFFF and last > 0 and hp == 0 and maxhp > 0
         and not W.said[e] then
        W.said[e] = true
        local bp = H.readByte(BP + e * 2)
        local by = W.act and string.format("slot %d cmd $%02X atk $%02X",
          W.act.slot, W.act.cmd, W.act.atk) or "nobody (no monster action running)"
        H.log(string.format("[%s] [death] f+%d entity %d char %d from %d/%d by "
          .. "%s bp=%d party_bp=%s%s", tag, W.tick, e, H.readByte(CHID + e * 2),
          last, maxhp, by, bp, party_bp,
          bp >= 3 and string.format(" -- died holding %d BP", bp) or ""))
      elseif hp > 0 and hp ~= 0xFFFF then
        W.said[e] = nil
      end
      W.hp[e] = hp
    end
  end
  return W
end
local whelkWatch = newDeathWatch("whelk")

-- Battle menus ignore input during their open animation, so presses only
-- start after the menu flag holds 4 consecutive pulses; when no menu is up,
-- A is edge-tapped every other pulse.  The next member's window can open
-- before the flag ever reads closed, so the sequence is also rebuilt when
-- the window's owner changes, with the same 4-pulse settle.  A finished
-- sequence whose window is still the same owner's after 4 more pulses did
-- not take: B backs out and it is rebuilt.
local mStreak, mSeq, mIdx, mIdle, mNoMenu, mActor = 0, nil, 1, 0, 0, nil
local function policyPulse()
  if hs == nil or H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mIdle, mActor = 0, nil, 1, 0, nil
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  local actor = H.readByte(ACTOR)
  if mActor ~= nil and actor ~= mActor then
    mStreak, mSeq, mIdx, mIdle = 0, nil, 1, 0
  end
  mActor = actor
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    local name, boost
    mSeq, name, boost = seqFor(actor)
    mIdx = 1
    H.log(string.format(
      "whelk cast f%d actor=%d %s boost=%d bank=%d state=$%02X seq=%s | head hp=%d sh=%d tmr=%d up=%s | party %d/%d/%d",
      H.frame, actor, name, boost, bank(actor), H.readByte(MSTATE),
      table.concat(mSeq, ","),
      H.readWord(MHP + hs * 2), shields(), H.readByte(TIMER + hs * 2),
      tostring(headAlive()),
      H.readWord(0x3bf4), H.readWord(0x3bf6), H.readWord(0x3bf8)))
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mIdle = mIdle + 1
  if mIdle > 4 then
    H.log(string.format("whelk cast f%d actor=%d did not take (state=$%02X); backing out",
      H.frame, actor, H.readByte(MSTATE)))
    mSeq, mIdle = nil, 0
    return { "b" }
  end
  return {}
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
      whelkWatch.frame()
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
  -- the fight's pace, the bank goes on the beams and Heal Force spends
  -- the hidden phases.
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

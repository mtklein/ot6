-- gen_arvis.lua -- WIN the Whelk and ride the esper scene to Terra's wake-up
-- in Arvis's house.  From whelk_doorstep.mss (party calm at (42,6), map 41):
-- step onto the trigger at (42,5), edge-tap the guard dialogs $0B6E/$0B6F,
-- then BEAT the Whelk BY PLAYING IT (issue #75: zero state writes -- the
-- kill-bit clearBattle this used to call is gone).  The strategy is the
-- measured "tutorial" policy from whelkbal_run.lua, the designed line the
-- head's fire-weak add exists for (balance-metrics.md Measurement #2 + the
-- resistance re-check: 3/3 honest wins, ~6 beams + 1-2 teks):
--   * head up: everyone fires their first beam at the default target (the
--     head -- chips land, measured); when exactly ONE shield remains and
--     the head is not yet broken, TERRA's turn walks the 2x4 magitek grid
--     to TekMissile (3,1) for the 4th chip -> break -> the x2 window
--     finishes the fight.
--   * head hidden (the shell's retract cycle): spend the turn on Heal
--     Force (2,0) -- ANY attack would default into the shell and draw the
--     MegaVolt counter, the fight's whole danger budget (Terra KO is a
--     scripted game over; whelkbal's mixed-naive policy lost 5/5 to
--     exactly this).
-- The event epilogue sets switch $0135 ($1EA6 bit $20, asserted).  North
-- of the fight, tiles (41..43, y=4) exit to map 0x2A at (86,28), the
-- Tritoch chamber; the single event trigger at (87,12) starts the long
-- automatic esper scene: the party is zapped (scripted battle 77 --
-- Tritoch, spared so it plays itself out), flashback, and Terra wakes
-- alone in Arvis's house (map 30).  advanceStory rides all of it out
-- (honest=true -- no route battle is kill-bitted anywhere in this gen).
-- Emits arvis_wake.mss at the first calm control point, plus progress
-- screenshots, and logs the roster + command lists the fixture has.
local H = dofile("tools/tests/lib/ot6.lua")
local DOORSTEP = "build/states/whelk_doorstep.mss.lua"

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

-- ------------------------------------------------ the honest Whelk win --
-- Addresses and menu-episode discipline lifted from whelkbal_run.lua (the
-- instrument that measured this exact fight 3/3 winnable on this policy).
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 (READ-only
                                   -- here: $c2 = gone/hidden; the kill-bit
                                   -- WROTE bit7 -- this gen never does)
local SPEC  = 0x57c0               -- formation species words
local CHID  = 0x3ed8               -- char id, +slot*2 (0 = terra)

local hs, terra                    -- head slot, terra's char slot
local function broken() return H.readByte(TIMER + hs * 2) > 0 end
local function shields() return H.readByte(SHLD + hs * 2) end
local function headAlive()
  return (H.readByte(ALIVE + hs * 2) & 1) == 1
     and (H.readByte(MSTAT + hs * 2) & 0xc2) == 0
end

-- RETRACT-CYCLE DISCIPLINE (measured the expensive way, run 3 of this
-- gen): an attack queued while the head is up can still EXECUTE after the
-- retract -- the turn engine retargets it into the shell, and every shell
-- hit draws the MegaVolt counter.  whelkbal_run knew this ("queued attacks
-- retarget into the shell and eat counters") but its policy only keyed on
-- head-up-right-now; from a gauntlet-worn party that lost Terra at f5085
-- and ended in an unwinnable one-soldier loop: the survivor's beams
-- queued in each up-window, executed into the next hidden phase, and the
-- head sat at 63 HP for ten thousand frames while counters ground the
-- party down.  So attacks are gated on a FRESH window instead:
--   * lastShow marks the hidden->up edge; attacks only queue within
--     FRESH frames of it (a window runs ~1600 frames; queue latency is a
--     few hundred, so early casts land while the head is still out);
--   * hitsSinceShow counts observed head hp/shield drops since the edge;
--     the head retracts ON the 3rd hit (ai_script.asm _309: var>2 ->
--     hide), so from 2 on nothing more is queued -- the 3rd is already
--     in flight somewhere.
--   * everything else (head hidden, stale window, hit budget spent) is a
--     Heal Force turn: MegaVolt sweeps ~30-50 across the party and Heal
--     Force outheals it, but only while all three keep casting it.
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

-- Sequences run from the settled top command menu (cursor on MagiTek).
-- Cell coordinates: the soldiers' 4-cell list stages sparse -- Fire|Bolt /
-- Ice / Heal -- so their Heal Force is (2,0); TERRA's list is the full 2x4
-- grid (col 0 = Fire/Bolt/Ice/Heal, col 1 = specials), so HER Heal Force
-- is (3,0) and TekMissile (3,1).  whelkbal_run's "(2,0) for everyone" was
-- wrong for Terra -- that cell is her ICE BEAM, and casting it in a hidden
-- phase is a shell hit (run 3's first MegaVolt chain started exactly
-- there).
--   beam at default target        A A A
--   heal force  soldier (2,0)     A dn dn A A     (self-target default)
--   heal force  terra   (3,0)     A dn dn dn A A
--   tekmissile  terra   (3,1)     A dn dn dn rt A A
local function seqFor(actor)
  local freshWindow = headAlive() and lastShow
    and (H.frame - lastShow) < FRESH and hitsSinceShow < 2
  if not freshWindow then
    if actor == terra then
      return { "a", "down", "down", "down", "a", "a" }         -- Heal Force
    end
    return { "a", "down", "down", "a", "a" }                   -- Heal Force
  end
  if actor == terra and not broken() and shields() == 1 then
    return { "a", "down", "down", "down", "right", "a", "a" }  -- TekMissile
  end
  return { "a", "a", "a" }                            -- first beam, head
end

-- The menu-episode machine (bal_mines settle discipline, via whelkbal_run):
-- battle menus eat input during their open animation EVERY turn, so presses
-- only start after the menu flag holds 4 consecutive pulses; when no menu is
-- up, A is edge-tapped every other pulse (the opening battle dialog and the
-- shell's "Gruuu……" dialogs need it; on a running battle a stray A is inert).
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

-- STEP: play the Whelk to the win.  Slots are found on the first open menu
-- (the formation words and char ids are battle scratch -- they are only
-- read once the battle module demonstrably owns them); until then the
-- pulse machine's no-menu branch pages the opening dialog.  Terminates on
-- battle teardown; the caller asserts the whelk-done switch, which is what
-- separates a WIN from a game-over teardown.
local function winWhelk()
  return H.driveUntil(function()
    return hs ~= nil and not H.battleLoadStarted()
  end, 40000, {
    H.call(function()
      if hs == nil and H.readByte(MENU) ~= 0 then
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
        -- the boot state of the window tracker: the head is UP at battle
        -- start, and that opening spread counts as a fresh window
        lastUp, lastShow, hitsSinceShow = true, H.frame, 0
      end
      observeHead()
      H.setPad(policyPulse())
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "whelk beaten honestly (tutorial policy)")
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOORSTEP),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "doorstep control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 41, "boot map is the Narshe mines")
    H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true, "at the doorstep (42,6)")
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0, "whelk-done switch clear")
  end),

  -- the deliberate step onto (42,5); the event force-walks us to (42,7) and
  -- opens the guard dialogs.  A random encounter on the step is FOUGHT
  -- inline by the same edge-tapped A (honest; nothing on this one-step
  -- route should draw one); the goal fight is hands-off (whelk() stops the
  -- loop; winWhelk plays it).
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

  -- WIN the fight for real: the first honest boss kill in the mint chain's
  -- history.  Real menus, real target defaults, real turns; the retract
  -- cycle is the fight's clock and Heal Force spends the hidden phases.
  H.logStep("whelk battle up; playing it (tutorial policy)"),
  winWhelk(),
  H.call(function()
    H.setPad({})
    H.log(string.format("whelk fight torn down at frame %d", H.frame))
  end),

  -- event epilogue: fade back in, switch $0135 set, control returns
  H.advanceStory(calm(30), 3000, { honest = true }),
  H.call(function()
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0x20, "whelk-done switch $0135 set")
    H.log(string.format("whelk won; back on field at (%d,%d) map=%d",
      H.fieldX(), H.fieldY(), H.mapId()))
    H.screenshot("arvis_whelk_won")
  end),

  -- north through the y=4 exit line into the Tritoch chamber
  H.navTo(42, 4, { arrive = function() return H.mapId() == 0x2A end,
                   maxFrames = 6000, honest = true }),
  H.waitUntil(calm(30), 900, "tritoch chamber control"),
  H.call(function()
    H.assertEq(H.mapId(), 0x2A, "in the tritoch chamber (map 0x2A)")
    H.log(string.format("chamber entry at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("arvis_chamber")
  end),

  -- approach the esper: the single trigger at (87,12) starts the scene
  H.navTo(87, 12, { arrive = eventFor(30), maxFrames = 12000, honest = true }),
  H.logStep("tritoch scene fired; hands off"),

  -- the long automatic stretch: zap battle (spared), flashback, wake-up.
  -- done = calm on a map that is neither mines (41) nor chamber (42)
  H.advanceStory(calm(60, function()
    return H.mapId() ~= 41 and H.mapId() ~= 42
  end), 45000, { spare = TRITOCH, honest = true }),

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

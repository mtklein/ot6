-- @suite slow savestate=worldmap_narshe
-- battle_hits: a boosted Fight adds 2 swings per pending BP (one extra hit
-- per BP for a one-weapon character; a genji pair swings both hands
-- again).
--
-- Issue #75 conversion.  The old apparatus existed because the magitek
-- intro party has no Fight command: it rewrote every $202E command list to
-- Fight-only, berserked the party, cleared the magitek status bit, handed
-- the subject bp:=3/pending:=2, and pinned the guards at 500 HP so the
-- rigged auto-Fights had something to hit.  On worldmap_narshe none of
-- that is needed: LOCKE (chid $01) carries Fight on row 0 and Steal on
-- row 1 (measured 2026-08-10: cmds 00,05,FF,01), so the berserk and
-- Fight-only setup drops out and the boost bank is earned the way
-- battle_boost earns it: every character opens with 1 bp (Ot6InitBP) and
-- each unboosted action regens +1 (Ot6ActionEnd).  Locke banks with Steal,
-- a real command that costs zero MP and deals zero damage, so two banking
-- turns cannot end the fight however weak the grass-area trash is.  TERRA
-- defers every turn with X (vanilla's own turn-cycling key), so the
-- subject's boost accounting is the only party arithmetic in flight, and
-- "only the subject has pending" holds by play rather than by poke.
--
--   asserts (all four originals, same numbers): $3a70 gets the boosted
--   swing count 1 + 2*pending = 5 exactly once, never more, the boost is
--   consumed (3-2 = 1) with no regen after the swing, and pending clears.
--   Plus the earn-on-camera controls: bp reached 3 by two steals, and
--   pending reached 2 by two R presses.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
-- $30 is the thief submenu (tools shell): since #55 the Steal row opens it
-- with Steal on row 0, so one attempt is A (submenu), A (row 0), A (target),
-- which is gen_sfigaro.lua's measured drive.  $01 is transitional, so the
-- driver leaves the pad alone during it.
local ST_CMD, ST_THIEF, ST_TGT, ST_TRANS = 0x05, 0x30, 0x38, 0x01
local CMD_FIGHT, CMD_STEAL = 0x00, 0x05
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local function cmdRow(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end

local subject                  -- Locke's battle slot, found by reading $3ED8
local rPresses = 0             -- real R edges counted at the subject's menu
local swings, swingRef = {}, nil
local armed = false

-- one pad decision per 8 frames, 4 held + 4 released (the menu-proven edge
-- cadence battle_boost uses); returns the button table to hold this frame.
local mf = 0
local function decide()
  if H.readByte(MENU) == 0 then
    -- no interactive menu: page battle text / victory the driver way
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  if (mf - 1) % 8 >= 4 then return {} end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end           -- hands off mid-handoff
  local btn
  if act ~= subject then
    btn = (st == ST_CMD) and "x" or "b"          -- defer everyone else
  elseif bp(subject) < 3 then                    -- BANK: two real steals
    if st == ST_CMD then
      local want = cmdRow(subject, CMD_STEAL)
      local cur = H.readByte(CMDROW + subject) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_THIEF then btn = "a"         -- Steal is submenu row 0
    elseif st == ST_TGT then btn = "a"           -- default monster target
    else btn = "b" end
  elseif pend(subject) < 2 then                  -- BOOST: two real R edges
    if st == ST_CMD then
      if not armed then
        armed = true
        swingRef = emu.addMemoryCallback(function(addr, value)
          swings[#swings + 1] = value
        end, emu.callbackType.write, 0x7e3a70, 0x7e3a70)
      end
      btn = "r"
      if (mf - 1) % 8 == 0 then rPresses = rPresses + 1 end
    else btn = "b" end
  else                                           -- FIGHT, boosted
    if st == ST_CMD then
      local want = cmdRow(subject, CMD_FIGHT)
      local cur = H.readByte(CMDROW + subject) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  end
  if btn and (mf - 1) % 8 == 0 then
    H.log(string.format("hits: f%d st=%02x act=%d press %s (bp=%d pend=%d)",
      H.frame, st, act, btn, bp(subject), pend(subject)))
  end
  return btn and { [btn] = true } or {}
end

local plan, idx, goal = nil, 1, { 82, 56 }

H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  -- patrol the grass area south of Narshe until a real encounter fires
  -- (codex_saveas's measured route: ~230 frames off the fixture tile)
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then
        if H.worldX() == goal[1] and H.worldY() == goal[2] then
          goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
        end
        plan = H.worldBfs(goal[1], goal[2]); idx = 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
      end
      local dir = plan[idx]; idx = idx + 1
      if not dir then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, "grass-area encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot*2) == 0x01 then subject = slot end
    end
    H.assertEq(subject ~= nil, true, "LOCKE is really in this party")
    H.assertEq(cmdRow(subject, CMD_FIGHT), 0, "his real Fight sits on row 0")
    H.assertEq(cmdRow(subject, CMD_STEAL) ~= nil, true,
      "and his real Steal exists to bank with")
    H.log(string.format("subject slot %d (LOCKE): bp=%d hp=%d",
      subject, bp(subject), H.readWord(0x3BF4 + subject*2)))
  end),
  -- bank 3 bp (1 open + 2 steal regens), boost to pending 2, Fight
  H.driveUntil(function()
    return pend(subject) == 2 and bp(subject) == 3
  end, 20000, {
    H.call(function() H.setPad(decide()) end),
  }, "3 bp banked by real steals, pending 2 by real R"),
  H.call(function()
    H.assertEq(bp(subject), 3, "3 bp banked by real turns (1 open + 2 steals)")
    H.assertEq(pend(subject), 2, "pending 2 from real R presses")
    H.assertEq(rPresses >= 2, true, "at least two R edges were really sent")
  end),
  H.driveUntil(function() return pend(subject) == 0 end, 10000, {
    H.call(function() H.setPad(decide()) end),
  }, "boosted fight lands"),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    emu.removeMemoryCallback(swingRef, emu.callbackType.write, 0x7e3a70, 0x7e3a70)
    local n5, maxv, vals = 0, -1, {}
    for _, v in ipairs(swings) do
      if v == 5 then n5 = n5 + 1 end
      if v > maxv and v ~= 0xff then maxv = v end   -- ff = the dec-past-zero wrap
      vals[#vals + 1] = string.format("%02x", v)
    end
    H.log("swing-count write values: " .. table.concat(vals, " "))
    H.assertEq(n5, 1, "exactly one boosted fight queued 1+2*2 swings")
    H.assertEq(maxv, 5, "and nothing queued more")
    H.assertEq(bp(subject), 1, "boost consumed (3-2), regen skipped")
    H.assertEq(pend(subject), 0, "pending cleared")
    H.screenshot("hits_landed")
  end),
})

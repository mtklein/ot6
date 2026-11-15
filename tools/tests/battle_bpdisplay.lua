-- @suite slow
-- battle_bpdisplay.lua -- the Boost Point cells beside the names show the
-- rule, every frame (#540).
--
-- The owner (v0.45): "they should be visible until the ability that uses
-- them begins, and should not visibly regenerate until that player becomes
-- active."  Each name row of the party window has one cell: the arrows of a
-- pending boost, or the pips of the bank.  The rule, read from the game's
-- own events rather than from OT6's display bytes:
--   1. a pending boost shows as its arrows from the press until the action
--      it is for begins (its ExecCmd), not only while its menu is open: a
--      confirmed, queued action keeps its arrows;
--   2. from the moment that action begins (a few frames' grace: the battle
--      computes the action before it draws again), the cell shows the bank less the
--      pending points (the spend), until the action ends and the bank is
--      charged; a boost the action ends up not spending (kept) may hold its
--      arrows instead, and one it spends may not;
--   3. the point an unboosted turn earns at its end (Ot6ActionEnd's regen)
--      does not show until that character is active again: its command
--      window opens, or its next action begins;
--   4. otherwise the cell is the bank.
-- Each row is read from VRAM (the party window's map, $7834 + 64*row) every
-- frame; a cell that disagrees with the rule for six frames running is a
-- violation (the nmi flush rewrites one row a frame, the lowest changed one
-- first, and every row at least every four frames).  Coverage is asserted too: the
-- battle shows a confirmed boost's arrows with that character's window shut,
-- a withheld regen point, and boosted actions beginning and spending.
--
-- Played: Continue ultros-won-v1 (TERRA, LOCKE, STRAGO and RELM at Esper
-- Mountain's save point), pace into a random battle beside it, and play it
-- through the real menu (H.kitBattle): TERRA Fights at one point, LOCKE at
-- two, STRAGO at none; the others Defend while the plan runs (each Defend
-- an unboosted turn, so regen points), then everyone Fights it out.
-- Nothing is written.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local TERRA, LOCKE, STRAGO = 0, 1, 7
local CMD_FIGHT = 0x00

local PIP = { [0x72] = 0, [0x73] = 1, [0x75] = 2, [0x76] = 3, [0x77] = 4, [0x79] = 5 }
local ARROW = { [0x68] = 1, [0x6C] = 2, [0x6D] = 3 }
local ROWADDR = { [0] = 0x7834, 0x7874, 0x78B4, 0x78F4 }
local vram = emu.memType.snesVideoRam
local function bank(c) return H.readByte(0x3E9C + c * 2) end
local function pend(c) return H.readByte(0x3E9D + c * 2) end

local W = { viol = {}, queuedArrows = 0, withheld = 0, begins = 0, spent = 0, kept = 0, frames = 0 }
local st = {}
for c = 0, 3 do st[c] = { begun = false, owed = false, mism = 0, seen = false } end

local function face(word)
  local t = word & 0xFF
  if PIP[t] then return "p" .. PIP[t] end
  if ARROW[t] then return "a" .. ARROW[t] end
  return string.format("?%02X", t)
end

local watching = false
local function arm()
  -- an action begins: ExecCmd, x = the actor's entity offset.  A
  -- counterattack ($b1 bit 0) is no action of the character's, and $b5 =
  -- $12 is the CmdNoEffect an emptied command list runs as: neither begins
  -- anything.
  emu.addMemoryCallback(function()
    if not watching then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x >= 8 or (H.readByte(0xB1) & 1) == 1 then return end
    local s = st[x >> 1]
    s.owed = false                         -- active again (3)
    if H.readByte(0xB5) == 0x12 then return end
    if pend(x >> 1) > 0 and not s.begun then
      H.log(string.format("[bpdisplay] f%d slot %d begins: command %02X, queued %04X, pending %d, bank %d",
        H.frame, x >> 1, H.readByte(0xB5), H.readWord(0x3A7C), pend(x >> 1), bank(x >> 1)))
      s.begun, s.beginF, s.arrowsIn, s.pipsIn = true, H.frame, 0, 0
      W.begins = W.begins + 1
    end
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"))
  -- an action ends: the bank is charged or earns here
  emu.addMemoryCallback(function()
    if not watching then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x >= 8 then return end
    local s = st[x >> 1]
    s.endAt, s.endBank, s.endPend = H.frame, bank(x >> 1), pend(x >> 1)
    H.log(string.format("[bpdisplay] f%d slot %d's action ends: bank %d, pending %d", H.frame, x >> 1,
      s.endBank, s.endPend))
  end, emu.callbackType.exec, H.sym("Ot6ActionEnd"))
end

local function sample()
  if not watching or not H.battleActive() then return end
  W.frames = W.frames + 1
  for c = 0, 3 do
    local s = st[c]
    local b, p = bank(c), pend(c)
    if s.lb ~= nil and (b ~= s.lb or p ~= s.lp) then
      H.log(string.format("[bpdisplay] f%d slot %d bank %d->%d pending %d->%d", H.frame, c, s.lb, b, s.lp, p))
    end
    s.lb, s.lp = b, p
  end
  if H.readByte(0x7BCA) ~= 0 then st[H.readByte(0x62CA) & 3].owed = false end   -- (3)
  for c = 0, 3 do
    local s = st[c]
    if s.endAt and H.frame >= s.endAt + 3 then   -- Ot6ActionEnd has run (its charge or regen in)
      local b = bank(c)
      if s.endPend > 0 then
        if b + s.endPend == s.endBank then
          W.spent = W.spent + 1
          if s.begun and s.arrowsIn > 8 then
            W.viol[#W.viol + 1] = string.format("f%d slot %d: arrows held %d frames after a spent boost began",
              H.frame, c, s.arrowsIn)
          end
        else
          W.kept = W.kept + 1
          if s.begun and s.pipsIn > 8 then
            W.viol[#W.viol + 1] = string.format("f%d slot %d: a kept boost showed as spent for %d frames",
              H.frame, c, s.pipsIn)
          end
        end
      elseif b == s.endBank + 1 then
        s.owed = true                      -- a regen point (3)
      end
      H.log(string.format("[bpdisplay] f%d slot %d after its action: bank %d (regen not yet shown %s)",
        H.frame, c, b, tostring(s.owed)))
      s.begun, s.endAt = false, nil
    end
  end
  for r = 0, 3 do
    local c = H.readByte(0x64D6 + r)
    if c ~= 0xFF and c < 4 then
      local s = st[c]
      local got = face(emu.readWord(ROWADDR[r] * 2, vram))
      local p, b = pend(c), bank(c)
      local want, alt
      if p > 0 and not s.begun then
        want = "a" .. math.min(p, 3)
      elseif s.begun then
        want = "p" .. math.max(0, b - p)
        if p > 0 then alt = "a" .. math.min(p, 3) end   -- a kept boost (2)
      else
        want = "p" .. math.max(0, b - (s.owed and 1 or 0))
      end
      if got:sub(1, 1) ~= "?" then s.seen = true end
      if s.seen then
        if got == want or got == alt then
          s.mism = 0
          if s.begun and p > 0 then
            if got == want then s.pipsIn = s.pipsIn + 1 else s.arrowsIn = s.arrowsIn + 1 end
          end
          if p > 0 and not s.begun and got == want
            and (H.readByte(0x7BCA) == 0 or (H.readByte(0x62CA) & 3) ~= c) then
            W.queuedArrows = W.queuedArrows + 1
          end
          if s.owed and not s.begun and got == want and b > 0 then W.withheld = W.withheld + 1 end
        else
          s.mism = s.mism + 1
          if s.mism == 6 then
            W.viol[#W.viol + 1] = string.format("f%d row %d (slot %d): shows %s, the rule says %s "
              .. "(bank %d, pending %d, begun %s, regen not yet shown %s)", H.frame, r, c, got, want,
              b, p, tostring(s.begun), tostring(s.owed))
          end
        end
      end
    end
  end
end

local plan = {
  { who = TERRA, cmd = CMD_FIGHT, boost = 1 },
  { who = LOCKE, cmd = CMD_FIGHT, boost = 2 },
  { who = STRAGO, cmd = CMD_FIGHT, boost = 0 },
}

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("ultros-won-v1"),
  H.call(function()
    arm()
    emu.addEventCallback(sample, emu.eventType.startFrame)
  end),
  H.paceToEncounter("bpdisplay"),
  H.call(function() watching = true end),
  H.kitBattle(plan, {}),
  H.call(function()
    watching = false
    H.log(string.format("[bpdisplay] %d frames sampled; boosted actions begun %d (spent %d, kept %d); "
      .. "frames a queued boost's arrows showed with its window shut %d; frames a regen point was "
      .. "withheld %d; violations %d", W.frames, W.begins, W.spent, W.kept, W.queuedArrows, W.withheld, #W.viol))
    for i = 1, math.min(#W.viol, 20) do H.log("[bpdisplay] violation: " .. W.viol[i]) end
    H.assertEq(#W.viol, 0, "every pip cell followed the rule on every frame (#540)")
    H.assertEq(W.begins >= 2 and W.spent >= 2, true,
      "coverage: at least two boosted actions began and spent their points")
    H.assertEq(W.queuedArrows > 0, true,
      "coverage: a confirmed boost's arrows showed with its window shut, before its action began")
    H.assertEq(W.withheld > 0, true,
      "coverage: a regen point was withheld until its character was active again")
  end),
})

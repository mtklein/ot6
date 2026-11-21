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
--   2. from the moment that action begins (judged once its battle script
--      is drawing: the battle computes the action before it draws again),
--      the cell shows the bank less the
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
-- first, and every row at least every four frames).  A reversion is a cell
-- that has shown the rule's face and then shows another before the rule moves
-- (a lag only ever trails a change; c1122cce's bug painted the right face and
-- then the text engine's stale copy over it for six frames).  An alternating
-- cell never makes a run of six, and its frames are too few to stand out of
-- the lag in a total (the old bound of 60 such frames passed with c1122cce
-- reverted as on main, #548), but it reverts every few frames: a row may
-- revert at most REV_EPISODES times, and never back to a withheld regen
-- point's face once the earned point showed.  Coverage is asserted too: the
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

local W = { viol = {}, queuedArrows = 0, withheld = 0, begins = 0, spent = 0, kept = 0, frames = 0, mismRow = {},
  revRow = {}, revMax = {}, revs = {}, revWithheld = 0 }
-- reversions a row may make in the battle.  Not zero: the menu's staged copy
-- of the party window can land over the flush's cell for up to three frames
-- as a boost is raised, spent or begun (0-3 a row in 12 draws on the fixed
-- ROM; build/attempts/wt/v050-multihit-anim/bpd/).  The withheld point's
-- face coming back after the earned one showed (a window's open staged the
-- names before $7bca was set: 41 of 66 reversions in the same 12 draws before
-- Ot6WindowOpenNames, 0 of 25 after) is asserted absent on its own (#548); an
-- alternating cell, a second writer fighting the flush, makes one every few
-- frames
local REV_EPISODES = 4
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
    s.sync = true
    if not s.begun then
      -- (a pending boost an action raises for itself, Bestow's point or
      -- Umaro's dump, is spent by an action already begun)
      s.begun, s.beginF, s.arrowsIn, s.pipsIn, s.drawn = true, H.frame, 0, 0, nil
      if pend(x >> 1) > 0 then
        H.log(string.format("[bpdisplay] f%d slot %d begins: command %02X, queued %04X, pending %d, bank %d",
          H.frame, x >> 1, H.readByte(0xB5), H.readWord(0x3A7C), pend(x >> 1), bank(x >> 1)))
        W.begins = W.begins + 1
      end
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

local loadedSeen = nil
local function sample()
  if not watching or not H.battleActive() then return end
  -- a restored snapshot (a host that branches) puts the game somewhere this
  -- model has not followed: each row waits for its character's next window
  -- or action before it is judged again
  if H.loadedFrame ~= loadedSeen then
    loadedSeen = H.loadedFrame
    for c = 0, 3 do st[c].begun, st[c].owed, st[c].sync, st[c].endAt = false, false, false, nil end
  end
  W.frames = W.frames + 1
  for c = 0, 3 do
    local s = st[c]
    local b, p = bank(c), pend(c)
    if s.lb ~= nil and (b ~= s.lb or p ~= s.lp) then
      H.log(string.format("[bpdisplay] f%d slot %d bank %d->%d pending %d->%d", H.frame, c, s.lb, b, s.lp, p))
    end
    s.lb, s.lp = b, p
  end
  if H.readByte(0x7BCA) ~= 0 then
    local a = st[H.readByte(0x62CA) & 3]
    a.owed, a.sync = false, true            -- (3)
  end
  for c = 0, 3 do
    local s = st[c]
    if s.endAt and H.frame >= s.endAt + 3 then   -- Ot6ActionEnd has run (its charge or regen in)
      local b = bank(c)
      if s.endPend > 0 then
        if b + s.endPend == s.endBank then
          W.spent = W.spent + 1
          if s.begun and s.arrowsIn > 2 then
            W.viol[#W.viol + 1] = string.format("f%d slot %d: arrows held %d frames after a spent boost "
              .. "began (f%d, its script drawing from f%s)", H.frame, c, s.arrowsIn, s.beginF, tostring(s.drawn))
          end
        else
          W.kept = W.kept + 1
          if s.begun and s.pipsIn > 2 then
            W.viol[#W.viol + 1] = string.format("f%d slot %d: a kept boost showed as spent for %d frames",
              H.frame, c, s.pipsIn)
          end
          if b == s.endBank + 1 then s.owed = true end   -- kept, then its regen (3)
        end
      elseif b == s.endBank + 1 then
        s.owed = true                      -- a regen point (3)
      end
      H.log(string.format("[bpdisplay] f%d slot %d after its action: bank %d (regen not yet shown %s)",
        H.frame, c, b, tostring(s.owed)))
      s.begun, s.endAt = false, nil
    end
  end
  local busy = H.readByte(0x57BF) ~= 0       -- OT6_SCRIPTBUSY: a battle script runs
  for c = 0, 3 do
    local s = st[c]
    if s.begun and s.drawn == nil and busy then s.drawn = H.frame end
  end
  for r = 0, 3 do
    local c = H.readByte(0x64D6 + r)
    if c ~= 0xFF and c < 4 then
      local s = st[c]
      local got = face(emu.readWord(ROWADDR[r] * 2, vram))
      -- the name beside the cell is drawn too: Ot6PipGlyph_ext once left
      -- the text engine a nonzero b and every name in the window went blank
      local lit = 0
      for k = 1, 8 do
        if (emu.readWord((ROWADDR[r] - k) * 2, vram) & 0xFF) ~= 0xFF then lit = lit + 1 end
      end
      if s.seen and lit == 0 then
        s.blank = (s.blank or 0) + 1
        if s.blank == 30 then
          W.viol[#W.viol + 1] = string.format("f%d row %d (slot %d): no name drawn beside the cell", H.frame, r, c)
        end
      else
        s.blank = 0
      end
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
      -- a cover's point (OT6_PIPPEND = slot + 1) or a runic absorb's
      -- (OT6_BPDEFER) shows when its blow or spell lands: one fewer until then
      if (not s.begun or p == 0) and (H.readByte(0xED74) == c + 1
          or (H.readByte(0xEEF2) & (1 << c)) ~= 0) then
        alt = "p" .. math.max(0, b - p - (s.owed and 1 or 0) - 1)
      end
      if got:sub(1, 1) ~= "?" then s.seen = true end
      -- the battle computes an action before it draws again, and the command
      -- window's close redraws the party window from the menu's own staging
      -- for a few frames more (measured: up to 15, battle_runic spliced,
      -- build/attempts/wt/v046-break-feel/bpw): a begun action is judged
      -- from 16 frames after its script starts drawing
      local settling = s.begun and (s.drawn == nil or H.frame < s.drawn + 16)
      -- a reversion: the cell showed the rule's face (want or alt) since the
      -- rule last moved, and now shows neither
      local key = want .. "|" .. tostring(alt)
      if key ~= s.ruleKey then s.ruleKey, s.shown, s.rev = key, false, 0 end
      local judged = s.seen and s.sync ~= false and not settling
      if not judged then s.shown, s.rev = false, 0 end
      if judged then
        if got == want or got == alt then
          s.shown, s.rev = true, 0
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
          if s.shown or (s.rev or 0) > 0 then
            s.rev = (s.rev or 0) + 1
            W.revMax[r] = math.max(W.revMax[r] or 0, s.rev)
          end
          if s.shown then
            W.revRow[r] = (W.revRow[r] or 0) + 1
            -- the earned point shown, then the withheld face again (#548)
            if not s.begun and p == 0 and want == "p" .. b and got == "p" .. (b - 1) then
              W.revWithheld = W.revWithheld + 1
            end
            if #W.revs < 20 then
              W.revs[#W.revs + 1] = string.format("f%d row %d (slot %d): showed %s, now %s, the rule still %s%s "
                .. "(bank %d, pending %d, begun %s, regen not yet shown %s)", H.frame, r, c, s.lastGot, got, want,
                alt and (" or " .. alt) or "", b, p, tostring(s.begun), tostring(s.owed))
            end
          end
          s.shown = false
          s.mism = s.mism + 1
          -- every mismatched frame past the grace, run or no run: a cell that
          -- alternates right and wrong never makes a run of six (review)
          W.mismRow[r] = (W.mismRow[r] or 0) + 1
          if s.mism == 6 then
            W.viol[#W.viol + 1] = string.format("f%d row %d (slot %d): shows %s, the rule says %s "
              .. "(bank %d, pending %d, begun %s, regen not yet shown %s; OT6_BPMARK $%02X)", H.frame, r, c,
              got, want, b, p, tostring(s.begun), tostring(s.owed), H.readByte(0xEEF1))
          end
        end
      end
      s.lastGot = got
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
    local rows = {}
    for r = 0, 3 do rows[#rows + 1] = string.format("row %d %d", r, W.mismRow[r] or 0) end
    H.log("[bpdisplay] frames a cell disagreed with the rule past the grace, all told: " .. table.concat(rows, ", "))
    local rrows = {}
    for r = 0, 3 do
      rrows[#rrows + 1] = string.format("row %d %d (longest %d)", r, W.revRow[r] or 0, W.revMax[r] or 0)
    end
    H.log("[bpdisplay] times a cell left the rule's face before the rule moved (reversions): "
      .. table.concat(rrows, ", "))
    for i = 1, #W.revs do H.log("[bpdisplay] reversion: " .. W.revs[i]) end
    H.assertEq(#W.viol, 0, "every pip cell followed the rule on every frame (#540)")
    local revWorst = 0
    for r = 0, 3 do revWorst = math.max(revWorst, W.revRow[r] or 0) end
    H.assertEq(revWorst <= REV_EPISODES, true, string.format("no pip cell left the rule's face before the rule "
      .. "moved more than %d times (worst row %d; the first: %s)", REV_EPISODES, revWorst, W.revs[1] or "none"))
    H.assertEq(W.revWithheld, 0, "no cell went back to a withheld regen point's face after the earned point "
      .. "showed (#548: a window's open staged the names before the point was shown)")
    H.assertEq(W.begins >= 2 and W.spent >= 2, true,
      "coverage: at least two boosted actions began and spent their points")
    H.assertEq(W.queuedArrows > 0, true,
      "coverage: a confirmed boost's arrows showed with its window shut, before its action began")
    H.assertEq(W.withheld > 0, true,
      "coverage: a regen point was withheld until its character was active again")
  end),
})

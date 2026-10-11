-- @suite slow
-- battle_breakspell.lua -- the Break spell takes shields, not a petrify (#398).
--
-- Break ($0c) deals no damage and sets no status: it takes shields off its
-- one target, ignoring class and element, one plus one per boost point, at
-- its flat 25 MP (Ot6BreakSpell, ot6_breakspell.asm; MagicProp overrides
-- 7-10).  Played: Continue fc-alcove-v1 (TERRA L26 knows Break, her level-24
-- spell), walk onto the continent into a random battle, and cast Break
-- through the real menu at the shielded monster with the most shields, at
-- 1 BP, 0 BP and 3 BP (Defends bank the points, and wait out a Break before
-- the next cast); everyone else Defends.
-- Nothing is written.
--
-- Asserted per cast, from what the engine did (the spell's own $3410 write
-- opens the record, TERRA's Ot6ActionEnd closes it):
--   1. the target's shields fell by exactly 1 + boost (or to Broken, when it
--      held no more), and no other body's shields moved;
--   2. its HP did not move and it is not petrified or dead (no damage, no
--      status: vanilla Break petrified);
--   3. TERRA paid 25 MP at both boosts (the price is flat), and the bank
--      paid the boost (an unboosted cast earns its turn's pip, as any turn).
-- Each cast aims at the unbroken body with the most shields and takes 1 +
-- boost, or asserts the Break when the body held no more than that.
--
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/breakspell/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, BREAK, CMD_MAGIC, CMD_DEFEND = 0x00, 0x0C, 0x02, nil
local BREAK_MP = 25

local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end

local function shields(s) return H.readByte(0x3E40 + s * 2) end
local function broken(s) return H.readByte(0x3E90 + s * 2) ~= 0 end
local function mons()
  local t = {}
  for s = 0, 5 do
    t[s] = { hp = H.readWord(0x3BFC + s * 2), sh = shields(s), brk = broken(s),
      st = H.readByte(0x3EEC + s * 2), present = (H.readByte(0x3AA8 + s * 2) & 1) == 1 }
  end
  return t
end

-- the continent, a random battle: pace between the arrival tile and a
-- walkable neighbour until one starts
local function encounter()
  local A, B = nil, nil
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.call(function()
      if A ~= nil then return end
      local x0, y0 = H.fieldX(), H.fieldY()
      for _, d in ipairs({ { 0, 3 }, { 0, -3 }, { 3, 0 }, { -3, 0 }, { 0, 2 }, { 2, 0 }, { -2, 0 }, { 0, -2 } }) do
        if H.bfsPath(x0 + d[1], y0 + d[2]) then A, B = { x0, y0 }, { x0 + d[1], y0 + d[2] }; break end
      end
      H.assertEq(A ~= nil, true, string.format("a walkable pace on the continent from (%d,%d)", x0, y0))
      H.log(string.format("[break] pacing (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.navTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle on the continent")
end

local terraSeat, recs, rec = nil, {}, nil
local function pickTarget()
  local best, bs = nil, -1
  local m = mons()
  for s = 0, 5 do
    if m[s].present and m[s].hp > 0 and (m[s].st & 0xC2) == 0 and not m[s].brk and m[s].sh > bs then
      best, bs = s, m[s].sh
    end
  end
  return best, bs
end

local function arm()
  emu.addMemoryCallback(function(_, v)
    if v ~= BREAK or terraSeat == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    local e = terraSeat * 2
    rec = { pend = H.readByte(0x3E9D + e), bank0 = H.readByte(0x3E9C + e), mp0 = H.readWord(0x3C08 + e),
      mon0 = mons(), f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or terraSeat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == terraSeat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 1 then return false end
  local e = terraSeat * 2
  rec.bank1, rec.mp1, rec.mon1 = H.readByte(0x3E9C + e), H.readWord(0x3C08 + e), mons()
  recs[#recs + 1] = rec
  for s = 0, 5 do
    local o, n = rec.mon0[s], rec.mon1[s]
    if o.present then
      H.log(string.format("[break] cast %d (%d BP, f%d): slot %d HP %d -> %d, shields %d -> %d, broken %s -> %s, "
        .. "status %02X -> %02X", #recs, rec.pend, rec.f, s, o.hp, n.hp, o.sh, n.sh, tostring(o.brk),
        tostring(n.brk), o.st, n.st))
    end
  end
  H.log(string.format("[break] cast %d: MP %d -> %d, bank %d -> %d", #recs, rec.mp0, rec.mp1, rec.bank0, rec.bank1))
  rec = nil
  return true
end

local function check(r, boost, slot)
  H.assertEq(r.pend, boost, string.format("the cast ran at the %d BP planned", boost))
  local o, n = r.mon0[slot], r.mon1[slot]
  local want = math.min(1 + boost, o.sh)
  if want >= o.sh then
    H.assertEq(n.brk and n.sh == 0, true, string.format("slot %d's %d shield(s) all taken by %d chips: Broken",
      slot, o.sh, 1 + boost))
  else
    H.assertEq(o.sh - n.sh, want, string.format("Break at %d BP took %d shield(s) off slot %d", boost, want, slot))
  end
  for s = 0, 5 do
    if s ~= slot and r.mon0[s].present then
      H.assertEq(r.mon1[s].sh, r.mon0[s].sh, string.format("slot %d's shields did not move (single target)", s))
    end
  end
  H.assertEq(n.hp, o.hp, string.format("slot %d's HP did not move: Break deals no damage", slot))
  H.assertEq(n.st & 0xC0, o.st & 0xC0, string.format("slot %d was not petrified or killed", slot))
  H.assertEq(r.mp0 - r.mp1, BREAK_MP, string.format("Break cost its flat %d MP at %d BP", BREAK_MP, boost))
  local regen = (boost == 0 and r.bank0 < 5) and 1 or 0   -- an unboosted turn earns its pip
  H.assertEq(r.bank1, r.bank0 - boost + regen, string.format("the bank paid the %d boost point(s)%s", boost,
    regen == 1 and " and earned the unboosted turn's pip" or ""))
end

-- the casts, in order: 1 BP on the body with the most shields (two chips:
-- counted exactly on three or more, the Break on two), 0 BP on a body with
-- two or more (one chip, counted exactly), then 3 BP (four chips, or the
-- Break when the body holds four or fewer).  Every body on this map's pool
-- holds two or three (route_data.py pool field 394).  Before each cast the
-- party Defends until a live unbroken body holds what the cast needs: a
-- lone body a cast broke recovers its shields when its Break runs out
-- (Ot6Tick).
local CASTS = { { boost = 1, need = 2 }, { boost = 0, need = 2 }, { boost = 3, need = 1 } }
local plan, targets = nil, {}
local function planCast(i)
  return H.call(function()
    if terraSeat == nil then
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then terraSeat = s end end
      H.assertEq(terraSeat ~= nil, true, "TERRA is seated")
    end
    local t, sh = pickTarget()
    H.assertEq(t ~= nil and sh >= CASTS[i].need, true, string.format(
      "cast %d (%d BP): a live unbroken monster holds %d+ shields (the best holds %s)", i, CASTS[i].boost,
      CASTS[i].need, tostring(sh)))
    targets[i] = t
    H.log(string.format("[break] cast %d: %d BP at slot %d (%d shields); TERRA seat %d, MP %d, bank %d", i,
      CASTS[i].boost, t, sh, terraSeat, H.readWord(0x3C08 + terraSeat * 2), H.readByte(0x3E9C + terraSeat * 2)))
    plan = { { who = TERRA, cmd = CMD_MAGIC, spell = BREAK, boost = CASTS[i].boost, slot = t } }
  end)
end
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local steps = {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function() arm() end),
  H.navTo(8, 9, { maxFrames = 3000 }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return mapIs(394) end, 1800, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { a = true } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "alcove -> the continent (394)")
  end)(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, "control on 394", 10),
  encounter(),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.waitFrames(30),
}
local empty = {}
for i = 1, #CASTS do
  steps[#steps + 1] = H.kitBattle(empty, { untilPlanDone = true, idle = "defend", maxFrames = 30000,
    planDone = function() local _, sh = pickTarget(); return sh ~= nil and sh >= CASTS[i].need end })
  steps[#steps + 1] = planCast(i)
  steps[#steps + 1] = H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
    planDone = function() return close() end })
  steps[#steps + 1] = H.call(function()
    H.assertEq(#recs, i, string.format("cast %d was recorded", i))
    check(recs[i], CASTS[i].boost, targets[i])
  end)
end
steps[#steps + 1] = H.call(function()
  H.log("[break] PASS: Break took 1 + boost shields at 1, 0 and 3 BP, no damage, no petrify, 25 MP flat")
end)
H.run({ maxFrames = 200000 }, steps)

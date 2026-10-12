-- @suite slow
-- battle_breakspell.lua -- the Break spell takes shields, not a petrify (#398).
--
-- Break ($0c) deals no damage and sets no status: it takes shields off its
-- one target, ignoring class and element, one plus one per boost point, at
-- its flat 25 MP (Ot6BreakProps and Ot6BreakSpell, ot6_breakspell.asm; a
-- monster's Break stays vanilla's: battle_breakmonster).  Played: Continue fc-alcove-v1 (TERRA L26 knows Break, her level-24
-- spell), walk onto the continent into a random battle, and cast Break
-- through the real menu at the shielded monster with the most shields, at
-- 0, 1 and 3 BP (Defends bank the points, and wait out a Break before the
-- next cast); everyone else Defends.  A battle where TERRA cannot cast (this
-- map's Apokryphos mutes) is fought out and the next one taken, and a cast
-- the battle's end cuts off, or one that charged no MP, is not counted.

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

-- The three counted casts: 0 BP on a body holding two or more (one chip,
-- counted exactly), 1 BP on a body holding two or more (two chips: counted
-- exactly on three or more, the Break on exactly two), and 3 BP on any
-- shielded body (four chips, or the Break when it holds four or fewer).
-- Every body on this map's pool holds two or three (route_data.py pool
-- field 394).  Each turn plays the first counted cast a live unbroken body
-- can take; when none can (a lone body worn to one shield), a filler
-- unboosted Break, checked but not counted, breaks it, and the party
-- Defends until its Break runs out and its shields come back (Ot6Tick).
local CASTS = { { boost = 0, need = 2 }, { boost = 1, need = 2 }, { boost = 3, need = 1 } }
local doneCast, cur, nDone, fillers, turns = {}, nil, 0, 0, 0
local plan, targets, mode, nrec = {}, {}, nil, 0
-- TERRA can cast: standing (no Wound, Petrify, Imp or Zombie) and not Mute,
-- Sleep, Muddle or Berserk -- this map's Apokryphos casts Silencer (Mute)
local function terraCasts()
  local e = terraSeat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0
end
local function decide()
  turns = turns + 1
  H.assertEq(turns <= 16, true, "the three counted casts within 16 tries")
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then terraSeat = s end end
  H.assertEq(terraSeat ~= nil, true, "TERRA is seated")
  cur, plan, mode, nrec = nil, {}, "cast", #recs
  if not terraCasts() then
    mode = "fightout"
    H.log(string.format("[break] TERRA cannot cast here (status %02X %02X): this battle is fought out and the "
      .. "next one taken", H.readByte(0x3EE4 + terraSeat * 2), H.readByte(0x3EE5 + terraSeat * 2)))
    return
  end
  local t, sh = pickTarget()
  if t == nil or sh < 1 then
    mode = "wait"
    H.log("[break] no live unbroken shielded body: the party Defends until a Break runs out")
    return
  end
  for i, c in ipairs(CASTS) do
    if not doneCast[i] and sh >= c.need then cur = i; break end
  end
  local boost = cur and CASTS[cur].boost or 0
  if cur == nil then fillers = fillers + 1 end
  H.assertEq(fillers <= 4, true, "at most four filler casts")
  targets[cur or 0] = t
  H.log(string.format("[break] %s: %d BP at slot %d (%d shields); TERRA seat %d, MP %d, bank %d",
    cur and ("cast " .. cur) or "a filler cast (not counted)", boost, t, sh, terraSeat,
    H.readWord(0x3C08 + terraSeat * 2), H.readByte(0x3E9C + terraSeat * 2)))
  plan = { { who = TERRA, cmd = CMD_MAGIC, spell = BREAK, boost = boost, slot = t } }
end
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function() arm() end),
  H.fcAlcoveToBattle("break"),
  H.driveUntil(function() return nDone == #CASTS end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("break") }, {}),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function()
          if mode == "wait" then local t, sh = pickTarget(); return t ~= nil and sh >= 1 end
          return close()
        end }),
      H.call(function()
        if mode ~= "cast" then return end
        if #recs == nrec then
          H.log("[break] the battle ended before the cast resolved: not counted")
          return
        end
        local r = recs[#recs]
        if r.mp0 == r.mp1 then
          H.log("[break] the cast charged no MP (it did not resolve): not counted")
          return
        end
        if cur ~= nil then
          check(r, CASTS[cur].boost, targets[cur])
          doneCast[cur] = true
          nDone = nDone + 1
        else
          check(r, 0, targets[0])
        end
      end),
    }),
  }, "the three counted casts"),
  H.call(function()
    H.log(string.format("[break] PASS: Break took 1 + boost shields at 0, 1 and 3 BP (%d filler cast(s)), no "
      .. "damage, no petrify, 25 MP flat", fillers))
  end),
})

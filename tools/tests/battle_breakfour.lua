-- @suite slow
-- battle_breakfour.lua -- a 3-BP Break takes exactly four shields, on a
-- body that holds five (#398, #424).
--
-- ot6_breakspell.asm: a character's Magic Break takes 1 + the pending boost
-- (Ot6BreakChips), so three points take four.  battle_breakspell counts 0
-- and 1 BP exactly, but the Floating Continent's bodies hold two or three,
-- so its 3-BP cast only ever showed a Break; here the body holds five, so
-- four taken is told from three and from five.
--
-- Played: Continue esper-mtn-save-v1 (Break is TERRA's level-24 spell; the
-- battles before she knows it are fought out for the experience), pace
-- beside the save point into a random battle, and TERRA casts
-- Break at 3 BP through the real menu (H.kitBattle; Defends bank the
-- points) at an unbroken body holding five; everyone else Defends.  This map's
-- pool (route_data.py pool field 375, group 90) fields an Adamanchyt
-- (five) in formations 164 and 165, 176/256 of its battles; 166 is five
-- Slurms (four).  A battle without a five-shield body, or where TERRA
-- cannot cast, is fought out and the next taken; a cast the battle's end
-- cuts off, or one that charged no MP, is not counted.  Nothing is
-- written.
--
-- Asserted for the counted cast (the spell's own $3410 write opens the
-- record, TERRA's Ot6ActionEnd closes it):
--   1. it ran at 3 BP, on a body holding five or more;
--   2. that body's shields fell by exactly four; no other body's moved;
--   3. its HP did not move and it is not petrified; TERRA paid 25 MP.
-- Old-ROM red and mutants: build/attempts/wt/v031-cleanup/ (#424).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, BREAK, CMD_MAGIC, BREAK_MP, BOOST = 0x00, 0x0C, 0x02, 25, 3

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

local seat, recs, rec = nil, {}, nil
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
    if v ~= BREAK or seat == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    local e = seat * 2
    rec = { pend = H.readByte(0x3E9D + e), mp0 = H.readWord(0x3C08 + e), mon0 = mons(), f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 1 then return false end
  rec.mp1, rec.mon1 = H.readWord(0x3C08 + seat * 2), mons()
  recs[#recs + 1] = rec
  for s = 0, 5 do
    local o, n = rec.mon0[s], rec.mon1[s]
    if o.present then
      H.log(string.format("[break4] cast %d (%d BP, f%d): slot %d HP %d -> %d, shields %d -> %d, broken %s -> %s, "
        .. "status %02X -> %02X", #recs, rec.pend, rec.f, s, o.hp, n.hp, o.sh, n.sh, tostring(o.brk),
        tostring(n.brk), o.st, n.st))
    end
  end
  H.log(string.format("[break4] cast %d: MP %d -> %d", #recs, rec.mp0, rec.mp1))
  rec = nil
  return true
end

local function check(r, slot)
  H.assertEq(r.pend, BOOST, string.format("the cast ran at the %d BP planned", BOOST))
  local o, n = r.mon0[slot], r.mon1[slot]
  H.assertEq(o.sh >= 5, true, string.format("slot %d held five or more shields at the cast (%d)", slot, o.sh))
  H.assertEq(o.sh - n.sh, 4, string.format("Break at 3 BP took exactly four of slot %d's %d shields", slot, o.sh))
  for s = 0, 5 do
    if s ~= slot and r.mon0[s].present then
      H.assertEq(r.mon1[s].sh, r.mon0[s].sh, string.format("slot %d's shields did not move (single target)", s))
    end
  end
  H.assertEq(n.hp, o.hp, string.format("slot %d's HP did not move: Break deals no damage", slot))
  H.assertEq(n.st & 0xC0, o.st & 0xC0, string.format("slot %d was not petrified or killed", slot))
  H.assertEq(r.mp0 - r.mp1, BREAK_MP, string.format("Break cost its flat %d MP at 3 BP", BREAK_MP))
end

-- TRIES: a battle fields no five-shield body 80/256 of the time, so ten
-- such battles in a row is 0.3125^10 = 8.7e-6; a try is also lost to a
-- TERRA who cannot cast or a battle that ends before the cast.  TRIES = 12.
local TRIES = 12
-- LEARN: Break is TERRA's level-24 spell, and the play that makes esper-mtn-save-v1 can leave her at L23
-- (the v0.34 qualification: 37,963 of the 39,056 experience L24 takes); battles fought before she knows it
-- are fought out for the experience, as a player would at the save point, and are not counted in TRIES
local LEARN = 8
local learning = 0
local done, turns, mode, nrec, target, held = false, 0, nil, 0, nil, 0
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function terraCasts()
  local e = seat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0
end
local function decide()
  if not H.knowsSpell(TERRA, BREAK) then
    learning = learning + 1
    H.assertEq(learning <= LEARN, true, string.format("TERRA learns Break within %d battles", LEARN))
    plan, mode, nrec = {}, "fightout", #recs
    H.log(string.format("[break4] TERRA (L%d) does not know Break yet: battle %d fought out for the experience",
      H.readByte(0x1608), learning))
    return
  end
  turns = turns + 1
  H.assertEq(turns <= TRIES, true, string.format("the counted cast within %d tries", TRIES))
  seat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
  H.assertEq(seat ~= nil, true, "TERRA is seated")
  plan, mode, nrec = {}, "cast", #recs
  local t, sh = pickTarget()
  if not terraCasts() or t == nil or sh < 5 then
    mode = "fightout"
    H.log(string.format("[break4] TERRA cannot cast (status %02X %02X) or no unbroken body holds five (best %s): "
      .. "this battle is fought out", H.readByte(0x3EE4 + seat * 2), H.readByte(0x3EE5 + seat * 2), tostring(sh)))
    return
  end
  target, held = t, sh
  H.log(string.format("[break4] 3 BP at slot %d (%d shields); TERRA seat %d, MP %d, bank %d", t, sh, seat,
    H.readWord(0x3C08 + seat * 2), H.readByte(0x3E9C + seat * 2)))
  plan = { { who = TERRA, cmd = CMD_MAGIC, spell = BREAK, boost = BOOST, slot = t } }
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("esper-mtn-save-v1"),
  H.call(arm),
  H.paceToEncounter("break4"),
  H.driveUntil(function() return done end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.paceToEncounter("break4", 0) }, {}),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function() return close() end }),
      H.call(function()
        if #recs == nrec then H.log("[break4] the battle ended before the cast resolved: not counted"); return end
        local r = recs[#recs]
        if r.mp0 == r.mp1 then H.log("[break4] the cast charged no MP (it did not resolve): not counted"); return end
        check(r, target)
        done = true
      end),
    }),
  }, "the counted cast"),
  H.call(function()
    H.log(string.format("[break4] PASS: Break at 3 BP took exactly four shields off a body holding %d, no damage, no "
      .. "petrify, 25 MP flat", held))
  end),
})

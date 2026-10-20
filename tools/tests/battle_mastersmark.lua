-- @suite slow
-- battle_mastersmark.lua -- LOCKE's divine, Master's Mark (#382): at a full
-- boost he robs and reads every enemy on the field.
--
-- kits.md ("Divines", "Locke"): the thief list's eighth row, taught on the
-- way to the Floating Continent (event switch $00A0, the Air Force
-- gauntlet).  Its one gate is three points pending (Ot6BushidoRowGrey's
-- thief arm greys it under three and the confirm refuses it); at three every
-- standing body is read as Appraise reads it (Ot6AnalyzeOne) and robbed as a
-- 3-BP Steal robs (its rare item, else its common, no roll), each item into
-- the battle's obtained-items queue (BtlGfx $05); 99 MP.  Picked at three
-- and taken back (L at target select), it does nothing and costs nothing.
--
-- Played: Continue fc-alcove-v1 (TERRA, LOCKE, EDGAR, SHADOW) and walk onto
-- the continent into random battles (H.fcAlcoveToBattle / H.fcPace); LOCKE
-- plays the list through H.kitBattle, everyone else Defends.  Nothing is
-- written.  Stages, each in a battle where a standing body carries loot:
--   1. the row at 2 BP: drawn at 99 MP in cell 7, refused at the list (it
--      buzzes, the list stays up); then at 3 BP, confirmed: every body
--      standing at the action lost its loot, the queue gained exactly the
--      rare-else-common of each body that had any, in slot order;
--      Ot6AnalyzeOne read every standing scannable body; 99 MP, the bank
--      paid three;
--   2. picked at 3 BP, taken back to 2 at target select: no body's loot
--      moved, the queue did not grow, no MP was charged, the bank paid two.
-- A battle with no loot on the field, or where LOCKE cannot act or lacks
-- 99 MP, is fought out and the next taken.
-- Old-ROM red and mutants: build/attempts/wt/v032-locke-kit/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, CMD, MARK = 0x01, 0x05, 0xE4
local MARK_MP = 99

local function ent(s) return 8 + s * 2 end
local function live(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 end
local function lootOf(s) return H.readByte(0x3308 + ent(s)), H.readByte(0x3309 + ent(s)) end
local function anyLoot()
  for s = 0, 5 do
    local r, c = lootOf(s)
    if live(s) and (r ~= 0xFF or c ~= 0xFF) then return true end
  end
  return false
end
local function queueN() return H.readByte(0x64DA) end
local function queueItem(i) return H.readByte(0x602D + (i & 15) * 5) end

local seat, rec, stage, battles, mode = nil, nil, 1, 0, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function lockeX() return (emu.getState()["cpu.x"] & 0xFF) == seat * 2 end
local function inProc(name, size)
  local st = emu.getState()
  local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
  local a = H.sym(name)
  return pc >= a and pc < a + size
end

local function arm()
  emu.addMemoryCallback(function()
    if seat == nil or rec ~= nil or not lockeX() or H.readByte(0xB6) ~= MARK then return end
    local e = seat * 2
    rec = { pend = H.readByte(0x3E9D + e), bank0 = H.readByte(0x3E9C + e), mp0 = H.readWord(0x3C08 + e),
      q0 = queueN(), f = H.frame, read = {}, bodies = {} }
    for s = 0, 5 do
      local r, c = lootOf(s)
      rec.bodies[s] = { live = live(s), rare = r, common = c, scan = (H.readByte(0x3C80 + ent(s)) & 0x10) == 0 }
    end
  end, emu.callbackType.exec, H.sym("Ot6ThiefExec"), H.sym("Ot6ThiefExec"))
  emu.addMemoryCallback(function(addr, v)
    if rec == nil or rec.ended or not inProc("Ot6AnalyzeOne", 76) then return end
    local o = addr - 0x7EED45
    local s = ((o >= 12) and o - 12 or o) // 2
    rec.read[s] = true
  end, emu.callbackType.write, 0x7EED45, 0x7EED5C)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil or not lockeX() then return end
    rec.ended = H.frame
  end, emu.callbackType.exec, ae, ae)
end
local function closed()
  if rec == nil or rec.ended == nil or H.frame <= rec.ended + 30 then return false end
  if rec.mp1 == nil then
    local e = seat * 2
    rec.mp1, rec.bank1, rec.q1 = H.readWord(0x3C08 + e), H.readByte(0x3E9C + e), queueN()
    rec.after = {}
    for s = 0, 5 do local r, c = lootOf(s); rec.after[s] = { rare = r, common = c } end
  end
  return true
end

local function judge()
  local r = rec
  local t = {}
  for s = 0, 5 do
    local b, a = r.bodies[s], r.after[s]
    if b.live then
      t[#t + 1] = string.format("%d:$%02X/$%02X->$%02X/$%02X%s", s, b.rare, b.common, a.rare, a.common,
        r.read[s] and " read" or "")
    end
  end
  H.log(string.format("[mark] stage %d: Master's Mark at %d BP (f%d): MP %d -> %d, bank %d -> %d, queue %d -> %d; %s",
    stage, r.pend, r.f, r.mp0, r.mp1, r.bank0, r.bank1, r.q0, r.q1, table.concat(t, " ")))
  if stage == 1 then
    local k = H.vars.kit
    H.assertEq(k[1] ~= nil and k[1].refusedSeen, true, "at 2 BP the row was refused at the list")
    H.assertEq(r.pend, 3, "the confirmed Master's Mark ran at 3 BP")
    local want = {}
    for s = 0, 5 do
      local b, a = r.bodies[s], r.after[s]
      if b.live then
        H.assertEq(a.rare == 0xFF and a.common == 0xFF, true, string.format("slot %d was robbed bare", s))
        if b.rare ~= 0xFF then want[#want + 1] = b.rare elseif b.common ~= 0xFF then want[#want + 1] = b.common end
        if b.scan then H.assertEq(r.read[s], true, string.format("slot %d was read (Ot6AnalyzeOne)", s)) end
      end
    end
    H.assertEq(r.q1 - r.q0, #want, string.format("the queue gained one item per body with loot (%d)", #want))
    for i, id in ipairs(want) do
      H.assertEq(queueItem(r.q0 + i - 1), id, string.format("queued item %d is $%02X: the body's rare, else its "
        .. "common", i, id))
    end
    H.assertEq(r.mp0 - r.mp1, MARK_MP, "Master's Mark cost 99 MP")
    H.assertEq(r.bank1, r.bank0 - 3, "the bank paid the full boost")
  else
    H.assertEq(H.vars.kit[1] ~= nil, true, "the take-back entry was played")
    H.assertEq(r.pend, 2, "taken back, the action ran at 2 BP")
    for s = 0, 5 do
      local b, a = r.bodies[s], r.after[s]
      if b.live then
        H.assertEq(a.rare == b.rare and a.common == b.common, true, string.format("slot %d's loot did not move", s))
      end
    end
    H.assertEq(r.q1, r.q0, "the queue did not grow")
    H.assertEq(r.mp0 - r.mp1, 0, "a Master's Mark under three points costs nothing")
    H.assertEq(r.bank1, r.bank0 - 2, "the bank paid the two points pending")
  end
  return true
end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= 20, true, "the two stages within 20 battles")
  seat, plan, mode, rec = nil, {}, "play", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == LOCKE then seat = s end end
  H.assertEq(seat ~= nil, true, "LOCKE is seated")
  local e = seat * 2
  local can = H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and H.readWord(0x3C08 + e) >= MARK_MP
  H.log(string.format("[mark] battle %d, stage %d: LOCKE seat %d MP %d bank %d; loot on the field %s", battles,
    stage, seat, H.readWord(0x3C08 + e), H.readByte(0x3E9C + e), tostring(anyLoot())))
  if not can or not anyLoot() then
    mode = "fightout"
    H.log("[mark] LOCKE cannot act, lacks 99 MP, or no body carries loot: fought out, the next battle taken")
    return
  end
  if stage == 1 then
    plan = { { who = LOCKE, cmd = CMD, row = MARK, boost = 2, refused = "list" },
             { who = LOCKE, cmd = CMD, row = MARK, boost = 3 } }
  else
    plan = { { who = LOCKE, cmd = CMD, row = MARK, boost = 3, takeBack = 2 } }
  end
end

local function onList(p, a)
  if p.boost ~= 2 or p.refused ~= "list" then return end
  H.assertEq(H.readByte(0x4005 + 7 * 3), MARK, "cell 7 holds Master's Mark ($E4): the Air Force is behind him")
  H.assertEq(H.readByte(0x4006 + 7 * 3), MARK_MP, "it draws 99 MP")
  H.screenshot("mastersmark_grey")
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    H.assertEq((H.readByte(0x1E80 + (0xA0 >> 3)) >> (0xA0 & 7)) & 1, 1, "switch $00A0 is set")
    arm()
  end),
  H.fcAlcoveToBattle("mark"),
  H.driveUntil(function() return stage > 2 end, 850000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("mark") }, {}),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
        planDone = closed }),
      H.call(function()
        if not closed() then
          H.log("[mark] the battle ended before the action resolved: not counted")
          return
        end
        if judge() then
          H.log(string.format("[mark] PASSED stage %d", stage))
          stage = stage + 1
        end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
    }),
  }, "the two stages"),
  H.call(function()
    H.log("[mark] PASS: under three points Master's Mark is refused; at three it robs every body of its best item "
      .. "and reads every body for 99 MP; taken back it does nothing and costs nothing")
  end),
})

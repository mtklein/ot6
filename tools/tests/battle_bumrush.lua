-- @suite slow
-- battle_bumrush.lua -- SABIN's divine, Bum Rush (#388): what a full boost buys him.
--
-- kits.md ("Divines", "Sabin"): the Blitz list's eighth row, taught by Duncan in the World of Ruin.  Its one gate
-- is three points pending (Ot6BushidoRowGrey's blitz arm greys it under three and the A button refuses it, the
-- grey Master's Mark and Jackpot take); at three it is the row at the full boost: four bludgeon blows
-- (Ot6HitCountTbl: the multi-attack counter $3a70 set to 3), each at Ot6BoostDmg's x8, for 99 MP.  Blitz commits
-- from the list (no target select), so a pick is never taken back; the command's own check (Ot6BlitzTake) turns
-- a copy read under three points (a Gogo's Mimic) into Pummel, and a random Blitz (Muddle, Charm, the
-- Colosseum) never picks it (Ot6RandBlitzBits, checked here in the built ROM).
--
-- Played: Continue wor-gau-v1 (SABIN, GAU, TERRA and CELES by Duncan's house, Bum Rush just taught), pace two
-- world tiles into a random battle, and play SABIN's turns through the real menu (H.kitBattle; Defends bank the
-- points, everyone else Defends).  Nothing is written.  Per battle, SABIN able to act and holding 99 MP:
--   1. the row at 2 BP: drawn at 99 MP, refused at the list (it buzzes, the list stays up); then at 3 BP,
--      confirmed: the command ran Bum Rush (Ot6BlitzTake left $b6 at $64) at 3 BP pending, set the multi-attack
--      counter to 3 (four blows) and landed at least one (Ot6HitJoin), cost 99 MP and the bank's three points;
--   2. a second Bum Rush in the next battle SABIN can afford one: the same (a divine is not once a battle, and the
--      bank, not a flag, paces it).
-- MP is a soft precondition, topped up the way a player would (field care between battles), and asserted at each
-- battle's start.  A battle SABIN cannot act in, or one that ends before the action resolves, is fought out and
-- not counted.
-- Old-ROM red and mutants: build/attempts/wt/v041-cleave-bumrush/bumrush/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local SABIN, CMD_BLITZ = 0x05, 0x0A
local BUMRUSH, PUMMEL = 0x64, 0x5D
local BUMRUSH_MP = 99

local seat, rec, recs, stage, battles, mode = nil, nil, {}, 1, 0, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function sabinX() return (emu.getState()["cpu.x"] & 0xFF) == seat * 2 end
local function sabinY() return (emu.getState()["cpu.y"] & 0xFF) == seat * 2 end

local function arm()
  -- the queue: Ot6AbilityCost prices SABIN's Blitz (cmd $0a in $3a7a, the row in $3a7b); the record opens here,
  -- before any charge, with the pool and the bank as the player left them
  local ac = H.sym("Ot6AbilityCost")
  emu.addMemoryCallback(function()
    if seat == nil or rec ~= nil or not sabinX() or H.readByte(0x3A7A) ~= CMD_BLITZ then return end
    local e = seat * 2
    rec = { row = H.readByte(0x3A7B), mp0 = H.readWord(0x3C08 + e), bank0 = H.readByte(0x3E9C + e),
      f = H.frame, sets = {}, hits = 0 }
  end, emu.callbackType.exec, ac, ac)
  -- the command: Ot6BlitzTake's entry (A = the blitz's id, y = the attacker), what it leaves in $b6 at
  -- Ot6HitCount's entry, and the pending boost the gate reads
  local take, hc = H.sym("Ot6BlitzTake"), H.sym("Ot6HitCount")
  emu.addMemoryCallback(function()
    if rec == nil or rec.cmdId ~= nil or not sabinY() then return end
    rec.cmdId = emu.getState()["cpu.a"] & 0xFF
    rec.pend = H.readByte(0x3E9D + seat * 2)
  end, emu.callbackType.exec, take, take)
  emu.addMemoryCallback(function()
    if rec == nil or rec.cmdId == nil or rec.ran ~= nil then return end
    rec.ran = H.readByte(0xB6)
  end, emu.callbackType.exec, hc, hc)
  emu.addMemoryCallback(function(_, v)
    if rec == nil or rec.ran == nil or rec.ended then return end
    if v ~= 0xFF then rec.sets[#rec.sets + 1] = v end
  end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  local join = H.sym("Ot6HitJoin")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ran == nil or rec.ended then return end
    rec.hits = rec.hits + 1
  end, emu.callbackType.exec, join, join)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil or not sabinX() or rec.ran == nil then return end
    rec.ended = H.frame
  end, emu.callbackType.exec, ae, ae)
end
local function closed()
  if rec == nil or rec.ended == nil or H.frame <= rec.ended + 30 then return false end
  if rec.mp1 == nil then
    local e = seat * 2
    rec.mp1, rec.bank1 = H.readWord(0x3C08 + e), H.readByte(0x3E9C + e)
  end
  return true
end

local function judge()
  local r = rec
  H.log(string.format("[bumrush] stage %d: queued $%02X (f%d), command $%02X at %d BP pending, ran $%02X; $3a70 "
    .. "set to {%s}; %d Ot6HitJoin pass(es); MP %d -> %d, bank %d -> %d", stage, r.row, r.f, r.cmdId or 0,
    r.pend or -1, r.ran or 0, table.concat(r.sets, ","), r.hits, r.mp0, r.mp1, r.bank0, r.bank1))
  if stage == 1 then
    local k = H.vars.kit
    H.assertEq(k[1] ~= nil and k[1].refusedSeen, true, "at 2 BP the Bum Rush row was refused at the list")
  end
  H.assertEq(r.row, BUMRUSH, "the queue holds Bum Rush ($64)")
  H.assertEq(r.cmdId, BUMRUSH, "the command entered with Bum Rush")
  H.assertEq(r.pend, 3, "at three points pending")
  H.assertEq(r.ran, BUMRUSH, "and ran Bum Rush, not the Pummel fallback (Ot6BlitzTake)")
  H.assertEq(#r.sets >= 1 and r.sets[1] == 3, true, "the multi-attack counter was set to 3: four blows "
    .. "(Ot6HitCountTbl)")
  H.assertEq(r.hits >= 1, true, "the blows landed (Ot6HitJoin)")
  H.assertEq(r.mp0 - r.mp1, BUMRUSH_MP, "Bum Rush cost 99 MP")
  H.assertEq(r.bank1, r.bank0 - 3, "the bank paid the full boost")
  return true
end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= 16, true, "the two Bum Rushes within 16 battles")
  seat, plan, mode, rec = nil, {}, "play", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == SABIN then seat = s end end
  H.assertEq(seat ~= nil, true, "SABIN is seated")
  local e = seat * 2
  local mp = H.readWord(0x3C08 + e)
  H.log(string.format("[bumrush] battle %d, stage %d: SABIN seat %d MP %d bank %d", battles, stage, seat, mp,
    H.readByte(0x3E9C + e)))
  H.assertEq(mp >= BUMRUSH_MP, true, "SABIN holds 99 MP at the battle's start (the field care before it)")
  local can = H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0x18) == 0
  if not can then
    mode = "fightout"
    H.log("[bumrush] SABIN cannot act here: this battle is fought out and the next one taken")
    return
  end
  if stage == 1 then
    -- (the refused entry is not `direct`: kitBattle closes a direct entry at its first A, refused or not)
    plan = { { who = SABIN, cmd = CMD_BLITZ, row = BUMRUSH, boost = 2, refused = "list" },
             { who = SABIN, cmd = CMD_BLITZ, row = BUMRUSH, boost = 3, direct = true } }
  else
    plan = { { who = SABIN, cmd = CMD_BLITZ, row = BUMRUSH, boost = 3, direct = true } }
  end
end

local function onList(p)
  if p.boost ~= 2 or p.refused ~= "list" then return end
  -- the list packs the learned blitzes in ladder order (Ot6BlitzListOpen), so Bum Rush is the last cell drawn
  local cell = nil
  for i = 0, 7 do if H.readByte(0x4005 + i * 3) == BUMRUSH then cell = i end end
  H.assertEq(cell ~= nil, true, "the list draws Bum Rush ($64)")
  H.assertEq(H.readByte(0x4006 + cell * 3), BUMRUSH_MP, "it draws 99 MP")
  H.screenshot("bumrush_grey")
end

local A, B = nil, nil
local function pace(what)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, what),
    H.waitUntil(function() return H.battleActive() end, 1200, what .. ": the battle is up", 2),
  })
end

-- the random Blitz's mask, in the built ROM: RandBlitz's first instruction is a jsl to Ot6RandBlitzBits, which
-- loads the known blitzes and clears bit 7 (Bum Rush) before RandBit picks
local function randBlitzCheck()
  local rb = H.sym("RandBlitz") & 0x3FFFFF
  local bits = H.sym("Ot6RandBlitzBits")
  H.assertEq(H.readRomByte(rb), 0x22, "RandBlitz opens with a jsl")
  local to = H.readRomByte(rb + 1) | (H.readRomByte(rb + 2) << 8) | (H.readRomByte(rb + 3) << 16)
  H.assertEq(to, bits, "to Ot6RandBlitzBits")
  local b = bits & 0x3FFFFF
  local got = {}
  for i = 0, 6 do got[#got + 1] = string.format("%02X", H.readRomByte(b + i)) end
  H.log("[bumrush] Ot6RandBlitzBits: " .. table.concat(got, " "))
  H.assertEq(table.concat(got, " "), "7B AD 28 1D 29 7F 6B",
    "Ot6RandBlitzBits is tdc / lda $1d28 / and #$7f / rtl: the known blitzes but Bum Rush")
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-gau-v1"),
  H.call(function()
    arm()
    randBlitzCheck()
    H.assertEq(H.readByte(0x1850 + SABIN) & 7, 1, "SABIN is seated (party 1)")
    H.assertEq(H.readByte(0x1D28) & 0x80, 0x80, "SABIN knows Bum Rush ($1D28 bit 7: Duncan, gen_wor_gau)")
    H.assertEq(H.worldMode(), true, "on the World of Ruin map")
    local x, y = H.worldX(), H.worldY()
    A = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if B == nil and H.worldPassable(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(B ~= nil, true, "a passable tile beside the party")
  end),
  H.driveUntil(function() return stage > 2 end, 550000, {
    H.cond(function() return not H.battleActive() end, {
      H.fieldCare({ threshold = 1.0, tag = "bumrush" }),
      pace("a random battle by Duncan's house"),
    }, {}),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
        planDone = closed }),
      H.call(function()
        if not closed() then
          H.log("[bumrush] the battle ended before the action resolved: not counted")
          return
        end
        if judge() then
          H.log(string.format("[bumrush] PASSED stage %d", stage))
          recs[#recs + 1] = rec
          stage = stage + 1
        end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
    }),
  }, "the two Bum Rushes"),
  H.call(function()
    H.log("[bumrush] PASS: under three points Bum Rush is refused at the list; at three it runs as four blows for "
      .. "99 MP and the full bank, again in a later battle; a random Blitz never picks it")
  end),
})

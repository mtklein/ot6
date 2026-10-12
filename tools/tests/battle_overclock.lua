-- @suite slow
-- battle_overclock.lua -- Edgar's Overclock: a 3-BP Tool fires twice (#378).
--
-- kits.md "Divines": a divine's one gate is a full 3-BP boost.  Overclock is
-- EDGAR's, learned at the Magitek factory (event switch $0068): a Tool he
-- boosts with all three points fires twice in the action, each firing a
-- whole pass at the boost's x8, and costs the two firings (each at the
-- 3-BP price, the sum capped at 99) -- Ot6Overclocks / Ot6ToolPrice /
-- Ot6OverclockPasses.  Under three points a Tool fires once at its
-- escalated price.
--
-- Played: Continue fc-alcove-v1 (EDGAR L27 with his bag's Tools, the
-- factory long behind him), walk onto the continent into a random battle,
-- and play EDGAR through the real menu (H.kitBattle); everyone else
-- Defends.  Nothing is written.  The Tool is AutoCrossbow ($AA, 4 MP, hits
-- every body), the bag's cheapest: 3 BP = 63, overclocked 99 (2 x 63,
-- capped).  EDGAR's pool here (201) pays two overclocks and nothing more
-- (a 0-BP AutoCrossbow beside them would be 202), so the one-firing control
-- is the old ROM's run of this suite and the mutant without the passes arm
-- (below), where the same 3-BP use fires once.  Asserted per use, from
-- Ot6ItemClass, called once per pass as each firing loads the tool:
--   1. AutoCrossbow at 3 BP: two firings, 99 MP;
--   2. again at 3 BP in the same battle: two firings, 99 MP.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/overclock/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, CMD_TOOLS, XBOW = 0x04, 0x09, 0xAA

local seat, recs, rec = nil, {}, nil
local function mp() return H.readWord(0x3C08 + seat * 2) end

local function arm()
  local ic = H.sym("Ot6ItemClass")
  emu.addMemoryCallback(function()
    if seat == nil then return end
    local a = emu.getState()["cpu.a"] & 0xff
    if a ~= XBOW or H.readByte(0x3A7C) ~= CMD_TOOLS then return end
    if rec == nil then
      local e = seat * 2
      rec = { pend = H.readByte(0x3E9D + e), mp0 = mp(), passes = 0, f = H.frame }
    end
    rec.passes = rec.passes + 1
  end, emu.callbackType.exec, ic, ic)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end
local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 1 then return false end
  rec.mp1 = mp()
  recs[#recs + 1] = rec
  H.log(string.format("[overclock] use %d: AutoCrossbow at %d BP (f%d): %d firing(s), MP %d -> %d", #recs,
    rec.pend, rec.f, rec.passes, rec.mp0, rec.mp1))
  rec = nil
  return true
end

local function use(boost)
  return H.kitBattle({ { who = EDGAR, cmd = CMD_TOOLS, row = XBOW, boost = boost } },
    { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = function() return close() end })
end

local function check(i, boost, firings, cost)
  local r = recs[i]
  H.assertEq(r ~= nil, true, string.format("use %d was recorded", i))
  H.assertEq(r.pend, boost, string.format("use %d ran at %d BP", i, boost))
  H.assertEq(r.passes, firings, string.format("AutoCrossbow at %d BP fired %d time(s)", boost, firings))
  H.assertEq(r.mp0 - r.mp1, cost, string.format("and cost %d MP", cost))
end

H.run({ maxFrames = 300000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (Overclock learned)")
  end),
  H.fcAlcoveToBattle("overclock"),
  H.call(function()
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == EDGAR then seat = s end end
    H.assertEq(seat ~= nil, true, "EDGAR is seated")
    H.assertEq(mp() >= 99 + 99, true, string.format("EDGAR's pool (%d MP) pays the two uses", mp()))
    H.log(string.format("[overclock] EDGAR seat %d, MP %d, bank %d", seat, mp(), H.readByte(0x3E9C + seat * 2)))
  end),
  use(3),
  H.call(function() check(1, 3, 2, 99) end),
  use(3),
  H.call(function()
    check(2, 3, 2, 99)
    H.log("[overclock] PASS: two firings at 3 BP, twice in the same battle, priced 99")
  end),
})

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
-- Defends.  Nothing is written.  The Tool is NoiseBlaster ($A3, 6 MP,
-- every body, no damage), so the battle stands for both uses (an
-- AutoCrossbow at x8 twice fells this map's smaller draws first), and its
-- 3-BP price sits under the cap where the doubling shows: 3 BP = 94,
-- overclocked 99 (2 x 94, capped).  EDGAR rests at the save first, so his pool pays two
-- overclocks and little more, so the one-firing control
-- is the old ROM's run of this suite and the mutant without the passes arm
-- (below), where the same 3-BP use fires once.  Asserted per use (the use
-- opens at its Ot6ItemClass load, every pass of it calls Ot6PassTargeted
-- after ChooseTarget with x = EDGAR, EDGAR's Ot6ActionEnd closes it):
--   1. NoiseBlaster at 3 BP: two firings, 99 MP;
--   2. again at 3 BP in the same battle: two firings, 99 MP.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_overclock.out).
--
-- The battle is whatever the continent deals (#468).  The Ninja pincer
-- (formation monsters $0003 $0003) can take a Defending party apart in the
-- rounds EDGAR banks for the second use: v0.36's sweep, shift 7, wiped it
-- after use 1 (build/attempts/wt/v036-fragile/A/logs/
-- battle_overclock__s7__k0.log.gz).  So the others Defend only while the
-- party holds: once a seated member falls under a third of their max HP (or
-- down), the battle is handed to the route's fight driver (tactical, boost,
-- items, its in-battle heals), which fights it out; the uses that battle
-- recorded are set aside (both must come from one battle), the party is
-- cared for at the save-point band again, and the next encounter is walked
-- into.  At most MAX_ENCOUNTERS; a battle with both uses is asserted as
-- before.  The budget: in the sweep of this fix (shifts 0/7/13, 0-3
-- encounters used up first), 7 of 19 battles were handed over (Ninjas,
-- Dragon, Behemoth, Brainpans; one run needed its 4th encounter), so
-- eight leave about 0.37^8, under one run in 2000, to luck
-- (build/attempts/wt/v036-fragile-fix/g1/full2/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, CMD_TOOLS, TOOL = 0x04, 0x09, 0xA3   -- NoiseBlaster: no damage, so the battle stands

local seat, recs, rec = nil, {}, nil
local MAX_ENCOUNTERS = 8
local enc, handed = 0, nil         -- the encounter in use; why its battle was handed over
local DANGER = 1 / 3                 -- a seated member under this share of max HP hands the battle over
local function mp() return H.readWord(0x3C08 + seat * 2) end

local function arm()
  local ic = H.sym("Ot6ItemClass")
  emu.addMemoryCallback(function()
    if seat == nil then return end
    local a = emu.getState()["cpu.a"] & 0xff
    if a ~= TOOL or H.readByte(0x3A7C) ~= CMD_TOOLS then return end
    if rec == nil then
      local e = seat * 2
      rec = { pend = H.readByte(0x3E9D + e), mp0 = mp(), passes = 0, f = H.frame }
    end
  end, emu.callbackType.exec, ic, ic)
  -- one call per pass: CalcAttackEffect's Ot6PassTargeted, after ChooseTarget
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.passes = rec.passes + 1 end
  end, emu.callbackType.exec, pt, pt)
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
  H.log(string.format("[overclock] use %d: NoiseBlaster at %d BP (f%d): %d firing(s), MP %d -> %d", #recs,
    rec.pend, rec.f, rec.passes, rec.mp0, rec.mp1))
  rec = nil
  return true
end

-- why the party can no longer Defend through EDGAR's banking, or nil: a
-- seated member down, or under DANGER of max HP
local function danger()
  if not H.battleLoadStarted() then return nil end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local hp, mx, st1 = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2), H.readByte(0x3EE4 + s * 2)
      if hp == 0 or (st1 & 0xC2) ~= 0 or (mx > 0 and hp < mx * DANGER) then
        return string.format("seat %d at %d/%d HP, status1 $%02X", s, hp, mx, st1)
      end
    end
  end
  return nil
end

local function use(boost)
  local ended = false
  return H.withReset(H.driveUntil(function()
    if ended then return true end
    if handed == nil then handed = danger() end
    return handed ~= nil
  end, 70000, {
    H.kitBattle({ { who = EDGAR, cmd = CMD_TOOLS, row = TOOL, boost = boost } },
      { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = function() return close() end }),
    H.call(function() ended = true end),
  }, "a 3-BP NoiseBlaster use, or the party in danger"), function() ended = false end)
end

-- the route's fight driver fights the battle out from wherever it stands
local function fightOut(tag)
  local F = nil
  return H.withReset(H.driveUntil(function() return not H.battleLoadStarted() end, 60000, {
    H.call(function()
      if F == nil then
        F = H.newFightDriver(tag, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55,
          setzer = false })
      end
      F.frame()
    end),
  }, tag .. ": the battle fought out"), function() if F then F.idle() end; F = nil end)
end

local function check(i, boost, firings, cost)
  local r = recs[i]
  H.assertEq(r ~= nil, true, string.format("use %d was recorded", i))
  H.assertEq(r.pend, boost, string.format("use %d ran at %d BP", i, boost))
  H.assertEq(r.passes, firings, string.format("the Tool at %d BP fired %d time(s)", boost, firings))
  H.assertEq(r.mp0 - r.mp1, cost, string.format("and cost %d MP", cost))
end

-- encounter e: care at the save-point band, the walk in, the two uses; a
-- battle handed over (danger()) is fought out and owes nothing
local function encounter(e)
  return H.cond(function() return #recs < 2 end, {
    H.call(function() enc, handed, rec, recs = e, nil, nil, {} end),
    -- the two uses take 198 MP, and what the alcove's save holds is the
    -- route's draw (164 of EDGAR's 230 in the v0.29 kits qualification,
    -- build/attempts/wt/v029-kits/qual/): at the save point a person rests
    -- first, so the care's MP band is set where his pool pays them (a Tent,
    -- or Tinctures); after a handed-over battle the same care again
    H.fieldCare({ tag = "overclock: rest for two overclocks (encounter " .. e .. ")", threshold = 0.95,
      mpBand = 0.9 }),
    e == 1 and H.fcAlcoveToBattle("overclock") or H.fcPace("overclock"),
    H.call(function()
      seat = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == EDGAR then seat = s end end
      H.assertEq(seat ~= nil, true, "EDGAR is seated")
      H.assertEq(mp() >= 99 + 99, true, string.format("EDGAR's pool (%d MP) pays the two uses", mp()))
      local fw = H.formationWords()
      H.log(string.format("[overclock] encounter %d (formation %04X %04X %04X %04X %04X %04X): EDGAR seat %d, "
        .. "MP %d, bank %d", e, fw[1], fw[2], fw[3], fw[4], fw[5], fw[6], seat, mp(), H.readByte(0x3E9C + seat * 2)))
    end),
    use(3),
    H.cond(function() return handed == nil end, {
      H.call(function() check(1, 3, 2, 99) end),
      use(3),
    }, {}),
    H.cond(function() return handed ~= nil end, {
      H.call(function()
        H.log(string.format("[overclock] encounter %d handed to the fight driver after %d use(s): %s", e, #recs,
          handed))
        rec, recs = nil, {}
      end),
      fightOut("overclock: encounter " .. e),
    }, {
      H.call(function() check(2, 3, 2, 99) end),
    }),
  }, {})
end

local body = {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (Overclock learned)")
  end),
}
for e = 1, MAX_ENCOUNTERS do body[#body + 1] = encounter(e) end
body[#body + 1] = H.call(function()
  H.assertEq(#recs, 2, string.format("a battle held both 3-BP uses within %d encounters", MAX_ENCOUNTERS))
  H.log(string.format("[overclock] PASS: two firings at 3 BP, twice in the same battle (encounter %d), priced 99",
    enc))
end)
H.run({ maxFrames = 400000 }, body)

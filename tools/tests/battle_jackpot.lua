-- @suite savestate=wor_grave slow
-- battle_jackpot.lua -- SETZER's divine, Jackpot (#319, kits.md "Setzer"):
-- the Fixed Dice come up a triple, a roll more a Boost Point, 99 MP, once a
-- battle, and no chip.
--
-- Played, not staged: wor_grave is gen_wor_falcon's own frame on Daryl's
-- grave (the party armed and cared for, the gil's digit settled, before
-- the press), reached by play from the wor-tomb-v1 battery; SETZER rejoined
-- in the World of Ruin there (event switch $00CA), so Jackpot is learned.
-- Three passes from that frame, each pressing the grave and playing SETZER
-- through the real menu (H.setzerBattle) against Dullahan (23,450 HP, ten
-- shields):
--   pass 1: Defend twice (the bank to 3), Jackpot at 3 BP: four rolls;
--   pass 2: Jackpot at 1 BP (two rolls), then Jackpot again;
--   pass 3: Defend once, Jackpot unboosted (one roll), then Jackpot again.
-- What it holds, per Jackpot (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd; each roll as the effect sets the dice animation):
--   * 1 + boost rolls (the boost buys rolls: owner, 2026-10-02), fewer only
--     when the last body has fallen;
--   * each roll three dice of one face (b7 = face-1 in both nybbles, b6 =
--     face-1), the face 1-6, its damage face^3 x level x 2 times the face
--     (vanilla's Fixed Dice arithmetic, saturating at 65,535), and what it
--     landed: that, halved while the body's shields hold, doubled once
--     Broken, capped at 9,999 and at the HP the roll found;
--   * null-break: every roll's class is special | null-break ($88) and no
--     monster's shields move;
--   * 99 MP whatever the boost, no gil, the bank less the boost, and the
--     once-a-battle flag (OT6_DIVINE_USED) set for SETZER by it;
--   * the second Jackpot of the battle is refused at the list: three A
--     presses, the list stays up, nothing is queued.
-- The face odds are a distribution: measured by the lab in
-- build/attempts/wt/kit-setzer/jackpot-dist/, not by these draws.
-- The run ends once the plan is spent; Dullahan's fight is not finished.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"

local JACKPOT = 0x5B
local DULLAHAN = 0x11C

local function checkJackpot(r, i)
  H.log(string.format("[jackpot] %d at %d BP, L%d: %d roll(s); MP %d -> %d, purse %d -> %d, bank %d -> %d, "
    .. "divine %02X -> %02X", i, r.boost, r.level, #r.dice, r.mp0, r.mp1, r.gil0, r.gil1, r.bank0, r.bank1,
    r.divine0, r.divine1))
  H.assertEq(r.mp0 - r.mp1, 99, string.format("Jackpot %d: 99 MP, whatever the boost", i))
  H.assertEq(r.gil1, r.gil0, string.format("Jackpot %d: no gil", i))
  H.assertEq(r.bank1, r.boost == 0 and math.min(5, r.bank0 + 1) or r.bank0 - r.boost,
    string.format("Jackpot %d: the bank less the boost (or +1, unboosted)", i))
  H.assertEq(r.divine0 & r.setzerBit, 0, string.format("Jackpot %d: unspent before", i))
  H.assertEq(r.divine1 & r.setzerBit, r.setzerBit, string.format("Jackpot %d: spent by it", i))
  H.assertEq(r.targets ~= 0, true, string.format("Jackpot %d was aimed at the monsters", i))
  for b = 0, 5 do
    if r.mon0[b].present then
      H.assertEq(r.mon1[b].sh, r.mon0[b].sh, string.format("Jackpot %d: slot %d's shields do not move", i, b))
    end
  end
  local alive = 0
  for b = 0, 5 do if r.mon1[b].present and r.mon1[b].hp > 0 then alive = alive + 1 end end
  if alive > 0 then
    H.assertEq(#r.dice, 1 + r.boost, string.format("Jackpot %d: 1 + boost rolls (%d BP)", i, r.boost))
  else
    H.assertEq(#r.dice >= 1 and #r.dice <= 1 + r.boost, true, string.format("Jackpot %d: rolls until the last "
      .. "body fell", i))
  end
  for k, d in ipairs(r.dice) do
    local f = d.b6 + 1
    H.assertEq(d.b7, (d.b6 << 4) | d.b6, string.format("Jackpot %d, roll %d: three dice of one face", i, k))
    H.assertEq(f >= 1 and f <= 6, true, string.format("Jackpot %d, roll %d: a face 1-6 (%d)", i, k, f))
    local dmg = math.min(65535, f * f * f * r.level * 2 * f)
    H.assertEq(d.dmg, dmg, string.format("Jackpot %d, roll %d: the triple's damage, face %d^4 x level %d x 2", i, k,
      f, r.level))
    H.assertEq(d.class, 0x88, string.format("Jackpot %d, roll %d: special | null-break", i, k))
    -- what it landed: the HP the roll found against the next roll's (or the end's)
    local post = r.dice[k + 1] and r.dice[k + 1].hp or (function()
      local t = {} for b = 0, 5 do t[b] = r.mon1[b].hp end return t end)()
    local hit, drop = nil, 0
    for b = 0, 5 do
      if d.hp[b] ~= post[b] then H.assertEq(hit, nil, "one body a roll"); hit, drop = b, d.hp[b] - post[b] end
    end
    H.assertEq(hit ~= nil, true, string.format("Jackpot %d, roll %d landed on a body", i, k))
    if k == 1 then
      H.assertEq((r.targets >> hit) & 1, 1, string.format("Jackpot %d: the first roll lands inside the aimed mask "
        .. "$%02X (slot %d)", i, r.targets, hit))
    end
    local o = r.mon0[hit]
    local want = dmg
    if o.brk == 0 and o.sh > 0 then want = (want * 8) >> 4 elseif o.brk ~= 0 and want < 32768 then want = want * 2 end
    want = math.min(want, 9999, d.hp[hit])
    H.log(string.format("[jackpot]   roll %d: face %d, dmg %d, slot %d HP %d -> %d (want -%d), shields %d, broken %d",
      k, f, d.dmg, hit, d.hp[hit], post[hit], want, o.sh, o.brk))
    H.assertEq(drop, want, string.format("Jackpot %d, roll %d: what it landed on slot %d", i, k, hit))
  end
end

local function pass(n, plan, wantBoost)
  local recs
  return H.seqStep({
    H.loadState(STATE),
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, 299, "wor_grave stands in the grave's room (map 299)")
      H.assertEq(H.readByte(0x1E99) & 0x04, 0x04, "SETZER has rejoined in the World of Ruin (switch $00CA)")
    end),
    H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave (100,14): face up, A"),
    H.release(),
    H.setzerBattle(plan, { untilPlanDone = true, shot = "jackpot_table_" .. n }),
    H.call(function()
      local ids = {}
      for _, s in ipairs(H.formationSpecies()) do ids[#ids + 1] = s.species end
      H.assertEq(ids[1], DULLAHAN, "the grave's fight is Dullahan")
      recs = H.vars.setzer
      H.assertEq(#recs, 1, string.format("pass %d: exactly one Jackpot resolved", n))
      H.assertEq(recs[1].row, JACKPOT, string.format("pass %d: the row is Jackpot", n))
      H.assertEq(recs[1].boost, wantBoost, string.format("pass %d: at %d BP", n, wantBoost))
      checkJackpot(recs[1], n)
      if plan[#plan].refused then
        H.assertEq(plan[#plan].refusedSeen == true, true,
          string.format("pass %d: the second Jackpot was refused at the list", n))
      end
      local faces = {}
      for _, d in ipairs(recs[1].dice) do faces[#faces + 1] = d.b6 + 1 end
      H.log(string.format("[jackpot] pass %d held: faces %s at %d BP%s", n, table.concat(faces, ","), wantBoost,
        plan[#plan].refused and "; the second Jackpot refused" or ""))
    end),
  })
end

H.run({ maxFrames = 90000 }, {
  pass(1, { { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 } }, 3),
  pass(2, { { row = JACKPOT, boost = 1 }, { row = JACKPOT, refused = true } }, 1),
  pass(3, { { row = "defend" }, { row = JACKPOT, boost = 0 }, { row = JACKPOT, refused = true } }, 0),
  H.call(function()
    H.log("[jackpot] PASSED: 1 + boost rolls at 3, 1 and 0 BP, 99 MP, no chip, once a battle")
  end),
})

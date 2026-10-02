-- @suite savestate=wor_grave slow
-- battle_jackpot.lua -- SETZER's divine, Jackpot (#319, kits.md "Setzer"):
-- the Fixed Dice come up a triple, the boost floors the face, 99 MP, once a
-- battle, and no chip.
--
-- Played, not staged: wor_grave is gen_wor_falcon's own frame on Daryl's
-- grave (the party armed and cared for, the gil's digit settled, before
-- the press), reached by play from the wor-tomb-v1 battery; SETZER rejoined
-- in the World of Ruin there (event switch $00CA), so Jackpot is learned.
-- Three passes from that frame, each pressing the grave and playing SETZER
-- through the real menu (H.setzerBattle) against Dullahan, whose 23,450 HP
-- and ten shields outlast one Jackpot, so the second try comes:
--   pass 1: Defend twice (the bank to 3), Jackpot at 3 BP, Jackpot again;
--   pass 2: Jackpot at 1 BP, Jackpot again;
--   pass 3: Defend once, Jackpot unboosted, Jackpot again.
-- What it holds, per Jackpot (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd; the dice as the effect sets the dice animation):
--   * three dice of one face (b7 = face-1 in both nybbles, b6 = face-1),
--     the face at least 4 / 2 / 1 for 3 / 1 / 0 BP: the floor the boost
--     buys, one face a point.  The odds above the floor (even, from the
--     floor to six) are a distribution, measured by the lab in
--     build/attempts/wt/kit-setzer/jackpot-dist/, not by these draws;
--   * the damage set: face^3 x level x 2, times the face for the triple
--     (vanilla's Fixed Dice arithmetic), saturating at 65,535;
--   * the target's HP falls by that, halved while its shields hold, doubled
--     once Broken, capped at 9,999 and at the HP it had;
--   * null-break: the class is special | null-break ($88) and no monster's
--     shields move;
--   * 99 MP, no gil, the bank less the boost, and the once-a-battle flag
--     (OT6_DIVINE_USED) set for SETZER by it;
--   * the second Jackpot of the battle is refused at the list: three A
--     presses, the list stays up, nothing is queued.
-- The run ends once the plan is spent; Dullahan's fight is not finished.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"

local JACKPOT = 0x5B
local FLOOR = { [0] = 1, 2, 3, 4 }   -- the lowest face per boost point (kits.md)
local DULLAHAN = 0x11C

local function checkJackpot(r, i)
  H.log(string.format("[jackpot] %d at %d BP, L%d: dice b6=%s b7=%s dmg %s class %s; MP %d -> %d, purse %d -> %d, "
    .. "bank %d -> %d, divine %02X -> %02X", i, r.boost, r.level, tostring(r.b6), tostring(r.b7), tostring(r.dmg),
    tostring(r.class), r.mp0, r.mp1, r.gil0, r.gil1, r.bank0, r.bank1, r.divine0, r.divine1))
  H.assertEq(r.b6 ~= nil, true, string.format("Jackpot %d set the dice animation", i))
  local f = r.b6 + 1
  H.assertEq(r.b7, (r.b6 << 4) | r.b6, string.format("Jackpot %d: three dice of one face", i))
  H.assertEq(f >= FLOOR[r.boost] and f <= 6, true,
    string.format("Jackpot %d: face %d at %d BP is at least %d", i, f, r.boost, FLOOR[r.boost]))
  local dmg = math.min(65535, f * f * f * r.level * 2 * f)
  H.assertEq(r.dmg, dmg, string.format("Jackpot %d: the triple's damage, face %d^4 x level %d x 2", i, f, r.level))
  H.assertEq(r.class, 0x88, string.format("Jackpot %d: special | null-break", i))
  H.assertEq(r.mp0 - r.mp1, 99, string.format("Jackpot %d: 99 MP", i))
  H.assertEq(r.gil1, r.gil0, string.format("Jackpot %d: no gil", i))
  H.assertEq(r.bank1, r.boost == 0 and math.min(5, r.bank0 + 1) or r.bank0 - r.boost,
    string.format("Jackpot %d: the bank less the boost (or +1, unboosted)", i))
  H.assertEq(r.divine0 & r.setzerBit, 0, string.format("Jackpot %d: unspent before", i))
  H.assertEq(r.divine1 & r.setzerBit, r.setzerBit, string.format("Jackpot %d: spent by it", i))
  local s = nil
  for b = 0, 5 do if (r.targets >> b) & 1 == 1 then H.assertEq(s, nil, "one target"); s = b end end
  H.assertEq(s ~= nil, true, string.format("Jackpot %d hit a monster", i))
  for b = 0, 5 do
    if r.mon0[b].present then
      H.assertEq(r.mon1[b].sh, r.mon0[b].sh, string.format("Jackpot %d: slot %d's shields do not move", i, b))
    end
  end
  local o, m = r.mon0[s], r.mon1[s]
  local d = dmg
  if o.brk == 0 and o.sh > 0 then d = (d * 8) >> 4 elseif o.brk ~= 0 and d < 32768 then d = d * 2 end
  d = math.min(d, 9999, o.hp)
  H.log(string.format("[jackpot]   slot %d: HP %d -> %d (want -%d), shields %d, broken %d", s, o.hp, m.hp, d,
    o.sh, o.brk))
  H.assertEq(o.hp - m.hp, d, string.format("Jackpot %d: the hit on slot %d", i, s))
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
      H.assertEq(plan[#plan].refusedSeen == true, true,
        string.format("pass %d: the second Jackpot was refused at the list", n))
      H.log(string.format("[jackpot] pass %d held: face %d at %d BP; the second Jackpot refused", n,
        recs[1].b6 + 1, wantBoost))
    end),
  })
end

H.run({ maxFrames = 90000 }, {
  pass(1, { { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 },
            { row = JACKPOT, refused = true } }, 3),
  pass(2, { { row = JACKPOT, boost = 1 }, { row = JACKPOT, refused = true } }, 1),
  pass(3, { { row = "defend" }, { row = JACKPOT, boost = 0 }, { row = JACKPOT, refused = true } }, 0),
  H.call(function()
    H.log("[jackpot] PASSED: the 3, 1 and 0 BP floors, 99 MP, no chip, once a battle")
  end),
})

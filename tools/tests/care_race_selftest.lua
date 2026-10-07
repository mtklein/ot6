-- @manual standalone: lua tools/tests/care_race_selftest.lua
-- care_race_selftest.lua -- the care race (#415, docs/design/care-race.md):
-- the old care rules' measured cases as race states, and the decision each
-- should come to.  No emulator: M.raceSim / M.raceChoose are arithmetic.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local n = 0
local function check(ok, what) assert(ok, what); n = n + 1 end

-- a line at boost 0..3: Fight-like, `per` shielded-equivalent a hit
local function lines(per, hits, chips)
  local t = {}
  for b = 0, 3 do t[b] = { per = per * (1 + b), hits = hits, chips = chips } end
  return t
end
local function member(hp, maxhp, eta, o)
  o = o or {}
  return { hp = hp, maxhp = maxhp, eta = eta, period = o.period or 300, bp = o.bp or 0,
           lines = o.lines or lines(100, 1, 1), heals = o.heals or {}, deathCost = o.deathCost or 1500 }
end
local function choose(st, cands)
  local i, r, all = H.raceChoose(st, cands)
  return cands[i], r, all
end

-- 1. The Gate's LOCKE (#312/#402): 144/820 under a 286 round, an X-Potion
-- (676) in hand that lifts him; the enemy has 3000 HP behind 3 shields.
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(144, 820, 0, { lines = lines(150, 1, 1) }), member(700, 900, 150), member(650, 800, 220) },
    enemies = { { hp = 3000, sh = 3, eta = 100, period = 300, ends = true,
                  act = { aoe = false, dmg = { 286, 286, 286 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 1, restore = 676, cost = 2000 } })
  check(c.kind == "heal", "the Gate's LOCKE at 144/820 under 286: the lifting X-Potion stands, got " .. c.kind)
end

-- 2. #414's review case: a member at 357/1130 under an 838 round, an
-- X-Potion's 773 lifts her; the alternative is a Tools turn chipping nothing
do
  local st = { actor = 2, hpRate = 1.2, focus = { 1 },
    party = { member(900, 1039, 200), member(357, 1130, 0, { bp = 3, lines = lines(80, 3, 0) }), member(1000, 1215, 250) },
    enemies = { { hp = 8000, sh = 8, eta = 60, period = 280, ends = true,
                  act = { aoe = true, dmg = { 420, 838, 450 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[2].lines[3], boost = 3 },
    { kind = "heal", target = 2, restore = 773, cost = 2000 } })
  check(c.kind == "heal", "357/1130 under an 838 round, an X-Potion's 773: the heal stands, got " .. c.kind)
end

-- 3. The lift (#312): a 250 Potion on a member at 523 under a 905 round
-- leaves her inside it -- the heal prevents nothing, the turn attacks
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 }, contCare = false,
    party = { member(900, 1000, 0, { lines = lines(300, 1, 1) }), member(523, 1100, 200) },
    enemies = { { hp = 2000, sh = 1, eta = 50, period = 300, ends = true,
                  act = { aoe = false, dmg = { 400, 905 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 2, restore = 250, cost = 300 } })
  check(c.kind == "attack", "a 250 Potion on 523 under 905 lifts nothing: attack, got " .. c.kind)
end

-- 4. Spend before dying (#175): EDGAR at 240/1048 inside a 729 round with
-- 3 BP; the Potion does not save him; the 3-BP line beats the 0-BP one
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 }, contCare = false,
    party = { member(240, 1048, 0, { bp = 3, lines = lines(400, 3, 1) }), member(900, 1129, 150) },
    enemies = { { hp = 6000, sh = 3, eta = 80, period = 300, ends = true,
                  act = { aoe = true, dmg = { 729, 500 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "attack", line = st.party[1].lines[3], boost = 3 },
    { kind = "heal", target = 1, restore = 250, cost = 300 } })
  check(c.kind == "attack" and c.boost == 3, "240/1048 inside 729 with 3 BP: spend them, got "
    .. c.kind .. " " .. tostring(c.boost))
end

-- 5. The finisher (#204): the enemy dies to this turn's attack
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(500, 1000, 0, { lines = lines(300, 1, 1) }), member(400, 900, 100) },
    enemies = { { hp = 250, sh = 0, eta = 40, period = 300, ends = true,
                  act = { aoe = true, dmg = { 300, 300 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 2, restore = 250, cost = 300 } })
  check(c.kind == "attack", "the kill this turn goes first, got " .. c.kind)
end

-- 6. A raise that dies again (#374): Fenix Down's 1/8 (300 of 2400) under
-- a 600 AoE coming before the raised member can act -- attack instead; and
-- a raise that stands (the AoE is 30) -- raise
do
  local function st(aoe)
    return { actor = 1, hpRate = 1.2, focus = { 1 }, contCare = false,
      party = { member(1800, 2000, 0, { lines = lines(200, 1, 1) }), member(0, 2400, 300) },
      enemies = { { hp = 5000, sh = 2, eta = 50, period = 400, ends = true,
                    act = { aoe = true, dmg = { aoe, aoe } } } } }
  end
  local s1 = st(600)
  local c = choose(s1, { { kind = "attack", line = s1.party[1].lines[0], boost = 0 },
                         { kind = "raise", target = 2, hp = 300, cost = 500 } })
  check(c.kind == "attack", "a raise to 300 under a 600 AoE dies again: attack, got " .. c.kind)
  local s2 = st(30)
  c = choose(s2, { { kind = "attack", line = s2.party[1].lines[0], boost = 0 },
                   { kind = "raise", target = 2, hp = 300, cost = 500 } })
  check(c.kind == "raise", "a raise that stands under a 30 AoE: raise, got " .. c.kind)
end

-- 7. Scarcity: two heals that both lift -- the last Elixir before a boss
-- is dear, the 40th Potion cheap
do
  check(H.raceItemCost(300, 40, 4) == 300, "the 40th Potion at its gil")
  check(H.raceItemCost(300, 1, 4) > 3 * 300, "the last one, reserve 4: over three times its gil")
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(900, 1000, 0), member(200, 1000, 150) },
    enemies = { { hp = 9000, sh = 8, eta = 40, period = 300, ends = true,
                  act = { aoe = false, dmg = { 50, 50 } } } } }
  local c = choose(st, {
    { kind = "heal", target = 2, restore = 800, cost = H.raceItemCost(4000, 1, 2), item = "elixir" },
    { kind = "heal", target = 2, restore = 250, cost = H.raceItemCost(300, 40, 4), item = "potion" } })
  check(c.item == "potion", "both lift: the plentiful Potion, not the last Elixir, got " .. tostring(c.item))
end

-- 8. The aftermath: two turns that end the fight inside the margin; the
-- one that leaves the party whole costs less to restore
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 }, contCare = false,
    party = { member(900, 1000, 0, { lines = lines(500, 1, 0) }), member(200, 1000, 100, { lines = lines(500, 1, 0) }) },
    enemies = { { hp = 900, sh = 0, eta = 500, period = 600, ends = true,
                  act = { aoe = true, dmg = { 50, 50 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 2, restore = 800, cost = 300 } })
  -- the attack (4x on the bare body: 2000) kills at t=0; the heal leaves
  -- the kill to the ally at t=100, inside the margin (600): the cheaper bill
  check(c.kind == "heal", "a kill 100 ticks later with the party whole beats the kill now at 200/1000, got " .. c.kind)
end

-- 9. The horizon sees past the next hit: a member at 400 under 286 hits
-- dies on the second; the heal that delays it is seen only by a race that
-- plays more than one enemy action
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 }, contCare = false,
    party = { member(1000, 1000, 0, { lines = lines(150, 1, 1) }), member(400, 1100, 900) },
    enemies = { { hp = 6000, sh = 4, eta = 50, period = 300, ends = true,
                  act = { aoe = false, dmg = { 286, 286 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 2, restore = 676, cost = 2000 } })
  check(c.kind == "heal", "a death on the second hit is put off by the heal, got " .. c.kind)
end

-- 10. The score's order: no wipe, then deaths, then the kill, then the cost
do
  local st = { enemies = { { period = 300 } } }
  local function r(t) t.left = t.left or 1000; t.left0 = 2000; t.cost = t.cost or 0; return t end
  check(H.raceBetter(r({ deaths = 0 }), r({ deaths = 1, kill = 100, firstDeath = 50 }), st),
    "no death beats a kill with a death")
  check(H.raceBetter(r({ deaths = 1, firstDeath = 900 }), r({ deaths = 1, firstDeath = 100 }), st),
    "the later first death")
  check(H.raceBetter(r({ deaths = 0, wipe = false }), r({ deaths = 0, wipe = true, kill = 10 }), st),
    "no wipe first")
  check(H.raceBetter(r({ deaths = 0, kill = 100, cost = 900 }), r({ deaths = 0, kill = 1000, cost = 0 }), st),
    "the kill sooner by more than the margin beats the cheaper")
end

-- 11. A Fight that lands half the time (#415, M.hitChance): the member at
-- 400/1000 under a 450 hit would kill with two landed swings before the
-- enemy acts; at 1 in 2 the race lifts him first
do
  check(H.hitChance(255, 0) == 1, "hit rate $FF always lands")
  check(H.hitChance(200, 128) == 1 and H.hitChance(100, 128) == 0.5, "hit rate x block / 256, out of 100")
  local function st(hit)
    local l = lines(400, 2, 0)
    for b = 0, 3 do l[b].hit = hit end
    return { actor = 1, hpRate = 1.2, focus = { 1 },
      party = { member(400, 1000, 0, { lines = l }), member(900, 900, 280) },
      enemies = { { hp = 800, sh = 1, eta = 60, period = 300, ends = true,
                    act = { aoe = false, dmg = { 450, 450 } } } } }
  end
  local function c(s)
    return choose(s, { { kind = "attack", line = s.party[1].lines[0], boost = 0 },
      { kind = "heal", target = 1, restore = 600, cost = 300 } }).kind
  end
  check(c(st(1)) == "attack", "two sure swings end it")
  check(c(st(H.hitChance(100, 128))) == "heal", "half of them land: lift first")
end

-- 12. A heal that only trades its gil for the aftermath's (#415 lab, the
-- Gate: an Elixir priced at a few gil won 30 of 33 decisions): a 100-HP
-- top-up at 30 gil saves 120 of the bill, 90 net, inside the 200-gil
-- margin, so the kill a turn sooner stands
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(800, 1000, 0, { lines = lines(100, 1, 1) }), member(900, 900, 2000) },
    enemies = { { hp = 250, sh = 1, eta = 350, period = 400, ends = true,
                  act = { aoe = false, dmg = { 10, 10 } } } } }
  local c = choose(st, {
    { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 1, restore = 100, cost = 30 } })
  check(c.kind == "attack", "a 90-gil trade does not buy a turn, got " .. c.kind)
end

-- 13. Calibration (#415 review): an enemy action is priced at its typical
-- landed hit, aimed as the game aims it, with the worst case kept only as
-- the no-wipe guard.  The Air Force's log read "WIPE, 3 down" in fights
-- the party won, from every slot's worst hit on the member it left lowest.
do
  local function party3(lowHp)
    return { member(lowHp, 1000, 0, { lines = lines(100, 1, 1) }), member(1000, 1000, 400), member(1000, 1000, 450) }
  end
  local function pick(st)
    return choose(st, {
      { kind = "attack", line = st.party[1].lines[0], boost = 0 },
      { kind = "heal", target = 1, restore = 500, cost = 100 },
      { kind = "heal", all = true, restore = 600, cost = 300 } }).kind
  end
  -- (a) worst 900 once, 300 typically: a member at 500 is not in danger
  local st = { actor = 1, hpRate = 0, focus = { 1 }, party = party3(650),
    enemies = { { hp = 700, sh = 0, eta = 50, period = 300, ends = true,
                  act = { dmg = { 300, 300, 300 }, worst = { 900, 900, 900 } } } } }
  check(pick(st) == "attack", "a 900 worst with a 300 typical hit does not heal a member at 650 (two typical hits before the kill)")
  -- (b) the script's fixed target: a member at 200 the enemy never aims at
  st = { actor = 1, hpRate = 0, focus = { 1 }, party = party3(200),
    enemies = { { hp = 700, sh = 0, eta = 50, period = 300, ends = true,
                  act = { dmg = { 300, 300, 300 }, aim = 2 } } } }
  check(pick(st) == "attack", "an enemy aimed at a full member leaves the one at 200 be")
  st.enemies[1].act.aim = nil
  check(pick(st) ~= "attack", "aimed at random, the member at 200 is one draw in three from dying")
  -- (c) the guard: typically 100 a member, at worst 700 on everyone; two
  -- members at 600 and one at 650 -- the worst case wipes unless a
  -- heal lifts one, the typical play loses no one either way
  st = { actor = 1, hpRate = 0, focus = { 1 },
    party = { member(600, 1000, 0, { lines = lines(100, 1, 1) }), member(600, 1000, 400), member(650, 1000, 450) },
    enemies = { { hp = 700, sh = 0, eta = 50, period = 300, ends = true,
                  act = { aoe = true, dmg = { 100, 100, 100 }, worst = { 700, 700, 700 } } } } }
  check(pick(st) == "heal", "the worst case wipes on the attack (at 50, before any typical death): a heal stands guard")
end

-- 14. The continuation's heals run out (#415 calibration): a solo member
-- at 300 under a 250 hit every 300 ticks, against an enemy the horizon
-- does not see die, drinks to stay up while the bag lasts -- one Potion
-- puts the death off, an endless bag never lets it come
do
  local function st(n)
    return { actor = 1, hpRate = 1.2, focus = { 1 }, samples = 0,
      party = { member(300, 1000, 0, { lines = lines(10, 1, 0), heals = { { restore = 400, cost = 50, n = n } } }) },
      enemies = { { hp = 90000, sh = 4, eta = 50, period = 300, ends = true,
                    act = { aoe = false, dmg = { 250 } } } } }
  end
  local a = { kind = "attack", line = lines(10, 1, 0)[0], boost = 0 }
  check(H.raceSim(st(1), a).deaths == 1, "one Potion: the member falls inside the horizon")
  check(H.raceSim(st(nil), a).deaths == 0, "no limit: the member drinks forever")
end

-- 15. A tie on paper goes to the damage done now (#415, the WoR from Tzen:
-- CELES cast Cure where her Fight tied it, "ends @202" both, cost 225 vs
-- 312, and the fight took two more Fights): the banked pip lets the heal's
-- next turn kill as soon as the Fight's would, and the cost is inside its
-- margin -- the Fight's damage now decides
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(700, 1000, 0, { lines = lines(100, 1, 1), period = 202 }) },
    enemies = { { hp = 150, sh = 1, eta = 150, period = 400, ends = true,
                  act = { aoe = false, dmg = { 30 } } } } }
  local a, h = { kind = "attack", line = st.party[1].lines[0], boost = 0 },
               { kind = "heal", target = 1, restore = 100, cost = 20 }
  local ra, rh = H.raceEval(st, a), H.raceEval(st, h)
  check(ra.kill == rh.kill and math.abs(ra.cost - rh.cost) <= H.RACE_COST_MARGIN,
    "the case is a tie on kill and inside the cost margin")
  check(choose(st, { a, h }).kind == "attack", "the Fight's damage now breaks the tie")
end

-- 16. A line's per-hit figure is the median of its last landings, not the
-- last alone (the WoR's CELES: 83 a hit off one swing, 328 off the next)
check(H.median({ 83, 328, 300 }) == 300 and H.median({ 83, 328 }) == 83 and H.median({}) == nil,
  "the median of the landings")

-- 17. The worst-case play's continuation lifts against the worst hits
-- (#415, the WoR's CELES at 75/1043 under three slots, worst 68 + 107 + 133):
-- a Cure (357) now and the Cure again when the worst hits bring her low keeps
-- her standing; read against the typical hits, the continuation would wait
-- too long and the guard would call the Cure line a wipe
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(75, 1043, 0, { lines = lines(150, 1, 0), period = 202,
                                    heals = { { restore = 357, cost = 5, n = 20 } } }) },
    enemies = {
      { hp = 3000, sh = 3, eta = 129, period = 303, act = { dmg = { 10 }, worst = { 68 } } },
      { hp = 3000, sh = 3, eta = 48, period = 303, act = { dmg = { 15 }, worst = { 107 } } },
      { hp = 3000, sh = 3, eta = 176, period = 272, act = { dmg = { 20 }, worst = { 133 } } } } }
  local r = H.raceEval(st, { kind = "heal", target = 1, restore = 357, cost = 5 })
  check(not r.worstWipe, "the Cure line survives the worst case, its continuation curing again")
end

print(string.format("care_race_selftest: PASS -- %d checks: the Gate's lift, #414's review case, the 250 "
  .. "Potion that lifts nothing, spend before dying, the finisher, the raise that dies again and the one that "
  .. "stands, scarcity, the aftermath bill, the horizon, the score's order, the hit chance, the cost margin, calibration, the bag's count, the damage now, the median hit, the worst case's lift", n))

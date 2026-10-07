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
    party = { member(700, 1000, 0, { lines = lines(100, 1, 0), period = 202 }) },
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

-- 18. A boosted Fight's swings past its target's death go on to the next
-- body (#415 rewind lab, the WoR from Tzen: the rules' boosted Fight ended
-- the fight sooner than the race's banked one in all 8 distinct pairs,
-- e.g. 1177 frames against 4009): CELES, 328 a swing, two monsters at 582
-- and 850 -- 4 swings now kill the first and carry into the second
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 328, hits = 2 + 2 * b, chips = 0 } end
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(900, 1043, 0, { lines = L, bp = 1, period = 202 }) },
    enemies = { { hp = 582, sh = 2, eta = 42, period = 303, act = { dmg = { 98 } } },
                { hp = 850, sh = 2, eta = 62, period = 303, act = { dmg = { 91 } } } } }
  local r1 = H.raceEval(st, { kind = "attack", line = L[1], boost = 1 })
  check(r1.leftNow < 850 * 3, "the 1-BP Fight's last two swings land on the second monster")
  check(choose(st, { { kind = "attack", line = L[0], boost = 0 }, { kind = "attack", line = L[1], boost = 1 } }).boost == 1,
    "the boost now, not the bank")
end

-- 19. An enemy Runic takes a cure too, unless it cannot act (review of
-- 187f73c0: 8 of 8 cures cast with the Speck up landed no HP; RunicEffect
-- skips a dead, petrified, sleeping, stopped, frozen or hidden body)
check(H.runicAwake(0, 0, 0, 0), "a Speck standing takes the cast")
check(not H.runicAwake(0, H.ST2_SLEEP, 0, 0) and not H.runicAwake(0, 0, H.ST3_STOP, 0)
  and not H.runicAwake(H.ST1_PETRIFY, 0, 0, 0) and not H.runicAwake(0, 0, 0, H.ST4_FROZEN)
  and not H.runicAwake(0, 0, 0, 0x20) and not H.runicAwake(0x80, 0, 0, 0),
  "asleep, stopped, petrified, frozen, hidden or dead, it takes nothing")

-- 20. A last-stand removal (#415, the WoR's g00CC: slot 1 throws Sneeze at
-- a hit that leaves one monster standing): a boosted Fight whose swings
-- carry from the plain body into the second plain body leaves the Sneezer
-- alone, and CELES is sneezed away; the unboosted Fight does not
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 300, hits = 2 + 2 * b, chips = 0 } end
  local st = { actor = 1, hpRate = 1.2, focus = { 1, 3, 2 },
    party = { member(900, 1043, 0, { lines = L, bp = 2, period = 202 }) },
    enemies = { { hp = 500, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } },
                { hp = 900, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } }, stand = { n = 1 } },
                { hp = 1500, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } } } }
  local r2 = H.raceEval(st, { kind = "attack", line = L[2], boost = 2 })
  check(r2.wipe, "the 2-BP Fight can leave the Sneezer alone: the worst case reads CELES gone")
  check(choose(st, { { kind = "attack", line = L[0], boost = 0 }, { kind = "attack", line = L[2], boost = 2 } }).boost == 0,
    "the Fight that leaves two standing")
end

-- 21. The worst case reads a last stand against a harder hit (the WoR's
-- s5: the 2-BP Fight read two standing on paper, three fell, CELES was
-- sneezed away): a Fight that leaves the second body 1 HP short of death on
-- paper is guarded against; the party gone is the fight lost
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 100, hits = 2 + 2 * b, chips = 0 } end
  local st = { actor = 1, hpRate = 1.2, focus = { 2, 1, 3 },
    party = { member(900, 1043, 0, { lines = L, bp = 2, period = 202 }) },
    enemies = { { hp = 500, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } },
                { hp = 300, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } }, stand = { n = 1 } },
                { hp = 900, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } } } }
  -- 2-BP Fight: 6 swings of 100 on the Sneezer (300 HP behind a shield):
  -- three kill it, three carry to slot 1 (500 HP): 300 off, two standing;
  -- at 150 a swing two kill it and four take slot 1's 500: one standing
  local r = H.raceEval(st, { kind = "attack", line = L[2], boost = 2 })
  check(r.worstWipe and r.wipe, "at 1.5x the carried swings would leave one standing: the guard reads the party gone")
end

-- 22. The continuation holds back a boost that would set the last stand
-- off (the WoR's s5: the rules' Cure read "1.00 down" because the race's
-- continuation then swung 3 BP into the Sneezer's stand)
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 100, hits = 2 + 2 * b, chips = 0 } end
  local st = { actor = 1, hpRate = 1.2, focus = { 2, 1, 3 },
    party = { member(500, 1043, 0, { lines = L, bp = 3, period = 202, heals = {} }) },
    enemies = { { hp = 500, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } },
                { hp = 300, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } }, stand = { n = 1 } },
                { hp = 900, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } } } }
  local r = H.raceEval(st, { kind = "heal", target = 1, restore = 300, cost = 5 })
  check(r.deaths == 0 and not r.wipe, "after the heal the continuation's Fight leaves two standing")
end

-- 23. A last stand every attack sets off does not stall the race on heals
-- (the WoR's s5 at dce53c3e: the Sneezer and one body left, every Fight
-- read as the party gone, and CELES cast Cure three times running)
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 200, hits = 2 + 2 * b, chips = 0 } end
  local st = { actor = 1, hpRate = 1.2, focus = { 2, 1 },
    party = { member(500, 1043, 0, { lines = L, bp = 1, period = 202, heals = {} }) },
    enemies = { { hp = 200, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } } },
                { hp = 300, sh = 1, eta = 300, period = 303, act = { dmg = { 60 } }, stand = { n = 1 } } } }
  local c = choose(st, { { kind = "attack", line = L[0], boost = 0 }, { kind = "attack", line = L[1], boost = 1 },
    { kind = "heal", target = 1, restore = 300, cost = 5 } })
  check(c.kind == "attack", "with every attack setting it off, the race attacks, got " .. c.kind)
end

-- 24. One death in sixteen plays is the draws (#415, the WoR's s5: a Fight
-- that died in 1 of 16 plays lost three times to a Cure that only stalled)
do
  local st = { enemies = { { period = 300 } } }
  local function r(t) t.left = t.left or 1000; t.left0 = 2000; t.cost = t.cost or 0; return t end
  check(H.raceBetter(r({ deaths = 0.0625, kill = 600 }), r({ deaths = 0, left = 1500 }), st),
    "a kill with a death in one play of sixteen beats a stall")
  check(not H.raceBetter(r({ deaths = 0.25, kill = 600 }), r({ deaths = 0, left = 1500 }), st),
    "four plays in sixteen is the line")
end

-- 25. A monster whose gauge is full acts before a member whose gauge is
-- full (#415, the Air Force at a726743e: the race healed TERRA at 129 and
-- read EDGAR at 155, gauge full, healing himself before slot 0, gauge
-- full too, hit him for 224; he fell)
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 }, samples = 0,
    party = { member(900, 1000, 0, { lines = lines(100, 1, 0) }),
              member(155, 1130, 0, { heals = { { restore = 900, cost = 50, n = 5 } } }) },
    enemies = { { hp = 9000, sh = 4, eta = 0, period = 250, ends = true, act = { dmg = { 224, 224 } } } } }
  local r = H.raceSim(st, { kind = "attack", line = st.party[1].lines[0], boost = 0 })
  check(r.deaths >= 1, "slot 0's full gauge strikes EDGAR before his own turn")
end

-- 26. battle_kefka on wt/v026-supply a4e9f966 (build/attempts/wt/v026-supply/
-- run-a4e9f966-px13/suite_battle_kefka.log, f+8400): CELES alone at 244/310
-- with 5 BP, TERRA and EDGAR down, Kefka at 1124 behind 2 shields.  The rules
-- held the raise (#312) and CELES healed herself turn after turn until she
-- died holding 5 BP.  The race raises EDGAR: his Tools (235 a hit) end the
-- fight sooner, and a second body takes a share of Kefka's hits
do
  local function fl(per, h0) local t = {} for b = 0, 3 do t[b] = { per = per, hits = h0 + b, chips = 1 } end return t end
  local function kl(per) local t = {} for b = 0, 3 do t[b] = { per = per * (1 + b), hits = 1, chips = 1 } end return t end
  local st = { actor = 3, hpRate = 1.2, focus = { 1 },
    party = { member(0, 306, 0, { lines = fl(40, 2), period = 206 }),
              member(0, 315, 0, { lines = kl(235), period = 202 }),
              member(244, 310, 0, { lines = fl(45, 2), period = 250, bp = 5,
                                    heals = { { restore = 250, cost = 300, n = 20 } } }) },
    enemies = { { hp = 1124, sh = 2, eta = 60, period = 250, ends = true,
                  act = { dmg = { 231, 160, 120 }, worst = { 306, 314, 243 } } } } }
  local L = st.party[3].lines
  local c = choose(st, {
    { kind = "attack", line = L[0], boost = 0 }, { kind = "attack", line = L[3], boost = 3 },
    { kind = "heal", target = 3, restore = 250, cost = 300 },
    { kind = "raise", target = 2, hp = 39, cost = 500 },
    { kind = "raise", target = 1, hp = 38, cost = 500 } })
  check(c.kind == "raise" and c.target == 2, "CELES raises EDGAR, not another Potion on herself, got " .. c.kind)
end

-- 27. A member left near fatal counts as half a member down (the full
-- ninja at 5b46dbd6: falls_done shipped CYAN at 5/358 after the race's
-- Fights; audit_party_hp red): CYAN at 40/358 and the last body two Fights
-- from dead -- the Potion first, though the kill comes a turn later
do
  local st = { actor = 1, hpRate = 1.2, focus = { 1 },
    party = { member(900, 1000, 0, { lines = lines(100, 1, 0), period = 200 }), member(40, 358, 500) },
    enemies = { { hp = 300, sh = 1, eta = 900, period = 150, ends = true, act = { dmg = { 10, 10 } } } } }
  local c = choose(st, { { kind = "attack", line = st.party[1].lines[0], boost = 0 },
    { kind = "heal", target = 2, restore = 250, cost = 50 } })
  check(c.kind == "heal", "CYAN at 40/358 is lifted before the kill, got " .. c.kind)
end

-- 28. A carried swing that takes half a body, against a last stand, is read
-- as taking all of it (the WoR's s5 at f7e822c8: a 1-BP Fight read the
-- Sneezer dead on its fourth swing with two bodies standing; the swing
-- carried, the plain body fell, CELES was sneezed away)
do
  local L = {}
  for b = 0, 3 do L[b] = { per = 138, hits = 2 + 2 * b, chips = 1 + b } end
  local st = { actor = 1, hpRate = 1.2, focus = { 2, 3, 1 },
    party = { member(586, 1125, 0, { lines = L, bp = 2, period = 202 }) },
    enemies = { { hp = 850, sh = 2, eta = 20, period = 303, act = { dmg = { 133 } } },
                { hp = 922, sh = 2, eta = 240, period = 303, act = { dmg = { 71 } }, stand = { n = 1 } },
                { hp = 458, sh = 2, eta = 222, period = 272, act = { dmg = { 61 } } } } }
  local c = choose(st, { { kind = "attack", line = L[0], boost = 0 }, { kind = "attack", line = L[1], boost = 1 } })
  check(c.boost == 0, "the 1-BP Fight whose last swing carries is held back, got " .. c.boost)
end

-- The continuation also respects a caller that disabled boost: its next
-- turn may not use banked BP to invent a faster kill.
do
  local st = { actor = 1, boost = false, samples = 0, contCare = false,
    party = { member(1000, 1000, 0, { bp = 3, lines = lines(100, 1, 0), period = 100 }) },
    enemies = { { hp = 1000, sh = 0, eta = 1000, period = 1000, act = { dmg = { 1 } } } } }
  local c = { kind = "attack", line = st.party[1].lines[0], boost = 0 }
  check(H.raceSim(st, c).kill == 200, "boost disabled: three unboosted attacks")
  st.boost = true
  check(H.raceSim(st, c).kill == 100, "boost enabled: the continuation spends its bank")
end

-- 29. Candidate vetoes are driver rules, tested with synthetic memory reads
-- only (no emulator state and no gameplay claim). A zombie and a member
-- who left receive neither healing nor a raise; the same seated patient
-- offers both normally.
do
  local D = H.newFightDriver("candidate veto unit").driver
  local readByte, leftMask, itemPower, itemPrice = H.readByte, H.leftMask, H.itemPower, H.itemPrice
  local zombie, left = false, false
  H.readByte = function(addr) return zombie and 2 or 0 end
  H.leftMask = function() return left and 2 or 0 end
  H.itemPower = function() return 2 end
  H.itemPrice = function() return 500 end
  D.battInvIdx = function() return 0 end
  local st = { actor = 0, careItems = true, careCasts = true, party = {
    [0] = { hp = 1000, maxhp = 1000, bp = 0, lines = {}, heals = {} },
    [1] = { hp = 100, maxhp = 1000, heals = { { restore = 250, cost = 300, id = 0xE9 } } } } }
  check(#D:raceCandidates(0, st) == 1, "a seated hurt member offers a heal")
  zombie = true
  check(#D:raceCandidates(0, st) == 0, "a zombie offers no heal")
  st.party[1].hp = 0
  check(#D:raceCandidates(0, st) == 0, "a zombie offers no Fenix Down")
  zombie, left = false, true
  check(#D:raceCandidates(0, st) == 0, "a member who left offers no Fenix Down")
  st.party[1].hp = 100
  check(#D:raceCandidates(0, st) == 0, "a member who left offers no heal")
  st.party[1].hp, left = 0, false
  check(#D:raceCandidates(0, st) == 1, "a seated fallen member offers a Fenix Down")
  st.careItems = false
  check(#D:raceCandidates(0, st) == 0, "the actor's closed item line offers no raise")
  st.party[1].hp = 100
  check(#D:raceCandidates(0, st) == 0, "the actor's closed item line offers no bag heal")
  st.careItems = true
  st.party[1].noCare = true
  check(#D:raceCandidates(0, st) == 0, "a patient whose Doom beats the next turn offers no heal")
  st.party[1].noCare = false
  H.readByte = function() return H.ST1_PETRIFY end
  check(#D:raceCandidates(0, st) == 0, "a statue offers no heal")
  H.readByte = function() return 0 end
  st.party[0].bp, st.party[0].lines = 3, lines(100, 1, 1)
  check(#D:raceCandidates(0, st) == 2, "boost disabled offers only the unboosted attack and heal")
  D.opts.boost = true
  check(#D:raceCandidates(0, st) == 5, "boost enabled offers all four attacks and heal")
  st.party[0].heals = { { cast = true, spell = 0x2D, restore = 100, cost = 0 } }
  st.careCasts, st.careItems = false, false
  check(#D:raceCandidates(0, st) == 4, "the actor's closed cure line offers no cast")
  st.careCasts = true
  check(#D:raceCandidates(0, st) == 5, "the actor's open cure line offers a cast")
  H.readByte, H.leftMask, H.itemPower, H.itemPrice = readByte, leftMask, itemPower, itemPrice
end

-- 30. The Gate regression's party-status class: simulated continuation
-- must not use a turn the player cannot command. Synthetic reads only.
do
  local D = H.newFightDriver("party status guard unit").driver
  D.pressTarget = function() return nil end
  local readByte, readWord, leftMask, shopRates = H.readByte, H.readWord, H.leftMask, H.shopRates
  local bytes, left = {}, 0
  H.readByte = function(addr) return bytes[addr] or 0 end
  H.readWord = function() return 0 end
  H.shopRates = function() return { hp = 1.2 } end
  H.leftMask = function() return left end
  local R = { hpNow = { [0] = 0, [1] = 1000, [2] = 0, [3] = 0 } }
  for _, status in ipairs({
    { "Muddle", 0x3EE5, 0x20 }, { "Sleep", 0x3EE5, H.ST2_SLEEP },
    { "Stop", 0x3EF8, H.ST3_STOP }, { "Frozen", 0x3EF9, H.ST4_FROZEN },
    { "Berserk", 0x3EE5, H.ST2_BERSERK }, { "Petrify", 0x3EE4, H.ST1_PETRIFY },
    { "Zombie", 0x3EE4, H.ST1_ZOMBIE } }) do
    bytes = { [status[2] + 2] = status[3] }
    local st, why = D:raceState(0, R)
    check(st == nil and why:find("cannot take a planned turn", 1, true),
      status[1] .. " contributes no imagined continuation")
  end
  bytes, left = {}, 2
  local st, why = D:raceState(0, R)
  check(st == nil and why:find("cannot take a planned turn", 1, true), "a departed member contributes no continuation")
  left = 0
  st, why = D:raceState(0, R)
  check(st == nil and why == "no monster stands", "a healthy party passes the status guard")
  H.readByte, H.readWord, H.leftMask, H.shopRates = readByte, readWord, leftMask, shopRates
end

-- 31. Executable records retain the affordable boost, target and MP price.
-- The requested three pips must not turn a zero-pip tool into fourfold damage.
do
  local plan = { kind = "skill", cmd = 9, skill = 0xAA, boostLeft = 0, mp = 4,
                 hits = 1, chips = 1, aim = 2 }
  local line = H.raceLine(plan, 100, { cost = 120, aoe = true })
  local c = H.raceAttack(line, 3)
  check(c.boost == 0 and line.per == 100, "score the executable zero-boost tool")
  check(c.mp == 4 and c.cost == 120 and c.target == 2, "one action retains price and target")
  check(line.aoe == true, "the area tool remains an area action")
end

-- 32. One Potion belongs to the shared bag, not separately to each actor.
do
  local function state()
    local heal = { id = 0xE9, n = 1, restore = 500, cost = 300 }
    return { actor = 1, samples = 0, contCare = true, horizon = 3, bag = { [0xE9] = 1 },
      party = { member(200, 1000, 0, { period = 100, heals = { heal }, lines = lines(0, 1, 0) }),
                member(200, 1000, 10, { period = 100, heals = { { id = 0xE9, n = 1, restore = 500, cost = 300 } },
                  lines = lines(0, 1, 0) }) },
      enemies = { { hp = 10000, sh = 0, eta = 20, period = 100,
                    act = { aoe = true, dmg = { 300, 300 } } } } }
  end
  local st = state()
  local first = { kind = "attack", line = st.party[1].lines[0], boost = 0 }
  local r = H.raceSim(st, first)
  check(r.spent == 300 and r.resources.bag[0xE9] == 0, "two actors share exactly one Potion")
  check(st.bag[0xE9] == 1, "each candidate receives an independent copied bag")
  st = state()
  r = H.raceSim(st, { kind = "heal", target = 1, id = 0xE9, restore = 500, cost = 300 })
  check(r.spent == 300 and r.resources.bag[0xE9] == 0, "the first action also exhausts the Potion")
end

-- 33. First action and continuation share one member's MP, across verbs.
do
  local function state()
    local l = { [0] = { per = 25, hits = 1, chips = 0, mp = 4, cost = 120 } }
    local p = member(100, 1000, 0, { period = 100, lines = l,
      heals = { { spell = 0x2D, mp = 4, n = 1, restore = 500, cost = 120 } } })
    p.mp = 4
    return { actor = 1, samples = 0, horizon = 3, party = { p },
      enemies = { { hp = 10000, sh = 0, eta = 150, period = 100, act = { dmg = { 300 } } } } }
  end
  local st = state()
  local r = H.raceSim(st, H.raceAttack(st.party[1].lines[0], 0))
  check(r.resources.party[1].mp == 0 and r.spent == 120, "the kit consumes the MP a cure would need")
  check(r.wipe, "imaginary continuation Cure cannot save the depleted member")
  st = state()
  r = H.raceSim(st, { kind = "heal", target = 1, restore = 500, spell = 0x2D, mp = 4, cost = 120 })
  check(r.resources.party[1].mp == 0 and r.spent == 120, "Cure consumes the MP future kit turns need")
  local unavailable = { kind = "attack", line = st.party[1].lines[0], mp = 5, cost = 150 }
  r = H.raceEval(st, unavailable)
  check(r.invalid and r.resources.party[1].mp == 4, "unpayable first command is invalid without consuming MP")
end

-- 34. Controller latency advances enemies before the candidate resolves.
-- Deep-item versus fast cure is a timing property, independent of damage.
do
  local st = { actor = 1, samples = 0, contCare = false, horizon = 1,
    party = { member(100, 1000, 0) },
    enemies = { { hp = 1000, sh = 0, eta = 20, period = 100, act = { dmg = { 200 } } } } }
  local r = H.raceSim(st, { kind = "heal", target = 1, restore = 900, delay = 30 })
  check(r.wipe and not r.firstExecuted, "enemy kills the actor during the deep item walk")
  r = H.raceSim(st, { kind = "heal", target = 1, restore = 900, delay = 10 })
  check(not r.wipe and r.firstExecuted, "the faster cure resolves before the hit")
  st.enemies[1].eta = 0
  r = H.raceSim(st, { kind = "attack", line = { per = 1000 }, boost = 0, delay = 0 })
  check(r.wipe and not r.firstExecuted, "full enemy gauge acts before the first command")
end

-- 35. Area effects and fixed targets are known before comparison.
do
  local st = { actor = 1, samples = 0, contCare = false, horizon = 1,
    party = { member(1000, 1000, 0, { period = 1000, lines = lines(0, 1, 0) }) },
    enemies = { { hp = 100, sh = 1, eta = 100, period = 1000, act = { dmg = { 0 } } },
                { hp = 100, sh = 1, eta = 100, period = 1000, act = { dmg = { 0 } } } } }
  local line = H.raceLine({ kind = "skill", boostLeft = 0, hits = 1, aim = 2 }, 100,
    { aoe = true, byTarget = { [1] = { hit = 0 }, [2] = { hit = 1, chips = 1 } } })
  local r = H.raceSim(st, H.raceAttack(line, 0))
  check(r.leftNow == 200, "area effects use each body's hit chance and shields")
  line = H.raceLine({ kind = "fight", boostLeft = 0, hits = 1, aim = 2 }, 50,
    { byTarget = { [1] = { hit = 0 }, [2] = { hit = 1, chips = 1 } } })
  r = H.raceSim(st, H.raceAttack(line, 0))
  check(r.leftNow == 200, "score the frozen target rather than the lowest HP/default target")
end

-- 36. Pending care is a commitment, not a second new candidate.
do
  local D = H.newFightDriver("pending care unit").driver
  local readByte, leftMask = H.readByte, H.leftMask
  H.readByte, H.leftMask = function() return 0 end, function() return 0 end
  local st = { actor = 0, careItems = true, careCasts = false, pendingHeal = { [1] = { by = 2 } },
    party = { [0] = { hp = 1000, maxhp = 1000, bp = 0, lines = {}, heals = {} },
              [1] = { hp = 100, maxhp = 1000, heals = { { id = 0xE9, restore = 250, cost = 300 } } } } }
  check(#D:raceCandidates(0, st) == 0, "no duplicate heal offered for a pending heal")
  st.pendingHeal = {}
  check(#D:raceCandidates(0, st) == 1, "the heal is offered without a pending commitment")
  H.readByte, H.leftMask = readByte, leftMask
end

-- 37. Enumerate executable alternatives before selecting by shield chips.
-- An affordable downgrade offered at several requested boosts is one action.
do
  local D = H.newFightDriver("canonical enumeration unit", { boost = true }).driver
  local readByte, leftMask = H.readByte, H.leftMask
  H.readByte, H.leftMask = function() return 0 end, function() return 0 end
  local tool = H.raceLine({ kind = "skill", cmd = 9, skill = 0xAA, boostLeft = 0, mp = 4 }, 100)
  local fight = H.raceLine({ kind = "fight", boostLeft = 1 }, 100)
  local st = { actor = 0, party = { [0] = { hp = 1000, maxhp = 1000, bp = 3, lines = {},
    actions = { tool, tool, tool, tool, fight }, heals = {} } } }
  local c = D:raceCandidates(0, st)
  check(#c == 2 and c[1].boost == 0 and c[2].boost == 1, "retain both verbs, deduplicate requested boost downgrades")
  st.party[0].bp = 0
  c = D:raceCandidates(0, st)
  check(#c == 1 and c[1].boost == 0, "a command cannot spend BP absent from the bank")
  H.readByte, H.leftMask = readByte, leftMask
end

-- 38. Depleted kit MP falls back to a real free Fight, not repeated tools.
do
  local l = { [0] = { per = 25, hits = 1, mp = 4, cost = 120 } }
  local p = member(1000, 1000, 0, { period = 100, lines = l })
  p.mp, p.fallback = 4, { per = 25, hits = 1, boost = 0, mp = 0 }
  local st = { actor = 1, samples = 0, contCare = false, party = { p },
    enemies = { { hp = 300, sh = 0, eta = 1000, period = 1000, act = { dmg = { 0 } } } } }
  local r = H.raceSim(st, H.raceAttack(l[0], 0))
  check(r.kill == 200 and r.spent == 120 and r.resources.party[1].mp == 0,
    "one paid tool followed by two free Fights")
end

-- 39. A party revived by the end still paid for its falls during the fight.
do
  local a = { wipe = false, deaths = 0, falls = 2, kill = 100, cost = 0 }
  local b = { wipe = false, deaths = 0, falls = 0, kill = 200, cost = 0 }
  check(H.raceBetter(b, a, { samples = 0, enemies = {} }), "fewer repeated falls beats a quicker ending with everyone raised")
end

-- 40. Measure the complete accepted action lifecycle, not button attempts.
do
  local D = H.newFightDriver("latency unit", {raceTimingGuesses=false}).driver
  local trace = H.newRecoveryTrace("latency unit", function() end,
    function(e) D:raceObserve(e) end)
  local plan = { kind = "item", item = 0xE9, boostLeft = 0 }
  check(D:raceDelay(0, plan) == nil, "unknown command latency is absent, never zero")
  trace.plan(0, plan, 100)
  trace.confirm(0, 110, 0, 0)
  trace.submit(0, 120, 1, 0xE9, 1)
  trace.start(0, 140, 1, 0xE9, 1, {100,100,100,100}, 20, 0)
  check(D:raceDelay(0, plan) == nil, "accepted but unresolved command is not a latency sample")
  trace.resolve(0, 180, {200,100,100,100}, 20, 0)
  local timing = D.raceTiming["0:item:233:0"]
  check(timing.navigation == 20 and timing.queue == 20 and timing.execution == 40
    and timing.finished == 80, "retain navigation, queue and execution separately")
  check(D:raceDelay(0, plan) == nil, "execution end is not an observed first-effect delay")
  check(D:raceDelay(1, plan) == nil and D:raceDelay(0, {kind="item", item=0xEA}) == nil,
    "latency samples do not cross actor or item identity")
  D:raceObserve({event="resolve", actor=0, kind="item", requested=0xE9, boost=0, elapsed_frames=100})
  D:raceObserve({event="resolve", actor=0, kind="item", requested=0xE9, boost=0, elapsed_frames=90})
  check(H.median(D.raceLatency["0:item:233:0"]) == 90, "retain the median resolved command latency")
end

-- 41. A pending command at the horizon has not performed its imagined heal.
do
  local st = { actor=1, samples=0, contCare=false, horizon=1,
    party={member(500,1000,0)},
    enemies={{hp=10000,sh=0,eta=10,period=10,act={dmg={1}}}} }
  local r=H.raceSim(st,{kind="heal",target=1,restore=500,delay=100})
  check(r.pending and not r.firstExecuted and r.resources.party[1].hp==499,
    "horizon does not credit a command that has not resolved")
end

-- 42. The final shield-breaking hit receives the break it causes.
do
  local st={actor=1, samples=0, contCare=false, horizon=1,
    party={member(1000,1000,0,{period=1000})},
    enemies={{hp=500,sh=1,eta=100,period=1000,act={dmg={0}}}}}
  local r=H.raceSim(st,{kind="attack",line={per=50,hits=1,chips=1},boost=0})
  check(r.leftNow==300,"the last shield chips before this hit's damage is priced")
end

-- 43. An unknown continuation cannot obtain an instantaneous saving Cure.
do
  local p=member(500,1000,0,{period=100, lines=lines(1,1,0),
    heals={{restore=900,cost=10,mp=1,latencyKnown=false}}})
  p.mp=10
  local st={actor=1,samples=0,party={p},
    enemies={{hp=10000,sh=0,eta=50,period=100,act={dmg={300}}}}}
  local r=H.raceSim(st,{kind="attack",line=p.lines[0],boost=0,delay=0,latencyKnown=true})
  check(r.invalid and r.resources.party[1].mp==10,
    "unknown later Cure invalidates the comparison without spending or healing")
end

-- 44. Only the matching running command owns an HP effect; animation end
-- is kept separately from target effect times, and censored volleys expire.
do
  local D = H.newFightDriver("effect timing unit", {raceTimingGuesses=false}).driver
  local events,clock = {},0xFFF0
  local T = H.newRecoveryTrace("effect timing unit", function(e) events[#events+1]=e end,
    function(e) D:raceObserve(e) end,function() return clock end)
  local p={kind="skill",skill=0xAB,boostLeft=1}
  T.plan(0,p,100); T.submit(0,120,9,0xAB,0x300)
  T.start(0,140,9,0xAB,0x300,{100,100,100,100},20,1)
  T.hpEffect(1,145,4,100,50,9,0xAB)
  T.hpEffect(0,146,4,100,50,0x22,0xAB)
  T.hpEffect(0,147,4,100,100,9,0xAB)
  check(#events==3,"unrelated actor, engine command and zero HP change supply no effect")
  clock=4; T.hpEffect(0,150,4,100,50,9,0xAB)
  clock=14; T.hpEffect(0,160,5,300,200,9,0xAB)
  check(events[4].effect_target==4 and events[5].effect_target==5
    and events[4].hp_change==-50 and events[5].effect_index==2,
    "retain each attributed target, signed HP change and pass timing")
  check(D:raceDelay(0,p)==nil,"an unfinished volley is not a completed timing sample")
  T.resolve(0,220,{100,100,100,100},16,0)
  local delay,bounds=D:raceDelay(0,p)
  check(delay==30 and bounds.lo==5 and bounds.hi==45,
    "first/last HP effects bound aggregate delay without using animation completion")
  check(D.raceTiming["0:skill:171:1"].finished==120,
    "completion latency is preserved as a separate fact")
  T.plan(0,p,300);T.submit(0,320,9,0xAB,0x300)
  T.start(0,340,9,0xAB,0x300,{100,100,100,100},20,1)
  T.hpEffect(0,350,4,100,50,9,0xAB);T.close(360,"battle_ended")
  local _,after=D:raceDelay(0,p)
  check(after.n==1 and next(D.raceEffectOpen)==nil,
    "an incomplete final command cannot masquerade as a short completed volley")
end

-- 45. A miss cannot strip the last shield; random samples land whole hits.
do
  local st={actor=1,samples=0,contCare=false,horizon=1,
    party={member(1000,1000,0,{period=1000})},
    enemies={{hp=500,sh=1,eta=100,period=1000,act={dmg={0}}}}}
  local c={kind="attack",line={per=50,hits=1,chips=1,hit=0},boost=0}
  check(H.raceSim(st,c).leftNow==1000,"zero hit chance preserves both HP and shield")
  c.line.hit=0.5
  local miss=H.raceSim(st,c,function() return 0.9 end)
  local land=H.raceSim(st,c,function() return 0.1 end)
  check(miss.leftNow==1000 and land.leftNow==300,
    "a sampled hit chips before damage; a sampled miss does neither")
end

-- 46. Guesses are explicit bounded estimates; paired scenarios must not
-- reverse preference or buy a new fall, and tie-breakers cannot override.
do
  local D=H.newFightDriver("coarse timing unit").driver
  local delay,bounds=D:raceDelay(0,{kind="fight"})
  check(delay>0 and bounds.lo<delay and bounds.hi>delay and bounds.n==0,
    "unobserved supported Fight uses a declared pulse/queue estimate, never zero")
  local p=member(50,1000,0,{period=1000})
  local st={actor=1,samples=0,contCare=false,horizon=2,tickMargin=5,
    party={p},enemies={{hp=600,sh=0,eta=100,period=1000,act={dmg={50}}}}}
  local rules={kind="attack",line={per=150,hits=1},boost=0,delay=50,delayBounds={lo=50,hi=50}}
  local alt={kind="attack",line={per=200,hits=1},boost=0,delay=40,delayBounds={lo=20,hi=150}}
  local safe,why=H.raceRobustBetter(st,alt,rules)
  check(not safe and why=="timing scenario adds wipe/down/fall risk",
    "late effect's lethal intervening enemy turn vetoes nominal faster kill")
  alt.delayBounds.hi=40
  check(H.raceRobustBetter(st,alt,rules),"material earlier kill with stable risk may override")
  alt.delay=49;alt.delayBounds={lo=49,hi=49}
  local ok,reason=H.raceRobustBetter(st,alt,rules)
  check(not ok and reason=="inside uncertainty margin","one-tick tie-break is not material evidence")
  p.heals={{restore=250,delay=20,delayBounds={lo=5,hi=40}}}
  p.lines={[0]={per=100,delay=10,delayBounds={lo=2,hi=30}}}
  local early=H.raceTimingScenario(st,rules,"lo")
  local late=H.raceTimingScenario(st,rules,"hi")
  check(early.party[1].heals[1].delay==5 and late.party[1].lines[0].delay==30
    and p.heals[1].delay==20 and p.lines[0].delay==10,
    "same timing convention reaches continuations without mutating the original state")
  local a={wipe=false,pWipe=0.25,deaths=0,falls=0,kill=10,cost=0}
  local b={wipe=false,pWipe=0,deaths=0,falls=0,kill=20,cost=0}
  check(H.raceBetter(b,a,{samples=16,enemies={}}),"sampled wipe disadvantage outranks faster mean kill")
end

-- 47. Overrides use the ranking's actual enemy-period margin; required
-- sampled plays cannot hide unsupported continuations behind a mean hit.
do
  local st={actor=1,samples=0,contCare=false,horizon=2,
    party={member(1000,1000,0,{period=1000})},
    enemies={{hp=400,sh=0,eta=1000,period=600,act={dmg={0}}}}}
  local a={kind="attack",line={per=100,hits=1},boost=0,delay=100}
  local b={kind="attack",line={per=100,hits=1},boost=0,delay=180}
  local safe,why=H.raceRobustBetter(st,a,b)
  check(not safe and why=="inside uncertainty margin",
    "80 ticks does not beat the shared 600-tick enemy-period margin")
  st.samples=16
  st.party[1].lines={[0]={per=100,hits=1,latencyKnown=false}}
  a.line={per=300,hits=1,hit=0.5};a.delay=0
  check(not H.raceSim(st,a).invalid,"deterministic expected hit ends before the unsupported continuation")
  check(H.raceEval(st,a).invalid,
    "sampled misses requiring an unsupported continuation invalidate the whole estimate")
end

-- 48. Engine break contract: suppressed turns, finite shield recovery,
-- and naturally shieldless bodies. These are arithmetic, not played wins.
do
  local st={actor=1,samples=0,contCare=false,horizon=2,
    party={member(1000,1000,0,{period=2000,lines={}})},
    enemies={{hp=1000,sh=1,shMax=1,breakDuration=10,eta=5,period=20,act={dmg={100}}}}}
  local a={kind="attack",line={per=10,hits=1,chips=1},boost=0}
  local r=H.raceSim(st,a)
  check(r.resources.party[1].hp==900 and r.breakSkips==1,
    "new break suppresses turn5; recovered turn25 deals100")
  st.enemies[1].sh=0;st.enemies[1].shMax=3;st.enemies[1].brokenLeft=10
  st.enemies[1].eta=20;st.enemies[1].period=100;st.horizon=1
  a.line.chips=0;a.delay=15
  r=H.raceSim(st,a)
  check(r.leftNow==3960,"break expiry restores3 shields before hit15:990HP*4")
  st.enemies[1].shMax=0;st.enemies[1].brokenLeft=0;a.delay=0
  r=H.raceSim(st,a)
  check(r.leftNow==980,"shieldless normal body takes20, not40 broken damage")
  check(H.raceDamageBase(80,0,false)==40 and H.raceDamageBase(80,3,true)==20
    and H.raceDamageBase(80,3,false)==80,"race-only damage normalization respects all three states")
  check(H.raceBreakClock(1,192,64,4,4)==1,
    "next entity visit overflowing consumes final broken count in one ATB update")
  check(H.raceBreakClock(1,0,64,4,5)==64,
    "just visited entity needs four visits for normal-speed final count")
  check(H.raceBreakClock(16,0,64,4,5)==1024,
    "full normal-speed break occupies sixteen status overflows")
  check(H.raceBreakClock(0,192,64,4,4)==0,"unbroken counter has no remaining window")
  for _,speed in ipairs({32,64,84}) do
    for _,acc in ipairs({0,63,192,255}) do
      for _,phase in ipairs({0,4,5,15}) do
        for _,count in ipairs({1,16}) do
          local ticks,left,a,nextEntity=0,count,acc,phase
          while left>0 do
            ticks=ticks+1
            if nextEntity==4 then
              a=a+speed
              if a>=256 then a=a-256;left=left-1 end
            end
            nextEntity=(nextEntity+1)%16
          end
          check(H.raceBreakClock(count,acc,speed,4,phase)==ticks,
            "break clock agrees with per-update DecCounters recurrence")
        end
      end
    end
  end
  local center,bounds=H.raceBreakDuration(64)
  check(bounds.lo==961 and bounds.hi==1024 and center>bounds.lo and center<bounds.hi,
    "new break bounds cover speed-accumulator and entity-phase uncertainty")
  local fast=H.raceBreakDuration(84);local slow=H.raceBreakDuration(32)
  check(fast<center and slow>center,"haste shortens break; slow lengthens it")
  st.enemies[1].breakDurationBounds=bounds
  local early=H.raceTimingScenario(st,a,"lo");local late=H.raceTimingScenario(st,a,"hi")
  check(early.enemies[1].breakDuration==961 and late.enemies[1].breakDuration==1024
    and st.enemies[1].breakDuration==10,"break timing sensitivity copies both arms without mutating input")
end

-- 49. A living broken body's attack counter is suppressed, while
-- if_self_dead retaliation remains admitted by the engine's died branch.
do
  local st={actor=1,samples=0,contCare=false,horizon=1,
    party={member(1000,1000,0,{period=2000})},
    enemies={{hp=1000,sh=1,shMax=1,breakDuration=100,eta=50,period=100,
      stand={n=1,guarded=true},act={dmg={100}}}}}
  local a={kind="attack",line={per=10,hits=1,chips=1},boost=0}
  check(not H.raceSim(st,a).standNow,"final shield chip suppresses living attack retaliation")
  a.line.chips=0
  check(H.raceSim(st,a).standNow,"unbroken living last-stand retaliation still fires")
  st.enemies[1].stand={n=1,deathOnly=true};a.line.chips=1;a.line.per=300
  check(H.raceSim(st,a).standNow,"broken death counter remains admitted after lethal hit")
end

-- 50. Another ready member can plan before the delayed first command.
-- Its speculative last-stand check must have the current planning time.
do
  local L={[0]={per=10,hits=1,chips=1},[1]={per=20,hits=1,chips=1}}
  local st={actor=1,samples=0,contCare=false,horizon=2,
    party={member(1000,1000,0,{period=1000}),
      member(1000,1000,0,{period=1000,bp=1,lines=L})},
    enemies={{hp=1000,sh=1,shMax=1,breakDuration=100,eta=50,period=200,
      stand={n=1,guarded=true},act={dmg={100,100}}}}}
  local a={kind="attack",line={per=10,hits=1,chips=0},delay=100,boost=0}
  local r=H.raceSim(st,a)
  check(not r.invalid and r.resources.enemies[1].breakUntil==nil,
    "early continuation plans safely and its break expires on the event timeline")
end

-- Accepted execution tokens own internal hand/tool/spell effects, while
-- unrelated dispatcher entries cannot borrow a waiting or stale plan.
do
  local function prepared(cmd,atk,kind)
    local ev={}
    local T=H.newRecoveryTrace("token unit",function(e) ev[#ev+1]=e end)
    T.plan(0,{kind=kind or "fight",skill=atk},0)
    T.submit(0,10,cmd,atk,0x100)
    local scope=T.start(0,20,cmd,atk,0x100,{100,100,100,100},20,0,
      {queued_command=cmd,queued_attack=atk,counter=false})
    return T,ev,scope
  end
  for _,v in ipairs({{0,255,0,127,"fight"},{9,170,9,7,"skill"},
    {10,93,10,0,"skill"},{0,255,2,14,"fight"}}) do
    local T,ev,scope=prepared(v[1],v[2],v[5])
    T.hpEffect(0,30,4,100,50,v[3],v[4],{context=scope,
      queued_command=v[1],queued_attack=v[2]})
    local e=ev[#ev]
    check(e.event=="hp_effect" and e.command==v[1] and e.attack==v[2]
      and e.raw_effect_command==v[3] and e.raw_effect_attack==v[4]
      and e.context_id==scope.id,"accepted Fight/Tools/Pummel/weapon-spell identity remains separate from its raw effect")
    T.resolve(0,40,{100,100,100,100},20,0)
    check(ev[#ev].event=="resolve" and ev[#ev].context_id==scope.id,
      "a matching dispatcher token resolves its accepted command")
  end
  local T,ev,scope=prepared(0,255)
  local before=#ev
  T.hpEffect(1,30,4,100,50,0,127,{context=scope,queued_command=0,queued_attack=255})
  check(#ev==before,"wrong actor cannot own a matching-looking HP effect")
  scope.actor=1
  T.hpEffect(0,23,4,100,50,0,127)
  check(#ev==before,"changed context actor cannot own running actor effect")
  scope.actor=0
  T.hpEffect(0,30,4,100,50,0,127,{context=scope,queued_command=9,queued_attack=255})
  check(#ev==before,"stable queued command mismatch rejects effect")
  T.hpEffect(0,30,4,100,50,0,127,{context=scope,queued_command=0,queued_attack=170})
  check(#ev==before,"stable queued attack mismatch rejects effect")
  local saved=scope.trace_id;scope.trace_id=saved+1
  T.hpEffect(0,30,4,100,50,0,127,{context=scope})
  check(#ev==before,"stale trace ID cannot own effect")
  scope.trace_id=saved
  local id=scope.id;scope.id=id+1
  T.hpEffect(0,30,4,100,50,0,127,{context=scope})
  check(#ev==before,"stale execution ID cannot own effect")
  scope.id=id
  T.hpEffect(0,30,4,100,50,0x22,0,{context=scope})
  check(#ev==before,"engine tick cannot be an accepted command's HP effect")
  T.start(nil,31,0,119,0x1,{100,100,100,100},20,0)
  T.hpEffect(0,32,4,100,50,0,127,{context=scope})
  check(#ev==before,"enemy dispatcher invalidates a bracket's earlier context")
  T.resolve(0,33,{100,100,100,100},20,0)
  check(#ev==before,"changed context cannot resolve a stale running command")
  T.close(34,"state_reload")
  local after=#ev
  T.hpEffect(0,35,4,100,50,0,127,{context=scope})
  check(#ev==after and T.context==nil,"reload discards the running trace and execution scope")
  for _,entry in ipairs({{0,255,true},{0x22,0,false},{2,14,false}}) do
    local ev={};local T=H.newRecoveryTrace("waiting token unit",function(e) ev[#ev+1]=e end)
    T.plan(0,{kind="fight"},0);T.submit(0,10,0,255,0x100)
    local waiting=ev[#ev].id
    T.start(0,20,entry[1],entry[2],0x100,{100,100,100,100},20,0,
      {counter=entry[3],queued_command=entry[1],queued_attack=entry[2]})
    T.hpEffect(0,21,4,100,50,entry[1],entry[2])
    T.resolve(0,22,{100,100,100,100},20,0)
    check(#ev==2 and T.queued[0][1].id==waiting,
      "same-actor counter/engine/untraced command cannot consume the normal Fight queue entry")
    local good=T.start(0,30,0,255,0x100,{100,100,100,100},20,0)
    T.hpEffect(0,31,4,100,50,0,127,{context=good})
    check(ev[#ev].event=="hp_effect" and ev[#ev].id==waiting,
      "the waiting accepted Fight owns effects only when its own normal dispatcher starts")
  end
end

print(string.format("care_race_selftest: PASS -- %d checks: the Gate's lift, #414's review case, the 250 "
  .. "Potion that lifts nothing, spend before dying, the finisher, the raise that dies again and the one that "
  .. "stands, scarcity, the aftermath bill, the horizon, the score's order, the hit chance, the cost margin, calibration, the bag's count, the damage now, the median hit, the worst case's lift, the retarget, the Runic's cure, the last stand and its guard, the draws, the full gauge, Kefka's raise, near fatal, the carried swing, zombie and left-member candidate vetoes", n))

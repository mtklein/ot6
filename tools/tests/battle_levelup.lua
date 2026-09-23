-- @suite savestate=worldmap_narshe
-- battle_levelup.lua -- full HP and MP restore on level up.
--
-- When a character gains a level, current HP and MP refill to the new
-- maxima.  OT6 implements it as a jsl at the tail of vanilla DoLevelUp into
-- Ot6LevelUpHeal (ff6/src/battle/ot6.asm), which writes the battle
-- current-HP and MP cells ($3bf4,y and $3c08,y) rather than the $1600
-- record, because the victory sequence copies those battle cells back over
-- the record (UpdateSRAM) right after WinBattle returns.
--
--   positive  the battle where a character's level rises: the $1600 record
--             afterwards holds current HP == the new max and current MP ==
--             the new max.
--   UpdateSRAM control: the record's 3-byte XP cell is latched before each
--             battle and must move across a won battle, or every assertion
--             above would be reading stale bytes.
--   negative  in the same battles, a character whose level did not rise
--             keeps spent state: current HP and MP never exceed the latched
--             pre-battle values, and the arm only counts as exercised when
--             a non-leveler ended a battle below max.
--
-- How many battles: the climber's deficit over the least XP a win here
-- can pay, plus slack -- both read at run time, not assumed.  The fixture's
-- deficit moves with every regeneration of the chain (the XP the route's
-- earlier randoms paid), and which formations the grass deals is the
-- save's encounter counter's to choose: the pool is a lone Leafer at
-- 160/256 beside Leafer x2 + Dark Wind at 96/256, so a fixture can meet
-- nothing but lone Leafers.  The least a win pays is the pool's smallest
-- formation, read from the ROM below (winXp); every battle's actual pay
-- is logged beside it, and a failed verdict names any battle that paid
-- the climber less.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local LVLEXP = H.sym("LevelUpExp") & 0x3FFFFF

-- $1600 character record fields; roster char index c = record base 0x1600+37c.
local function recBase(c) return 0x1600 + 37 * c end
local function level(c) return H.readByte(recBase(c) + 0x08) end
local function curHp(c) return H.readWord(recBase(c) + 0x09) end
local function maxHp(c) return H.readWord(recBase(c) + 0x0B) end
local function curMp(c) return H.readWord(recBase(c) + 0x0D) end
local function maxMp(c) return H.readWord(recBase(c) + 0x0F) end
local function exp(c)
  local b = recBase(c) + 0x11
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end

-- CheckLevelUp's own arithmetic (battle_main.asm:16074-16095): XP to leave
-- level L is 8 * sum(LevelUpExp[1..L]), read from the same ROM table.
local function neededXp(L)
  local s = 0
  for i = 1, L do s = s + H.readRomWord(LVLEXP + (i - 1) * 2) end
  return s * 8
end

local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end

-- The XP one random win pays each member for formation `f`: WinBattle
-- (battle_main.asm @5d91) sums the defeated monsters' MonsterProp+12
-- words, Ot6RewardScale_ext scales a random battle's sum by
-- Ot6RewardMulW/16, and the result is divided among the members alive at
-- the end ($3a76).  With everyone standing that is the least it pays; an
-- Exp. Egg doubles a share and a fallen member raises the others'.
local MONSTER_PROP = H.sym("MonsterProp") & 0x3FFFFF
local REWARD_MUL = H.sym("Ot6RewardMulW") & 0x3FFFFF
local function winXp(f, alive)
  local sum = 0
  for _, sp in ipairs(f.species) do sum = sum + H.readRomWord(MONSTER_PROP + sp * 32 + 12) end
  return (sum * H.readRomByte(REWARD_MUL) // 16) // alive
end
-- the grass legs' goals (battleLeg's walk toggles between them)
local GOALS = { { 82, 56 }, { 82, 50 } }
-- battles allowed after the one that crosses the line: one for the
-- negatives that need a post-level battle, one spare
local SLACK = 2
-- legs built into the step list; the run takes the first `budget` of them
local MAX_LEGS = 40

local members = {}          -- roster char indices in the active party
local base = {}             -- per-char pre-battle latch
local positives = 0
local hpNegSeen, mpNegSeen = false, false
local battles = 0
local battleHpDeficit = false
local budget = nil          -- battles this run may fight (set at the precondition)
local winMin = nil          -- the least XP a win here pays a member (from the ROM)
local climber = nil
local underpaid = {}        -- battles that paid the climber less than winMin
local battleAge = 0
local skipSaid = false
local function done()
  return positives >= 1 and hpNegSeen and mpNegSeen
end

local function latch()
  for _, c in ipairs(members) do
    base[c] = { level = level(c), hp = curHp(c), mp = curMp(c), exp = exp(c) }
  end
end

local MENU, ACTOR, MSTATE, CMDTBL = 0x7BCA, 0x62CA, 0x7BC2, 0x202E
local ST_TRANS, ST_CMD, ST_MAGIC, ST_TGT = 0x01, 0x05, 0x0E, 0x38
local FIRE = 0x00
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local function spellEntry(slot, id)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then
      return i, H.readByte(a + 3)
    end
  end
  return nil, nil
end
local lastActor, mfM, actM = nil, 0, nil
-- how the cast attempt went, so a lost menu race is reported as itself
local firePlanned, fireListSeen = 0, 0
local listThisTurn = false
local function battleReset()
  lastActor = nil
  battleHpDeficit = false
end
local function battlePulse()
  if H.readByte(MENU) == 0 then
    lastActor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR)
  -- Once the positive has fired, deliberately give the enemies time to
  -- make the HP negative non-vacuous.  This is still ordinary input: the
  -- party Defends until somebody is hurt, then resumes the normal win.
  if positives >= 1 and not hpNegSeen and not battleHpDeficit then
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF and H.readWord(0x3BF4 + s * 2)
          < H.readWord(0x3C1C + s * 2) then
        battleHpDeficit = true
      end
    end
  end
  if lastActor ~= a then
    lastActor, mfM = a, 0
    actM = "fight"
    listThisTurn = false
    if H.readByte(0x3ED8 + a * 2) == 0x00 then
      local i, cost = spellEntry(a, FIRE)
      if i ~= nil and H.readWord(0x3C08 + a * 2) >= (cost or 255) then
        actM = "fire"
        firePlanned = firePlanned + 1
      end
    end
  end
  mfM = mfM + 1
  local hold = (mfM % 10) < 5
  local st, btn = H.readByte(MSTATE), nil
  if st == ST_TRANS then
    -- the window is being built: any press here is read by whatever opens
    H.setPad({})
    return
  end
  if positives >= 1 and not hpNegSeen and not battleHpDeficit then
    if st == ST_CMD then
      -- Right from the command list selects Defend; alternate the direction
      -- and confirmation edges so neither is swallowed by the opening frame.
      local q = mfM % 40
      btn = (q < 10) and "right" or ((q >= 20 and q < 30) and "a" or nil)
    else
      btn = "b"
    end
    H.setPad((hold and btn) and { [btn] = true } or {})
    return
  end
  if st == ST_CMD then
    btn = "a"
    if actM == "fire" then
      local cell = nil
      for i = 0, 3 do
        if H.readByte(CMDTBL + a * 12 + i * 3) == 0x02 then cell = i end
      end
      if cell == nil then actM = "fight"
      else
        local cur = H.readByte(0x890F + a)
        if cur ~= cell then btn = (cur < cell) and "down" or "up" end
      end
    end
  elseif st == ST_MAGIC then
    if actM ~= "fire" then btn = "b"
    else
      if not listThisTurn then
        listThisTurn = true
        fireListSeen = fireListSeen + 1
      end
      local i = spellEntry(a, FIRE)
      if i == nil then actM = "fight"; btn = "b"
      else
        local wantRow, wantCol = i // 2, i % 2
        local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
        local col = H.readByte(0x8917 + a)
        btn = "a"
        if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
        elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left" end
      end
    end
  elseif st == ST_TGT then
    btn = "a"
  else
    btn = "b"          -- every other window: back out, never confirm blind
  end
  H.setPad((hold and btn) and { [btn] = true } or {})
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  -- the precondition plans the legs' paths over the world tilemap in
  -- WRAM, so the map must be settled (loaded and faded in)
  H.waitUntil(function() return H.worldSettled() end, 1500, "the world map settled", 5),
  H.call(function()
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then members[#members + 1] = c end
    end
    H.assertEq(#members >= 2, true,
      "two party members: one to level, one for the negative control")
    local nearest, deficit = nil, nil
    for _, c in ipairs(members) do
      local d = neededXp(level(c)) - exp(c)
      H.log(string.format("char %d: L%d exp=%d threshold=%d deficit=%d "
        .. "hp=%d/%d mp=%d/%d", c, level(c), exp(c), neededXp(level(c)), d,
        curHp(c), maxHp(c) & 0x3FFF, curMp(c), maxMp(c) & 0x3FFF))
      -- precondition: no HP/MP-boost relic, so effective max == the low-14-bit
      -- base and "current == (max & $3fff)" is the exact full-refill check.
      H.assertEq(maxHp(c) & 0xC000, 0,
        "char " .. c .. " max HP carries no boost tier")
      H.assertEq(maxMp(c) & 0xC000, 0,
        "char " .. c .. " max MP carries no boost tier")
      if deficit == nil or d < deficit then nearest, deficit = c, d end
    end
    -- the least a win on the grass legs pays one member, from the ROM:
    -- every formation in every group the legs' paths roll from, with the
    -- whole party standing -- and in any ENTRY group, the zone of the
    -- engine's saved position (where the party entered the world), which
    -- the first battle rolls from when that zone is not the legs' own
    -- (H.worldPathGroups)
    local groups, entry = H.worldPathGroups({ { H.worldX(), H.worldY() }, GOALS[1], GOALS[2],
      GOALS[1] })
    H.assertEq(#groups > 0, true, "the grass legs roll random battles somewhere on their paths")
    local zx, zy = H.worldZonePos()
    H.log(string.format("grass legs: group(s) %s; the engine's saved position is (%d,%d)%s",
      table.concat(groups, ","), zx, zy, #entry > 0 and (", entry group(s) "
        .. table.concat(entry, ",")) or ", in the legs' own zones"))
    for _, list in ipairs({ { "grass", groups }, { "entry", entry } }) do
      for _, g in ipairs(list[2]) do
        local pool = H.encounterPool(g)
        for slot = 1, 4 do
          for _, f in ipairs(pool[slot].formations) do
            local xp = winXp(f, #members)
            H.log(string.format("%s pool: group %d slot %d (%d/256) formation %d pays %d XP "
              .. "a member", list[1], g, slot, pool[slot].odds, f.id, xp))
            if winMin == nil or xp < winMin then winMin = xp end
          end
        end
      end
    end
    H.assertEq(winMin > 0, true, "every formation the grass deals pays XP")
    -- the budget: enough least-paying wins to cross the line, plus SLACK
    climber = nearest
    budget = (deficit + winMin - 1) // winMin + SLACK
    H.log(string.format("climber: char %d, %d XP short; the least a win pays is %d, so "
      .. "the budget is %d battle(s) (%d to cross + %d slack)", nearest, deficit, winMin,
      budget, budget - SLACK, SLACK))
    -- the precondition, consistent with the budget: the step list holds
    -- MAX_LEGS battles, so the deficit must be crossable inside them
    H.assertEq(budget <= MAX_LEGS, true, string.format(
      "char %d's deficit (%d XP at %d a win) is crossable within the %d battles the "
      .. "step list holds", nearest, deficit, winMin, MAX_LEGS))
  end),
})

-- one earned battle: walk the grass area, fight through the real menus,
-- then judge every record against its pre-battle latch.
-- Steps after the first two only run while the goal is unmet (H.cond), so a
-- lucky early run costs two battles and an unlucky one has budget.
local function battleLeg(n)
  local plan, idx, goal = nil, 1, { 82, 56 }
  local advance = {
    H.waitUntil(worldReady, 1500, "world control before battle " .. n, 5),
    H.call(function()
      latch()
      battles = n
      battleReset()
      H.log(string.format("battle %d: records latched", n))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        if not H.worldMode() then H.setPad({}); return end
        if not H.worldHasControl() then plan = nil; H.setPad({}); return end
        if not H.worldAligned() then return end
        if not plan or idx > #plan then
          if H.worldX() == goal[1] and H.worldY() == goal[2] then
            goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
          end
          plan = H.worldBfs(goal[1], goal[2]); idx = 1
          if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
        end
        local dir = plan[idx]; idx = idx + 1
        if not dir then H.setPad({}); return end
        H.setPad({ [dir] = true })
      end),
    }, "grass-area encounter " .. n),
    H.release(),
    H.call(function() battleAge = 0 end),
    H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(function()
        battleAge = battleAge + 1
        if battleAge == 60 then
          -- the formation as it opened, for the record (reads only)
          local names = {}
          for _, s in ipairs(H.formationSpecies()) do
            names[#names + 1] = string.format("%03X", s.species)
          end
          H.log(string.format("battle %d: formation %d [%s]", n,
            H.readWord(0x11E0) & 0x1FF, table.concat(names, " ")))
        end
        battlePulse()
      end),
    }, "battle " .. n .. " fought through the real menus"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(worldReady, 1500, "back on the world after battle " .. n, 5),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.partyWiped(), false, "the party survived battle " .. n)
      for _, c in ipairs(members) do
        local b = base[c]
        H.log(string.format("battle %d char %d: L%d->%d exp %d->%d "
          .. "hp %d->%d/%d mp %d->%d/%d", n, c, b.level, level(c), b.exp,
          exp(c), b.hp, curHp(c), maxHp(c) & 0x3FFF, b.mp, curMp(c),
          maxMp(c) & 0x3FFF))
        -- a won battle must move the record's XP cell.  If it did not,
        -- UpdateSRAM never ran and every claim below would be reading
        -- stale bytes.
        H.assertEq(exp(c) > b.exp, true, string.format(
          "char %d's record XP moved across the win (UpdateSRAM ran) -- "
          .. "the baseline-latch control", c))
        if level(c) > b.level then
          -- positive: leveled this battle, so currents == the new maxima.
          positives = positives + 1
          H.assertEq(curHp(c), maxHp(c) & 0x3FFF, string.format(
            "char %d leveled (L%d->L%d): HP refilled to the NEW max",
            c, b.level, level(c)))
          H.assertEq(curMp(c), maxMp(c) & 0x3FFF, string.format(
            "char %d leveled: MP refilled to the NEW max", c))
        else
          -- negative: no level, so nothing refills.  Currents can only have
          -- fallen (damage taken, MP spent) or held; a rise means a refill
          -- fired without a level.
          H.assertEq(level(c), b.level,
            "char " .. c .. " did not level (negative control)")
          H.assertEq(curHp(c) <= b.hp, true, string.format(
            "char %d's un-leveled HP was not restored (%d -> %d)",
            c, b.hp, curHp(c)))
          H.assertEq(curMp(c) <= b.mp, true, string.format(
            "char %d's un-leveled MP was not restored (%d -> %d)",
            c, b.mp, curMp(c)))
          if curHp(c) < (maxHp(c) & 0x3FFF) then hpNegSeen = true end
          if curMp(c) < (maxMp(c) & 0x3FFF) then mpNegSeen = true end
        end
      end
      -- the budget's premise, read live: no win pays the climber less
      -- than the pool's least-paying formation
      local paid = exp(climber) - base[climber].exp
      if paid < winMin then underpaid[#underpaid + 1] = n .. ":" .. paid end
      H.log(string.format("after battle %d: positives=%d hpNeg=%s mpNeg=%s "
        .. "casts planned=%d reached-list=%d; the climber was paid %d (the pool's least %d)",
        n, positives, tostring(hpNegSeen), tostring(mpNegSeen), firePlanned,
        fireListSeen, paid, winMin))
    end),
  }
  if n <= 2 then
    add(advance)
  else
    add({ H.cond(function() return not done() and n <= budget end, advance, {
      H.call(function()
        if not skipSaid then
          skipSaid = true
          H.log(string.format("battles %d..%d skipped -- %s", n, MAX_LEGS,
            done() and "goal already met" or ("past the budget of " .. budget)))
        end
      end),
    }) })
  end
end

-- Budget: the precondition's `budget` of earned battles (the climber's
-- deficit over the least a win pays, plus SLACK); two are always fought
-- (the crossing one and at least one post-level negative), the rest only
-- while needed.
for n = 1, MAX_LEGS do battleLeg(n) end

add({
  H.call(function()
    H.assertEq(positives >= 1, true, string.format(
      "a level was EARNED and its refill observed (%d level-ups across %d "
      .. "battles, of a budget of %d at the least %d XP a win; battles that paid "
      .. "the climber less than that: %s)", positives, battles, budget, winMin,
      #underpaid > 0 and table.concat(underpaid, " ") or "none"))
    -- the negative arms must have been exercised, or their <=
    -- comparisons above were comparing full to full
    H.assertEq(hpNegSeen, true,
      "a non-leveler really ended a battle below max HP -- the HP negative "
      .. "was non-vacuous")
    -- the MP arm is only observable if the driver actually spent MP, so say
    -- which half failed.  A planned cast that never reached the magic list is
    -- the driver losing the command-window race, not a level-up defect.
    H.assertEq(fireListSeen >= 1, true, string.format(
      "the driver reached TERRA's magic list -- planned a cast on %d turns "
      .. "and got into the list on %d.  planned>0 with reached==0 means the "
      .. "command window was confirmed on row 0 (Fight) before the cursor "
      .. "walked to Magic; fix the drive, do not relax the MP control below",
      firePlanned, fireListSeen))
    H.assertEq(mpNegSeen, true, string.format(
      "a non-leveler really ended a battle below max MP -- the MP negative "
      .. "was non-vacuous (Terra's own post-level casts; %d planned, %d "
      .. "reached the list across %d battles)",
      firePlanned, fireListSeen, battles))
    H.log("[levelup] earned positive + live negatives, zero writes")
  end),
})

H.run({ maxFrames = 200000 }, steps)

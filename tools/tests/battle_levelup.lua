-- @suite savestate=worldmap_narshe
-- battle_levelup.lua -- v0.4 test: FULL HP/MP RESTORE ON LEVEL UP.
--
-- The mechanic (docs/design/mp-economy.md "Full HP/MP restore on level up"):
-- when a character gains a level, current HP and MP refill to the new maxima.
-- OT6 implements it as a jsl at the tail of vanilla DoLevelUp
-- (battle_main.asm) into Ot6LevelUpHeal (ff6/src/battle/ot6.asm), which writes
-- the battle current-HP/MP cells ($3bf4,y / $3c08,y) -- NOT the $1600 record --
-- because the victory sequence copies those battle cells back over the record
-- (UpdateSRAM, battle_main.asm:12136-12141) right after WinBattle returns.
--
-- ISSUE #75 CONVERSION -- the level is EARNED, and the record is its own
-- check.  The old file pinned XP one threshold over, planted a $3FFF record
-- sentinel, forced the win by writing the battle-clearing flag, and faked the
-- negative with a level-50 poke.  All of it is replaced by the fixture's own
-- arithmetic:
-- worldmap_narshe's TERRA stands 23 XP short of level 5 (measured 2026-08-10:
-- exp=377, threshold=400 via LevelUpExp -- the genuine near-boundary save the
-- burn-down plan hoped a recon would find), while LOCKE needs 342 more, so
-- one grass-area battle levels her and cannot level him.  Real world
-- encounters are walked into (battle_fold's grass-area loop), fought through
-- the real menus (newFightDriver -- Terra casts her real Fire so her MP is
-- visibly SPENT, everyone else Fights), and won by damage.
--
--   POSITIVE  the battle where a character's level rises: the $1600 record
--             afterwards holds current HP == the NEW max and current MP ==
--             the NEW max.  Both are sharp: DoLevelUp grows the maxima and
--             UpdateSRAM copies the battle cells, so without Ot6LevelUpHeal
--             the record's currents keep their pre-level values (< new max --
--             for MP provably so, since Fire was cast this battle).
--   UPDATESRAM CONTROL (the sentinel's replacement, cb8e605 baseline-latch):
--             the record's 3-byte XP cell is latched before each battle and
--             must MOVE across a won battle -- a quiet win that skipped the
--             reward path would leave it, and every assertion above would be
--             reading stale bytes.
--   NEGATIVE  in the same battles, a character whose level did NOT rise keeps
--             spent state: current HP/MP never exceed the latched pre-battle
--             values (no refill for non-levelers), and the arm is only
--             counted NON-VACUOUS when a non-leveler really ended a battle
--             below max (HP: enemy hits land on whoever the AI picks; MP:
--             Terra's own casts in her post-level battles).
--
-- The loop fights until the positive fired and both negatives were seen
-- non-vacuously (budget: 6 battles; measured green in 2).
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

local members = {}          -- roster char indices in the active party
local base = {}             -- per-char pre-battle latch
local positives = 0
local hpNegSeen, mpNegSeen = false, false
local battles = 0
local function done()
  return positives >= 1 and hpNegSeen and mpNegSeen
end

local function latch()
  for _, c in ipairs(members) do
    base[c] = { level = level(c), hp = curHp(c), mp = curMp(c), exp = exp(c) }
  end
end

-- ---- the in-battle action machine: codex_ctx's measured pulse ----
-- TERRA casts her real Fire through the live magic menu (so MP is SPENT --
-- the thing the refill has to visibly restore), everyone else Fights;
-- 5-on/5-off held presses, A through messages.  One addition: the cast is
-- planned only while her battle MP covers the list's own cost cell (entry+3
-- of the $2092 spell list -- ot6_boost.asm:725's price authority), so a
-- drained pool falls back to Fight instead of buzzing the greyed row.
local MENU, ACTOR, MSTATE, CMDTBL = 0x7BCA, 0x62CA, 0x7BC2, 0x202E
local ST_CMD, ST_MAGIC, ST_TGT = 0x05, 0x0E, 0x38
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
local function battleReset() lastActor = nil end
local function battlePulse()
  if H.readByte(MENU) == 0 then
    lastActor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if lastActor ~= a then
    lastActor, mfM = a, 0
    actM = "fight"
    if H.readByte(0x3ED8 + a * 2) == 0x00 then
      local i, cost = spellEntry(a, FIRE)
      if i ~= nil and H.readWord(0x3C08 + a * 2) >= (cost or 255) then
        actM = "fire"
      end
    end
  end
  mfM = mfM + 1
  local hold = (mfM % 10) < 5
  local st, btn = H.readByte(MSTATE), nil
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
    btn = "a"          -- transitional states and battle messages
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
    -- the input-driven arm's precondition the burn-down plan asked a recon to find:
    -- somebody is near enough that a couple of grass battles cross the line.
    H.assertEq(deficit <= 200, true, string.format(
      "char %d is within reach of a level (deficit %d) -- if this "
      .. "fires, the fixture regeneration moved the XP and the fixture choice "
      .. "needs re-measuring, not a bigger budget", nearest, deficit))
    H.log(string.format("climber: char %d, %d XP short", nearest, deficit))
  end),
})

-- one earned battle: walk the grass area (battle_fold's loop), fight through
-- the real menus, then judge every record against its pre-battle latch.
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
    H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(battlePulse),
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
        -- the sentinel's replacement: a won battle MUST move the record's
        -- XP cell.  If it did not, UpdateSRAM never ran and every claim
        -- below would be reading stale bytes.
        H.assertEq(exp(c) > b.exp, true, string.format(
          "char %d's record XP moved across the win (UpdateSRAM ran) -- "
          .. "the baseline-latch control", c))
        if level(c) > b.level then
          -- POSITIVE: leveled this battle -> currents == the NEW maxima.
          positives = positives + 1
          H.assertEq(curHp(c), maxHp(c) & 0x3FFF, string.format(
            "char %d leveled (L%d->L%d): HP refilled to the NEW max",
            c, b.level, level(c)))
          H.assertEq(curMp(c), maxMp(c) & 0x3FFF, string.format(
            "char %d leveled: MP refilled to the NEW max", c))
        else
          -- NEGATIVE: no level -> nothing refills.  Currents can only have
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
      H.log(string.format("after battle %d: positives=%d hpNeg=%s mpNeg=%s",
        n, positives, tostring(hpNegSeen), tostring(mpNegSeen)))
    end),
  }
  if n <= 2 then
    add(advance)
  else
    add({ H.cond(function() return not done() end, advance, {
      H.call(function()
        H.log(string.format("battle %d skipped -- goal already met", n))
      end),
    }) })
  end
end

-- Budget: up to 6 earned battles; two are always fought (the crossing one
-- and at least one post-level negative), the rest only while needed.
for n = 1, 6 do battleLeg(n) end

add({
  H.call(function()
    H.assertEq(positives >= 1, true, string.format(
      "a level was EARNED and its refill observed (%d level-ups across %d "
      .. "battles)", positives, battles))
    -- the negative arms must have been exercised for real, or their <=
    -- comparisons above were comparing full to full
    H.assertEq(hpNegSeen, true,
      "a non-leveler really ended a battle below max HP -- the HP negative "
      .. "was non-vacuous")
    H.assertEq(mpNegSeen, true,
      "a non-leveler really ended a battle below max MP -- the MP negative "
      .. "was non-vacuous (Terra's own post-level casts)")
    H.log("[levelup] earned positive + live negatives, zero writes")
  end),
})

H.run({ maxFrames = 200000 }, steps)

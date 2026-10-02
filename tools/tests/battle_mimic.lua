-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_mimic.lua -- a boosted Mimic is free and buys what the copied
-- action's boost buys  (#260)
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_mimic.lua <log>
--
-- mp-economy.md: Mimic is free, "vanilla Mimic copies the action and not the
-- price".  Vanilla makes it free twice over.  The copied action overwrites
-- the mimic's own queue slot ($3420/$3520, mimicreplace) and keeps the cost
-- that slot was queued at, which for command $12 is 0.  The one copy that is
-- queued afresh, an x-magic's second spell, goes through CreateAction with
-- $b1.6 set, which GetMPCost clears (`trb $b1`) and answers 0 for.  OT6's
-- Ot6QueueFold runs after GetMPCost on that same path and re-prices magic,
-- x-magic and lore from the caster's pending boost; before #260 it could not
-- see $b1.6.  This measures what a boosted mimic is charged, and what its
-- boost buys, not what the code says.  The verdict (last step): every case
-- charged 0 MP, a boosted copy of a tier-family head cast its tier (Fire 2
-- at 1 pip, Fire 3 at 2 and 3), the pips were spent, and a boosted copy of
-- anything outside the tier families -- Drain, a lore, a summon -- dealt
-- the x2/x4/x8 of the same copy unboosted.  Main at 6f8382cb fails it
-- (x-magic copies charged 38 and 20; plain copies of Fire cast plain Fire);
-- build/attempts/wt/mimic-charge/, and the negative controls for the
-- tier-3 and multiplier verdicts are under build/attempts/wt/mimic-suite/.
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt).  No fixture has Gogo:
-- he joins in the World of Ruin, past the route.  Nor does any fixture have
-- an x-magic caster (the Gem Box is World of Ruin too).  So after the cold
-- Continue, before the first step, this test writes two command bytes in
-- the field character records ($1600 + 37*id + $16..$19): the stand-in's
-- second command becomes Mimic ($12), and TERRA's Morph row becomes X-Magic
-- ($17).  Battle init builds the battle command lists from those bytes, so
-- everything after is the engine's own: the menus, the queue, the charge.
-- Nothing else is written.  This is a mechanism measurement of the mimic
-- charge, not play and not a claim about Gogo's balance.
--
-- The run: Continue fire-out-v1 (TERRA LOCKE STRAGO on the world map by
-- Thamasa; LOCKE is the stand-in, RELM would be if present), write the two
-- bytes, walk to an encounter, and snapshot TERRA's first window (X, for the
-- x-magic cases: her second spell waits out its own delay, and a TERRA worn
-- down by Defend rounds was killed in it), then Defend until the stand-in
-- has 3 pips banked and snapshot TERRA's window (T) and STRAGO's (S).  Each
-- case restores one snapshot: the source casts (unboosted unless the case
-- says; a summon is TERRA's worn esper, from the top of her Magic list),
-- everyone else Defends, and the stand-in, once the source's cast has
-- resolved (SaveForMimic has run for it), presses R to the case's boost and
-- picks Mimic.  Observed, never
-- written: every store to the MP-cost queue ($3620-$371F) with the queue
-- context, Ot6QueueFold's entries, mimicreplace's entry (what is copied,
-- the pending there), the staged cost $3A4C the stand-in's actions start
-- with, Ot6BoostDmg's entries for the stand-in, the damage a drain's calc
-- hands FixDrainDmg, damage numerals, and the stand-in's MP and BP at the
-- Mimic confirm and after Ot6ActionEnd.

-- The draw (#354 re-cut).  Every formation this plain deals by Thamasa holds
-- a Baskervor ($01D), whose retaliation is `if_num_monsters 1 / if_hit /
-- attack SNEEZE, NOTHING, NOTHING`: once one monster or fewer stands, a hit
-- on it may answer with Sneeze ($CB), which takes a party member out of the
-- fight ($3A39).  A source sneezed out between an x-magic's two spells never
-- casts the second, and a stand-in sneezed out before its Mimic never
-- copies, so the case cannot finish.  The v0.24 re-cut dealt the lone
-- Baskervor (formation $0A0): its first x-magic case sneezed TERRA out after
-- her Fire and waited 12000 frames for her Drain
-- (build/attempts/wt/mimic-v024/).
--
-- So the source aims every single-target pick at the sturdiest body (the
-- most HP standing; sturdiest, below), and the copy follows it.  Before the
-- copy resolves, the only body the cases can kill is that one: every
-- single-target hit lands on it, an all-target source cast is one unboosted
-- cast on bodies at full HP, and an all-target copy is the stand-in's last
-- action, whose counters come after it.  Each encounter is then read off
-- the ROM -- the species' AI scripts (M.partRoles' lastStand / lastStandN),
-- whether a holder's own death ends its script (`if_self_dead / end_if`
-- first in its retaliation), and the species' max HP -- and it is run from,
-- as a player keeping a party together would, when a Sneeze counter is
-- armed at the opening (N or fewer standing) or once the aimed body falls
-- (another holder left with N or fewer, or the aimed holder's own killing
-- blow when its death does not end its script); with a tie for the most HP
-- every tied body counts as aimed.  On this plain that runs from the lone
-- Baskervor (160) and the pair (191: either one's death leaves the other
-- alone) and measures 162, whose aimed Baskervor dies quietly and leaves
-- only the Cephaler.  The budget is the most encounters any
-- encounter-counter state needs to deal a measurable slot of the pool
-- CheckBattleWorld rolled (H.worstCaseEncounters; 19 for group 24 on the
-- v0.24 ROM).  A case that loses a member it still needs anyway (a KO, a
-- kill this reading did not foresee) fails at once, naming it, instead of
-- timing out.
--
-- Levers, for evidence only (the suite runs BURN 0, MUTANT nil): BURN runs
-- from that many encounters first, whatever they are, to vary the encounter
-- history (TESTING.md: the draw moves with encounters used up, not seeds);
-- MUTANT "take-any" measures the first draw after BURN with no Sneeze check
-- (the old behavior), "opening-only" checks only the opening (the first
-- fix, which measured 191), "refuse-all" calls every formation armed,
-- "budget-1" allows one draw, "other-group" decodes the budget for a
-- group the walk does not roll, "default-target" confirms the source's
-- target where the cursor opens (the old aim), "fell" reads every needed
-- member as KO'd (guard's fell branch).
local BURN, MUTANT = 0, nil

local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC = 0x05, 0x27, 0x38, 0x0E
local ST_LORE_OPEN, ST_LORE, ST_ESPER = 0x19, 0x1B, 0x16
local BANK, PEND, CURMP, MLISTPTR, STONE = 0x3E9C, 0x3E9D, 0x3C08, 0x302C, 0x3344
local MSCROLL, MCOL, MROW, LSCROLL, LROW = 0x8913, 0x8917, 0x891B, 0x891F, 0x8927
local CMD_MAGIC, CMD_LORE, CMD_MIMIC, CMD_XMAGIC = 0x02, 0x0C, 0x12, 0x17
local TERRA, LOCKE, STRAGO, RELM = 0, 1, 7, 8

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function listBase(s)
  local b = H.readWord(MLISTPTR + s * 2)
  if b < 0x2000 or b > 0x2600 then return nil end
  return b
end
-- magic grid cell (0..53) of a spell id, and its list cost
local function spellCell(s, id)
  local b = listBase(s)
  if not b then return nil end
  for cell = 0, 53 do
    local a = b + (cell + 1) * 4
    if H.readByte(a) == id then return cell, H.readByte(a + 3), H.readByte(a + 1) end
  end
end
local function loreRow(s, id)
  local b = listBase(s)
  if not b then return nil end
  for row = 0, 23 do
    local a = b + (55 + row) * 4
    if H.readByte(a) == id then return row, H.readByte(a + 3) end
  end
end
local function loreOffered(id) return H.readByte(0x306A + id) == id + 0x8B end

-- the field party and the two declared writes
local cast = {}          -- char id -> battle slot, filled at battle start
local standId, standS, terraS, stragoS
local function members()
  local p, t = H.readByte(0x1A6D) & 7, {}
  for c = 0, 13 do
    if (H.readByte(0x1850 + c) & 7) == p and p ~= 0 then t[#t + 1] = c end
  end
  return t
end
local function recCmd(c, r) return 0x1600 + 37 * c + 0x16 + r end

-- ---- the draw: Sneeze counters (see the header) -----------------------------
local MAXDRAWS = 24          -- draws built after BURN; the budget must fit
local worldGroup = nil       -- the group the last CheckBattleWorld rolled
local battleKey = nil        -- the last battle's key (H.firstBattleKey)
local function aiByte(species)
  local ptrs, base = H.sym("AIScriptPtrs") & 0x3FFFFF, H.sym("AIScript") & 0x3FFFFF
  local off = H.readRomWord(ptrs + species * 2)
  return function(i) return H.readRomByte(base + off + i) end
end
-- N of a species' `if_num_monsters N` retaliation that throws Sneeze, or nil
local function sneezeN(species)
  if species >= 0x180 then return nil end
  local r = H.partRoles(aiByte(species), 0)
  for _, a in ipairs(r.lastStand) do
    if a == H.SNEEZE then return r.lastStandN or 1 end
  end
end
-- its retaliation opens `if_self_dead / end_if` (FC 12 00 00 FE): its
-- death ends the script (AICmd_fe), so its killing blow throws nothing
local function quietDeath(species)
  local at, i = aiByte(species), 0
  while at(i) ~= 0xFF and i < H.AI_SCRIPT_MAX do i = i + (H.AI_OP_LEN[at(i)] or 1) end
  return at(i + 1) == 0xFC and at(i + 2) == 0x12 and at(i + 3) == 0 and at(i + 4) == 0
     and at(i + 5) == 0xFE
end
-- a species' max HP (MonsterProp +8, the word LoadMonsterProp seeds)
local function speciesHp(species)
  return H.readRomWord((H.sym("MonsterProp") & 0x3FFFFF) + species * 32 + 8)
end
-- why a formation of these species, all standing at full HP, can answer a
-- hit with a Sneeze before a copy resolves (header: at the opening, or once
-- the aimed body falls); nil when it cannot
local function sneezeArmed(species)
  if MUTANT == "refuse-all" then return "MUTANT refuse-all" end
  local n, top = #species, -1
  for _, sp in ipairs(species) do
    local N = sneezeN(sp)
    if N and n <= N then
      return string.format("$%03X throws Sneeze at a hit once %d or fewer stand, and %d stand%s",
        sp, N, n, n == 1 and "s" or "")
    end
    top = math.max(top, speciesHp(sp))
  end
  if MUTANT == "opening-only" then return nil end
  for k, aimed in ipairs(species) do
    if speciesHp(aimed) == top then
      local N = sneezeN(aimed)
      if N and n - 1 <= N and not quietDeath(aimed) then
        return string.format("$%03X (aimed, %d HP) throws Sneeze at its own killing blow, "
          .. "%d left standing", aimed, top, n - 1)
      end
      for j, sp in ipairs(species) do
        N = sneezeN(sp)
        if j ~= k and N and n - 1 <= N then
          return string.format("killing the aimed $%03X (%d HP) leaves $%03X, which throws Sneeze "
            .. "once %d or fewer stand, with %d", aimed, top, sp, N, n - 1)
        end
      end
    end
  end
end
local budgets = {}
local function budgetFor(group)
  if budgets[group] then return budgets[group] end
  local pool = H.encounterPool(group)
  local ok, parts = {}, {}
  for slot = 1, 4 do
    ok[slot] = true
    local names = {}
    for _, f in ipairs(pool[slot].formations) do
      local why = sneezeArmed(f.species)
      ok[slot] = ok[slot] and why == nil
      local sp = {}
      for _, s in ipairs(f.species) do sp[#sp + 1] = string.format("%03X", s) end
      names[#names + 1] = string.format("%d [%s]%s", f.id, table.concat(sp, " "),
        why and (" armed: " .. why) or "")
    end
    parts[#parts + 1] = string.format("slot %d (%d/256) %s%s", slot, pool[slot].odds,
      table.concat(names, ", "), ok[slot] and " measurable" or "")
  end
  local worst = H.worstCaseEncounters(function() return function(slot) return ok[slot] end end)
  H.log(string.format("[mimic] budget: group %d: %s -- the worst of the 65536 encounter-counter "
    .. "states needs %d encounter(s) to deal a measurable slot", group, table.concat(parts, "; "), worst))
  H.assertEq(worst <= MAXDRAWS, true, string.format("group %d deals a formation with no Sneeze "
    .. "counter armed within the %d draws built (worst counter state: %d)", group, MAXDRAWS, worst))
  budgets[group] = worst
  return worst
end

-- ---- observers -------------------------------------------------------------
local armed = nil        -- the case being measured
local function rd16(a) return H.readWord(a) end
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFFFF end
  local function cy() return emu.getState()["cpu.y"] & 0xFFFF end
  local cbw = H.sym("CheckBattleWorld")
  emu.addMemoryCallback(function() worldGroup = H.worldCheckGroup() end, emu.callbackType.exec, cbw, cbw)
  -- each battle's key (seed at its store, formation, encounter counters),
  -- so a sweep counts its draws by distinct battle, not by run
  local ss = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    battleKey = H.firstBattleKey(emu.getState()["cpu.a"] & 0xFF, H.readWord(0x11E0))
  end, emu.callbackType.exec, ss, ss)
  emu.addMemoryCallback(function(addr, v)
    if armed == nil or armed.endF then return end
    armed.stores[#armed.stores + 1] = string.format("[$%04X<-%d x=%02X 3a7a=$%02X 3a7b=$%02X]",
      addr & 0xFFFF, v, cx(), H.readByte(0x3A7A), H.readByte(0x3A7B))
    if cx() == standS * 2 then armed.standStores[#armed.standStores + 1] = v end
  end, emu.callbackType.write, 0x7E3620, 0x7E371F)
  local qf = H.sym("Ot6QueueFold")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = cx()
    if x == armed.src * 2 and not armed.srcDone then
      armed.srcQueued = armed.srcQueued + 1
      if armed.srcQueued >= #armed.picks then armed.srcDone = true end
    end
    armed.folds[#armed.folds + 1] = string.format("[x=%02X y=%02X 3a7a=$%02X 3a7b=$%02X pend=%d b1=$%02X]",
      x, cy(), H.readByte(0x3A7A), H.readByte(0x3A7B),
      x < 8 and H.readByte(PEND + x) or -1, H.readByte(0x00B1))
  end, emu.callbackType.exec, qf, qf)
  local sfm = H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    armed.sfmAll[#armed.sfmAll + 1] = string.format("x=%02X:$%04X@f%d", cx(), rd16(0x3A7C), H.frame)
    if cx() == armed.src * 2 then
      armed.srcTargets = string.format("$%04X", rd16(0x3A30))
      local hp = {}
      for m = 0, 5 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + (4 + m) * 2)) end
      armed.monHpAtSave = table.concat(hp, ",")
      armed.srcSaved = armed.srcSaved + 1
      armed.srcActs[#armed.srcActs + 1] = string.format("$%04X", rd16(0x3A7C))
    end
  end, emu.callbackType.exec, sfm, sfm)
  local mr = H.sym("mimicreplace")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    armed.replace = string.format("mimicreplace x=%02X: 3f20=$%04X 3f24=$%04X 3f28=$%02X pend=%d bank=%d mp=%d",
      cx(), rd16(0x3F20), rd16(0x3F24), H.readByte(0x3F28), pend(standS), bank(standS), mp(standS))
    armed.inStand = true
  end, emu.callbackType.exec, mr, mr)
  emu.addMemoryCallback(function(_, v)
    if armed == nil or armed.endF or not armed.inStand then return end
    if cx() ~= standS * 2 then return end
    armed.staged[#armed.staged + 1] = string.format("%d(3a7c=$%04X)", v, rd16(0x3A7C))
  end, emu.callbackType.write, 0x7E3A4C, 0x7E3A4C)
  local bd = H.sym("Ot6BoostDmg")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF or not armed.inStand then return end
    if cx() ~= standS * 2 then return end
    armed.dmg[#armed.dmg + 1] = string.format("[b5=$%02X 3a7c=$%02X 3a7d=$%02X pend=%d base=%d]",
      H.readByte(0x00B5), H.readByte(0x3A7C), H.readByte(0x3A7D), pend(standS), rd16(0x11B0))
    armed.castIds[#armed.castIds + 1] = H.readByte(0x3A7D)
  end, emu.callbackType.exec, bd, bd)
  local lastLo = {}
  emu.addMemoryCallback(function(addr, value)
    if armed == nil or armed.endF then return end
    local a = addr & 0xFFFF
    if a % 2 == 0 then lastLo[a] = value return end
    local w = (lastLo[a - 1] or 0) | (value << 8)
    if w == 0xFFFF then return end
    local t = armed.inStand and armed.standNums or armed.srcNums
    t[#t + 1] = string.format("%d", w & 0x3FFF) .. ((w & 0x4000) ~= 0 and "m" or "")
    -- the stand-in's HP damage numerals, for the multiplier verdict
    if armed.inStand and (w & 0x4000) == 0 and (w & 0x3FFF) > 0 then
      armed.standDmg[#armed.standDmg + 1] = w & 0x3FFF
    end
  end, emu.callbackType.write, 0x7E33D0, 0x7E33E3)
  -- A drain's numeral is not its damage: the drain caps it (FixDrainDmg and
  -- the heal half after it), and on fire-out-v1 the cap that binds is the
  -- stand-in's missing HP -- boost 0, 1 and 3 copies of Drain all showed 68
  -- against a 750-HP target, with the stand-in at 1147/1215
  -- (build/attempts/wt/mimic-suite/explore2-drain-615ed364.log).  So the
  -- drain's multiplier is read where the damage calc hands the drain its
  -- number: $f0 at FixDrainDmg's entry, after Ot6BoostDmg and the variance,
  -- before either cap.
  local fd = H.sym("FixDrainDmg")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x, y = cx(), cy()
    armed.drainLog[#armed.drainLog + 1] = string.format("[x=%02X y=%02X f0=%d tgtHP=%d atkHP=%d/%d]",
      x, y, H.readWord(0x00F0), H.readWord(0x3BF4 + y), H.readWord(0x3BF4 + x), H.readWord(0x3C1C + x))
    if armed.inStand and x == standS * 2 and armed.drainPre == nil then armed.drainPre = H.readWord(0x00F0) end
  end, emu.callbackType.exec, fd, fd)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = cx()
    if x == armed.src * 2 and armed.srcMpEnd == nil then armed.srcMpEnd = mp(armed.src) end
    if x == standS * 2 and armed.inStand then
      armed.endF = H.frame
      armed.mpEnd, armed.pendAtEnd, armed.bankAtEnd = mp(standS), pend(standS), bank(standS)
    end
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the per-case menu policy ----------------------------------------------
local tick, held = 0, nil
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  return nil
end

local function steerMagic(s, id)
  local cell = spellCell(s, id)
  if cell == nil then error("spell $" .. string.format("%02X", id) .. " not in list", 0) end
  local wr, wc = cell // 2, cell % 2
  local ar = H.readByte(MSCROLL + s) + H.readByte(MROW + s)
  local col = H.readByte(MCOL + s)
  if ar < wr then return "down" end
  if ar > wr then return "up" end
  if col < wc then return "right" end
  if col > wc then return "left" end
  return "a"
end

local function decide(c)
  if H.readByte(MENU) == 0 then return nil end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == c.src and not c.srcDone then
    if st == ST_CMD then
      if pend(c.src) < (c.srcBoost or 0) then return "r" end
      local want = cmdRow(c.src, c.cmd)
      local cur = H.readByte(CMDROW + c.src) & 3
      if cur ~= want then return cur < want and "down" or "up" end
      c.srcMp0 = mp(c.src)
      return "a"
    end
    if st == ST_MAGIC then
      -- a summon: from the top of the list UP opens the esper window
      if c.summon then return "up" end
      if c.tgtSeen then c.tgtSeen = false; c.pickIdx = c.pickIdx + 1 end
      return steerMagic(c.src, c.picks[math.min(c.pickIdx, #c.picks)])
    end
    if st == ST_ESPER and c.summon then return "a" end
    if st == ST_LORE_OPEN then return nil end
    if st == ST_LORE then
      local want = loreRow(c.src, c.picks[1])
      local cur = H.readByte(LSCROLL + c.src) + H.readByte(LROW + c.src)
      if cur < want then return "down" end
      if cur > want then return "up" end
      return "a"
    end
    if st == ST_TGT then
      c.tgtSeen = true
      return "a"
    end
    return nil
  end
  if a == standS and c.srcDone and not c.mimicSent then
    if c.srcSaved < #c.picks then return nil end       -- the source's cast has not resolved
    if st == ST_TGT then
      -- Mimic's own target (itself): this A is the confirm
      c.mp0, c.pendAtConfirm, c.bank0 = mp(standS), pend(standS), bank(standS)
      c.mimicSent = true
      return "a"
    end
    if st ~= ST_CMD then return nil end
    if pend(standS) < c.boost then return "r" end
    local want = cmdRow(standS, CMD_MIMIC)
    local cur = H.readByte(CMDROW + standS) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  end
  if a == standS and c.mimicSent and st == ST_TGT and c.replace == nil then return "a" end
  return defendPress(st)
end

-- The members a case still needs are in the fight and on their feet: the
-- source until its last pick's SaveForMimic, the stand-in until its Mimic's
-- Ot6ActionEnd.  One sneezed out ($3A39, the member's bit) or KO'd ($3EE4
-- bit 7) never finishes its part, so the case fails here, naming it.
local function guard(c)
  local left, need = H.leftMask(), {}
  if not (c.srcDone and c.srcSaved >= #c.picks) then
    need[#need + 1] = { c.src, "the source", "its cast resolved" }
  end
  if c.endF == nil then need[#need + 1] = { standS, "the stand-in", "its Mimic resolved" } end
  for _, n in ipairs(need) do
    local s = n[1]
    local st1 = H.readByte(0x3EE4 + s * 2)
    if MUTANT == "fell" then st1 = st1 | 0x80 end
    local out, ko = ((left >> s) & 1) == 1, (st1 & 0x80) ~= 0
    if out or ko then
      error(string.format("case %s: %s (slot %d) %s before %s ($3A39=$%02X, status1 $%02X; "
        .. "SaveForMimic{%s}) -- the case cannot finish", c.name, n[2], s,
        out and "LEFT the fight" or "fell", n[3], left, st1, table.concat(c.sfmAll, " ")), 0)
    end
  end
end

-- The source's target: a single-target pick goes to the monster with the
-- most HP standing, and the copy follows it (Mimic replays the targets).
-- The Sneeze counter arms only once a kill leaves one monster standing
-- (header), and a source or a copy aimed at the frailest body kills it
-- first: on the re-cut's Cephaler + Baskervor draw ($0A2, 420 and 750 HP)
-- TERRA's Drain + Fire took the Cephaler at the default cursor, the
-- stand-in's copied Drain went on to the lone Baskervor, and its Sneeze
-- took the stand-in out before the copied Fire (build/attempts/wt/
-- mimic-v024/).  The Baskervor's own death stops its script (`if_self_dead
-- / end_if` ends it), so on that draw a kill on the sturdiest body arms
-- nothing; a draw where it would (191, two Baskervors) is run from
-- (sneezeArmed).  An all-target pick (a lore, a summon) is confirmed as it opens.  Steered
-- with H.targetCursor, its taps paced as battle_assassinate paces them.
local function sturdiest()
  local best, hp = nil, -1
  for _, e in ipairs(H.activeSlots()) do
    local v = H.readWord(0x3BF4 + (4 + e.slot) * 2)
    if v > hp then best, hp = e.slot, v end
  end
  return best
end
local T = H.targetCursor()
local mf, tapNo, tapAt = 0, -1, 0
-- the pad for the source's own target window, or false when this is not it
local function aimPress(c)
  if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT or (H.readByte(ACTOR) & 3) ~= c.src
     or c.srcDone then
    mf, tapNo = 0, -1
    return false
  end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local m = T.mask
  if m == nil then return {} end
  local btn
  if (m & (m - 1)) ~= 0 then
    btn = edge and "a" or nil                  -- all targets
  else
    c.tgtSlot = c.tgtSlot or sturdiest()
    btn = T.steer(c.tgtSlot, mf)
    if btn == "a" then
      if not edge then btn = nil end
    else
      if btn ~= nil and T.press ~= tapNo then tapNo, tapAt = T.press, mf end
      btn = (tapNo >= 0 and mf - tapAt < 4) and T.dir or nil
    end
  end
  if btn == "a" then c.tgtSeen = true end
  return btn and { [btn] = true } or {}
end

local function runCase(snapRef, c)
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snapRef.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      tick, held = 0, nil
      c.pickIdx, c.srcSaved, c.srcActs, c.srcQueued, c.tgtSeen, c.tgtSlot = 1, 0, {}, 0, false, nil
      c.stores, c.standStores, c.folds, c.staged, c.dmg, c.castIds = {}, {}, {}, {}, {}, {}
      c.srcNums, c.standNums, c.sfmAll, c.standDmg, c.drainLog = {}, {}, {}, {}, {}
      armed = c
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 20 end, 12000, {
      H.call(function()
        guard(c)
        T.observe()
        local aim = MUTANT ~= "default-target" and aimPress(c)
        if aim then held = nil; H.setPad(aim) return end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if ph == 0 and (held or tick % 120 == 0) then
          H.log(string.format("[mimicdbg] %s f%d menu=%02X st=%02X actor=%d press=%s srcDone=%s "
            .. "queued=%d saved=%d pick=%d mimicSent=%s pendS=%d src 32cc=%02X 3aa0=%02X 3aa1=%02X "
            .. "3ab5=%02X SaveForMimic{%s}", c.name, H.frame,
            H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR) & 3, tostring(held),
            tostring(c.srcDone), c.srcQueued, c.srcSaved, c.pickIdx, tostring(c.mimicSent),
            pend(standS), H.readByte(0x32CC + c.src * 2), H.readByte(0x3AA0 + c.src * 2),
            H.readByte(0x3AA1 + c.src * 2), H.readByte(0x3AB5 + c.src * 2), table.concat(c.sfmAll, " ")))
        end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      local charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[mimic] %s: source slot %d cmd $%02X picks %s srcBoost %d (source MP %d -> %s); "
        .. "source actions saved %s; aimed at %s", c.name, c.src, c.cmd, table.concat(c.pickNames, "+"),
        c.srcBoost or 0, c.srcMp0 or -1, tostring(c.srcMpEnd), table.concat(c.srcActs, " "),
        c.tgtSlot and ("monster slot " .. c.tgtSlot .. ", the most HP standing") or "all targets or the default"))
      H.log(string.format("[mimic] %s: stand-in boost %d: pending at confirm %d bank %d; %s",
        c.name, c.boost, c.pendAtConfirm or -1, c.bank0 or -1, c.replace or "mimicreplace NOT reached"))
      H.log(string.format("[mimic] %s: Ot6QueueFold entries %s", c.name, table.concat(c.folds, " ")))
      H.log(string.format("[mimic] %s: cost queue stores %s; by the stand-in (x=%02X) {%s}",
        c.name, table.concat(c.stores, " "), standS * 2, table.concat(c.standStores, ",")))
      H.log(string.format("[mimic] %s: stand-in staged cost $3A4C %s; Ot6BoostDmg %s",
        c.name, table.concat(c.staged, " "), table.concat(c.dmg, " ")))
      H.log(string.format("[mimic] %s: damage numerals source {%s} stand-in {%s}; source targets %s, monster HP at its SaveForMimic {%s}",
        c.name, table.concat(c.srcNums, ","), table.concat(c.standNums, ","),
        tostring(c.srcTargets), tostring(c.monHpAtSave)))
      H.log(string.format("[mimic] %s: FixDrainDmg entries %s", c.name, table.concat(c.drainLog, " ")))
      H.log(string.format("[mimic] %s: RESULT boost %d: stand-in MP %d -> %d (charged %d); "
        .. "pending %d -> %d at ActionEnd entry, bank %d -> %d at ActionEnd entry, %d/%d two frames later",
        c.name, c.boost, c.mp0 or -1, c.mpEnd or -1, charged, c.pendAtConfirm or -1,
        c.pendAtEnd or -1, c.bank0 or -1, c.bankAtEnd or -1, c.pendAfter or -1, c.bankAfter or -1))
    end),
  }
end

-- ---- the run ----------------------------------------------------------------
local snapX, snapT, snapS = nil, nil, nil
local picks = {}
local steps = {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and bright() >= 15 and H.worldHasControl() end,
      6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    local m, names = members(), {}
    for _, c in ipairs(m) do
      names[#names + 1] = string.format("%d[%02X %02X %02X %02X]", c,
        H.readByte(recCmd(c, 0)), H.readByte(recCmd(c, 1)), H.readByte(recCmd(c, 2)), H.readByte(recCmd(c, 3)))
    end
    H.log("[mimic] party (char[commands]) " .. table.concat(names, " ") .. string.format(
      " at world (%d,%d)", H.worldX(), H.worldY()))
    local have = {}
    for _, c in ipairs(m) do have[c] = true end
    assert(have[TERRA] and have[STRAGO], "TERRA and STRAGO are in the party")
    standId = have[RELM] and RELM or (have[LOCKE] and LOCKE or nil)
    assert(standId, "a stand-in (RELM or LOCKE) is in the party")
    -- the declared expedient: two command bytes, see the header
    local old1 = H.readByte(recCmd(standId, 1))
    H.writeByte(recCmd(standId, 1), CMD_MIMIC)
    local xr
    for r = 1, 3 do
      local v = H.readByte(recCmd(TERRA, r))
      if v ~= 0x00 and v ~= CMD_MAGIC and v ~= 0x01 then xr = r break end
    end
    assert(xr, "TERRA has a row that is not Fight, Magic or Item")
    local oldx = H.readByte(recCmd(TERRA, xr))
    H.writeByte(recCmd(TERRA, xr), CMD_XMAGIC)
    H.log(string.format("[mimic] EXPEDIENT: char %d command row 1 $%02X -> $12 (Mimic); "
      .. "TERRA command row %d $%02X -> $17 (X-Magic)", standId, old1, xr, oldx))
    installObservers()
  end),
  (function()
    -- lap between the Continue tile and a tile a few steps off it, each leg
    -- planned on the settled tilemap (M.worldBfs), until an encounter fires;
    -- a draw whose Sneeze counter is armed from the opening is run from and
    -- the lap goes on (see the header)
    local home, away, goal, plan, idx
    local function lapWalk(what)
      return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
        H.call(function()
          if not H.worldHasControl() or not H.worldSettled() then plan = nil; H.setPad({}) return end
          if not H.worldAligned() then return end
          local x, y = H.worldX(), H.worldY()
          if home == nil then
            home = { x, y }
            for _, o in ipairs({ { 0, -4 }, { 0, 4 }, { -4, 0 }, { 4, 0 }, { 0, -3 }, { 0, 3 },
                                 { -3, 0 }, { 3, 0 }, { 2, 2 }, { -2, -2 }, { 2, -2 }, { -2, 2 } }) do
              local p = H.worldBfs(x + o[1], y + o[2])
              if p and #p >= 3 and #p <= 10 then away = { x + o[1], y + o[2] } break end
            end
            assert(away, "a reachable tile a few steps from the Continue tile")
            goal = away
            H.log(string.format("[mimic] encounter lap (%d,%d) <-> (%d,%d)", x, y, away[1], away[2]))
          end
          if plan == nil or idx > #plan then
            if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
            plan, idx = H.worldBfs(goal[1], goal[2]), 1
            if not plan or #plan == 0 then plan = nil; H.setPad({}) return end
          end
          local dir = plan[idx]; idx = idx + 1
          H.setPad({ [dir] = true })
        end),
      }, what)
    end
    local measured, group0, budget = false, nil, nil
    local steps = {}
    for try = 1, BURN + MAXDRAWS do
      steps[#steps + 1] = H.cond(function() return measured end, {}, {
        lapWalk("a random encounter (draw " .. try .. ")"),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900, "battle up (draw " .. try .. ")", 5),
        H.call(function()
          local sp, names = {}, {}
          for _, e in ipairs(H.formationSpecies()) do
            sp[#sp + 1] = e.species
            names[#names + 1] = string.format("$%03X", e.species)
          end
          local why = sneezeArmed(sp)
          local verdict
          if try <= BURN then
            verdict = string.format("used up (BURN %d)", BURN)
          else
            -- the budget belongs to the pool that dealt this encounter
            group0 = group0 or (MUTANT == "other-group" and worldGroup + 1 or worldGroup)
            H.assertEq(worldGroup, group0, string.format("draw %d was dealt by group %s, the pool "
              .. "the budget was decoded from", try, tostring(group0)))
            budget = budget or (MUTANT == "budget-1" and 1 or budgetFor(group0))
            measured = why == nil or MUTANT == "take-any"
            verdict = measured and ("measured" .. (why and " (MUTANT take-any)" or "")) or "run from"
          end
          H.log(string.format("[mimic] draw %d: key %s group %s, formation %s%s -> %s", try,
            tostring(battleKey), tostring(worldGroup), table.concat(names, " "),
            why and ("; armed: " .. why) or "; no Sneeze counter armed", verdict))
          if try > BURN and not measured then
            H.assertEq(try - BURN < budget, true, string.format("a formation with no Sneeze "
              .. "counter armed drawn within %d encounter(s), the most any encounter-counter "
              .. "state needs from group %d", budget, group0))
          end
        end),
        H.cond(function() return measured end, {}, {
          H.fleeBattle(9000),
          H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 1200,
            "back on the world map after running from draw " .. try, 10),
          H.waitFrames(30),
        }),
      })
    end
    return H.repeatN(1, steps)
  end)(),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == TERRA then terraS = s end
      if id == STRAGO then stragoS = s end
      if id == standId then standS = s end
    end
    assert(terraS and stragoS and standS, "the three are in the battle")
    local function dump(s)
      local t = {}
      for cell = 0, 53 do
        local a = listBase(s) + (cell + 1) * 4
        local id = H.readByte(a)
        if id ~= 0xFF then t[#t + 1] = string.format("%02X:%d%s", id, H.readByte(a + 3),
          (H.readByte(a + 1) & 0x80) ~= 0 and "g" or "") end
      end
      return table.concat(t, " ")
    end
    H.log(string.format("[mimic] battle slots: TERRA %d STRAGO %d stand-in %d; commands T[%02X %02X %02X %02X] "
      .. "stand[%02X %02X %02X %02X]", terraS, stragoS, standS,
      H.readByte(CMDTBL + terraS * 12), H.readByte(CMDTBL + terraS * 12 + 3),
      H.readByte(CMDTBL + terraS * 12 + 6), H.readByte(CMDTBL + terraS * 12 + 9),
      H.readByte(CMDTBL + standS * 12), H.readByte(CMDTBL + standS * 12 + 3),
      H.readByte(CMDTBL + standS * 12 + 6), H.readByte(CMDTBL + standS * 12 + 9)))
    H.log("[mimic] TERRA list " .. dump(terraS))
    H.log("[mimic] STRAGO list " .. dump(stragoS))
    H.log("[mimic] stand-in list " .. dump(standS))
    for _, s in ipairs({ terraS, standS, stragoS }) do
      local b = listBase(s)
      H.log(string.format("[mimic] slot %d list head %02X %02X %02X %02X (char %d field esper $%02X)", s,
        H.readByte(b), H.readByte(b + 1), H.readByte(b + 2), H.readByte(b + 3), H.readByte(0x3ED8 + s * 2),
        H.readByte(0x1600 + 37 * H.readByte(0x3ED8 + s * 2) + 0x1E)))
    end
    local ids = H.monsterIds()
    local mon = {}
    for m = 0, 5 do
      mon[#mon + 1] = string.format("%d:%04X hp%d/%d", m, ids[m + 1],
        H.readWord(0x3BF4 + (4 + m) * 2), H.readWord(0x3C1C + (4 + m) * 2))
    end
    H.log("[mimic] monsters " .. table.concat(mon, " "))
    H.log(string.format("[mimic] MP: TERRA %d STRAGO %d stand-in %d", mp(terraS), mp(stragoS), mp(standS)))
    for _, id in ipairs({ 0x00, 0x01, 0x02 }) do
      local cell, cost, fl = spellCell(terraS, id)
      if cell and (fl & 0x80) == 0 then picks.fam = id break end
    end
    local cell, cost, fl = spellCell(terraS, 0x04)
    if cell and (fl & 0x80) == 0 then picks.non = 0x04 end
    for row = 0, 23 do
      local a = listBase(stragoS) + (55 + row) * 4
      local id = H.readByte(a)
      if id ~= 0xFF and loreOffered(id) then picks.lore = id break end
    end
    -- the summon: TERRA's worn esper, whose attack is a spell outside every
    -- tier family (FixPlayerAttack's +$36), so its boost buys Ot6BoostDmg's
    -- multiplier; its numerals are not capped the way a drain's are
    local stone = H.readByte(STONE + terraS * 2)
    if stone ~= 0xFF then picks.esper = stone + 0x36 end
    H.log(string.format("[mimic] picks: family $%02X, non-family $%02X, lore %s, summon %s (TERRA's esper $%02X, "
      .. "esper row cost %d)", picks.fam or 0xFF, picks.non or 0xFF,
      picks.lore and string.format("$%02X", picks.lore) or "none",
      picks.esper and string.format("$%02X", picks.esper) or "none", stone, H.readByte(listBase(terraS) + 3)))
    assert(picks.fam and picks.non, "TERRA knows a family head and Drain")
    assert(picks.lore, "STRAGO has a lore on offer")
    assert(picks.esper, "TERRA wears an esper (the summon cases)")
    assert(cmdRow(standS, CMD_MIMIC), "the stand-in's battle list has Mimic")
    assert(cmdRow(terraS, CMD_XMAGIC), "TERRA's battle list has X-Magic")
  end),
  H.driveUntil(function() return snapX ~= nil and snapT ~= nil and snapS ~= nil end, 40000, {
    H.call(function()
      tick = tick + 1
      if tick % 12 ~= 0 and tick % 12 ~= 6 then return end
      if tick % 12 == 6 then H.setPad({}) return end
      -- X: TERRA's first window, while her HP is still high -- an x-magic's
      -- second spell waits out its own advance delay, and a TERRA worn down
      -- by the Defend rounds below was killed in it (try6-xmagic.log).  The
      -- opening pip is enough for the x-magic cases, which boost 0 or 1.
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and snapX == nil
         and (H.readByte(ACTOR) & 3) == terraS and bank(standS) >= 1 and pend(terraS) == 0 then
        H.setPad({}); snapX = H.requestSaveState()
        H.log(string.format("[mimic] snapshot X f%d: stand-in bank %d MP %d, TERRA MP %d HP %d",
          H.frame, bank(standS), mp(standS), mp(terraS), H.readWord(0x3BF4 + terraS * 2)))
        return
      end
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and bank(standS) >= 3 then
        local a = H.readByte(ACTOR) & 3
        if a == terraS and snapT == nil and pend(terraS) == 0 then
          H.setPad({}); snapT = H.requestSaveState()
          H.log(string.format("[mimic] snapshot T f%d: stand-in bank %d MP %d, TERRA MP %d",
            H.frame, bank(standS), mp(standS), mp(terraS)))
          return
        end
        if a == stragoS and snapS == nil and pend(stragoS) == 0 then
          H.setPad({}); snapS = H.requestSaveState()
          H.log(string.format("[mimic] snapshot S f%d: stand-in bank %d MP %d, STRAGO MP %d",
            H.frame, bank(standS), mp(standS), mp(stragoS)))
          return
        end
      end
      if H.readByte(MENU) == 0 then return end
      local b = defendPress(H.readByte(MSTATE))
      H.setPad(b and { [b] = true } or {})
    end),
  }, "snapshots at TERRA's first window, and TERRA's and STRAGO's with 3 stand-in pips"),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snapX, "snapshot X"); H.checkReq(snapT, "snapshot T"); H.checkReq(snapS, "snapshot S")
  end),
}

local function nm(id) return string.format("$%02X", id) end
local function addCase(snapName, c)
  steps[#steps + 1] = H.call(function()
    c.src = (snapName == "S") and stragoS or terraS
    local p = {}
    for _, k in ipairs(c.pickKeys) do p[#p + 1] = picks[k] end
    c.picks = p
    c.pickNames = {}
    for _, id in ipairs(p) do c.pickNames[#c.pickNames + 1] = nm(id) end
  end)
  for _, s in ipairs(runCase(setmetatable({}, { __index = function(_, k)
    if k == "blob" then return ({ X = snapX, T = snapT, S = snapS })[snapName].blob end
  end }), c)) do steps[#steps + 1] = s end
  steps[#steps + 1] = H.waitFrames(2)
  steps[#steps + 1] = H.call(function()
    c.pendAfter, c.bankAfter = pend(standS), bank(standS)
    H.log(string.format("[mimic] %s: two frames later pending %d bank %d", c.name, c.pendAfter, c.bankAfter))
  end)
end

local CASES = {
  { "T", { name = "fam-b0",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 0 } },
  { "T", { name = "fam-b1",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 1 } },
  { "T", { name = "fam-b2",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 2 } },
  { "T", { name = "fam-b3",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 3 } },
  { "T", { name = "non-b0",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 0 } },
  { "T", { name = "non-b1",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 1 } },
  { "T", { name = "non-b3",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 3 } },
  { "T", { name = "srcfold-b0", cmd = CMD_MAGIC, pickKeys = { "fam" }, srcBoost = 1, boost = 0 } },
  { "X", { name = "x-fam-non-b0", cmd = CMD_XMAGIC, pickKeys = { "fam", "non" }, boost = 0 } },
  { "X", { name = "x-fam-non-b1", cmd = CMD_XMAGIC, pickKeys = { "fam", "non" }, boost = 1 } },
  { "X", { name = "x-non-fam-b0", cmd = CMD_XMAGIC, pickKeys = { "non", "fam" }, boost = 0 } },
  { "X", { name = "x-non-fam-b1", cmd = CMD_XMAGIC, pickKeys = { "non", "fam" }, boost = 1 } },
  { "S", { name = "lore-b0",  cmd = CMD_LORE,   pickKeys = { "lore" },       boost = 0 } },
  { "S", { name = "lore-b1",  cmd = CMD_LORE,   pickKeys = { "lore" },       boost = 1 } },
  { "S", { name = "lore-b3",  cmd = CMD_LORE,   pickKeys = { "lore" },       boost = 3 } },
  { "T", { name = "sum-b0",   cmd = CMD_MAGIC,  pickKeys = { "esper" }, summon = true, boost = 0 } },
  { "T", { name = "sum-b1",   cmd = CMD_MAGIC,  pickKeys = { "esper" }, summon = true, boost = 1 } },
  { "T", { name = "sum-b2",   cmd = CMD_MAGIC,  pickKeys = { "esper" }, summon = true, boost = 2 } },
}
-- The multiplier pairs: the same copy, from the same snapshot, unboosted and
-- boosted.  mp-economy.md: a lore or any spell outside the tier families
-- takes Ot6BoostDmg's x2/x4/x8 on a mimic's copy.  A lore and a summon are
-- read off their damage numerals (neither is capped short of 9999); Drain,
-- whose numeral the drain caps (see FixDrainDmg above), off the damage the
-- calc hands the drain.
local MULT = {
  { base = "non-b0",  vs = { "non-b1", "non-b3" },  how = "drain" },
  { base = "lore-b0", vs = { "lore-b1", "lore-b3" }, how = "numerals" },
  { base = "sum-b0",  vs = { "sum-b1", "sum-b2" },  how = "numerals" },
}
local ONLY = nil                 -- a case-name prefix, or nil for all of them
for _, e in ipairs(CASES) do
  if ONLY == nil or e[2].name:sub(1, #ONLY) == ONLY then addCase(e[1], e[2]) end
end

-- The verdict, once every case has logged (so a red run still shows all of
-- them).  mp-economy.md: Mimic is free at every boost, and the boost buys
-- what it buys on the copied action -- on a tier-family head, the tier.
steps[#steps + 1] = H.call(function()
  -- the family heads and their tiers, off the built ROM's Ot6FoldTbl
  -- (8 rows of [head, +1 tier, +2 tiers])
  local TIERS, tbl = {}, H.sym("Ot6FoldTbl") & 0x3FFFFF
  for r = 0, 7 do
    TIERS[H.readRomByte(tbl + r * 3)] = { H.readRomByte(tbl + r * 3 + 1), H.readRomByte(tbl + r * 3 + 2) }
  end
  local bad = {}
  for _, e in ipairs(CASES) do
    local c = e[2]
    if c.mp0 then
      local charged = c.mp0 - (c.mpEnd or c.mp0)
      local queued = 0
      for _, v in ipairs(c.standStores) do queued = queued + v end
      local verdict = ""
      if charged ~= 0 or queued ~= 0 then
        verdict = string.format("; CHARGED %d MP (queued %s)", charged, table.concat(c.standStores, ","))
      end
      -- a boosted copy of a family head casts the tier the boost buys.  The
      -- cast ids are Ot6BoostDmg's entries, one per damage calc; consecutive
      -- repeats (one per target) fold to one per spell
      local casts = {}
      for _, id in ipairs(c.castIds) do
        if casts[#casts] ~= id then casts[#casts + 1] = id end
      end
      c.casts = casts
      if c.boost > 0 and (c.srcBoost or 0) == 0 and c.cmd ~= CMD_LORE then   -- a lore id is not a spell id
        for i, pick in ipairs(c.picks or {}) do
          if TIERS[pick] then
            local want = TIERS[pick][math.min(c.boost, 2)]
            if casts[i] ~= want then
              verdict = verdict .. string.format("; spell %d cast $%02X, not the tier $%02X",
                i, casts[i] or 0xFF, want)
            end
          end
        end
      end
      if c.boost > 0 and c.bankAfter ~= c.bank0 - c.boost then
        verdict = verdict .. string.format("; bank %d -> %d, not spent %d", c.bank0, c.bankAfter, c.boost)
      end
      if verdict ~= "" then bad[#bad + 1] = c.name else verdict = "; ok" end
      local t = {}
      for _, id in ipairs(c.casts) do t[#t + 1] = string.format("$%02X", id) end
      H.log(string.format("[mimic] VERDICT %s boost %d: charged %d, cast %s%s", c.name, c.boost,
        charged, table.concat(t, "+"), verdict))
    end
  end
  -- The multiplier.  Each copy's damage carries vanilla's own variance,
  -- x(224..255)/256, drawn independently, so the ratio of two copies of one
  -- action at boosts b and 0 is 2^b within [224/255, 255/224] of it; the
  -- band below is that, widened a little for the integer rounding.  x1 (a
  -- boost that bought nothing) and the next multiplier up both fall
  -- outside it at every boost.
  local byName = {}
  for _, e in ipairs(CASES) do byName[e[2].name] = e[2] end
  local LO, HI = 0.86, 1.16
  local function measure(c, how)
    if how == "drain" then return c.drainPre, c.drainPre and "FixDrainDmg $f0" or "no drain calc" end
    local sum, big = 0, 0
    for _, v in ipairs(c.standDmg or {}) do sum = sum + v; if v > big then big = v end end
    if #(c.standDmg or {}) == 0 then return nil, "no damage numeral" end
    if big >= 9999 then return nil, "a numeral at the 9999 cap" end
    return sum, string.format("%d numeral(s) {%s}", #c.standDmg, table.concat(c.standDmg, ","))
  end
  for _, m in ipairs(MULT) do
    local c0 = byName[m.base]
    for _, name in ipairs(m.vs) do
      local c = byName[name]
      if c0.mp0 and c.mp0 then
        local v0, w0 = measure(c0, m.how)
        local v, w = measure(c, m.how)
        local k = 1 << c.boost
        local line
        if v0 == nil or v == nil or v0 == 0 then
          line = string.format("unmeasured (%s: %s; %s: %s)", c0.name, w0, c.name, w)
          bad[#bad + 1] = c.name .. "(unmeasured)"
        elseif #(c0.standDmg or {}) ~= #(c.standDmg or {}) and m.how == "numerals" then
          line = string.format("%s hit %d targets, %s %d", c0.name, #c0.standDmg, c.name, #c.standDmg)
          bad[#bad + 1] = c.name .. "(targets)"
        else
          local r = v / v0
          local ok = r >= k * LO and r <= k * HI
          line = string.format("%d / %d = %.3f, want x%d in [%.2f, %.2f] (%s; %s)%s", v, v0, r, k,
            k * LO, k * HI, w, w0, ok and "; ok" or "; NOT THE MULTIPLIER")
          if not ok then bad[#bad + 1] = c.name .. "(x" .. k .. ")" end
        end
        H.log(string.format("[mimic] MULTIPLIER %s vs %s boost %d: %s", c.name, c0.name, c.boost, line))
      elseif ONLY == nil then
        bad[#bad + 1] = name .. "(not run)"
      end
    end
  end
  assert(#bad == 0, "a boosted mimic was charged, or bought nothing: " .. table.concat(bad, " "))
end)

H.run({ maxFrames = 400000 }, steps)

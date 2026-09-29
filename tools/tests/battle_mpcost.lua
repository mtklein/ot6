-- @suite slow savestate=camp_escaped
-- battle_mpcost.lua -- every ability costs MP.
--
-- The cost table is present in bank F0 with kits.md's numbers, and the test
-- asserts the charge and the insufficient-mp refusal.

-- The mechanism under test: vanilla's GetMPCost prices only magic/lore/
-- summon/x-magic; Blitz/SwdTech/Tools fall through it at 0, so the universal
-- charge at CalcAttackEffect never fires for them.  Ot6AbilityCost (ot6.asm)
-- swaps that 0 for the kit price keyed by the id in $3a7b.
--
-- On camp_escaped, Cyan is real: katana SWDTECH flag $3BA4 bit 1 reads
-- $82.  WHICH techs his SwdTech list offers is not the fixture's to fix:
-- the list is his top three learned techs, weakest first, row r costing
-- r+1 pips (Ot6BushidoWindow / Ot6BushidoTech: base = max(0, ceiling-2)),
-- and the ceiling is his level's.  The fighting run has delivered him at
-- L14 (rows Dispatch/Retort/Slash) and at L15 (Retort/Slash/Quadra Slam,
-- Dispatch slid out), so a fixed "row 0 is Dispatch" measured Retort's 10
-- on the second (build/attempts/wt/mpcost-anydraw).  Each battle's tech is
-- therefore planned from his live window (the learned set $1CF7, the
-- loadout word) and the
-- ROM: the lowest row that is a hit -- not the Retort stance, decoded from
-- Cmd_07 -- and the price the ROM's Ot6AbilityCostTbl gives it, which is
-- checked against kits.md's numbers for all eight.  At the confirm the
-- list must hold that tech on that row, and the action measured must be
-- it.  A row above 0 needs more than the opening pip, and he banks it the
-- way a player does, with real unboosted turns (Item, or Fight once the
-- bag has no Tonic or Potion) before the tech.
-- Both scenarios' MP states are the fight's own:
--   charge  CYAN casts the planned tech off a bank that covers its row
--           against his real pool.  The measurement is
--           taken across the tech's own action, from InitPlayerAction
--           loading his SwdTech into $3a7c to the next action's ExecAction
--           (see installWatches): the pool and the pack's HP as it began
--           and ended, every write to his pool inside it.  Exactly one
--           write, under his own SwdTech (X = his slot, CalcAttackEffect's
--           `sta $3c08,x`), takes the pool it found down by exactly the
--           tech's table price, and the tech lands its hit.  The same
--           Berserk special (below) can take CYAN's window before he
--           gets to choose; that battle is void, it is fought out, and the
--           next encounter measures.  A KO or Petrify, which the next
--           encounter would inherit, SHADOW cures from the bag instead.
--   refusal, a labeled isolation arm in two halves: an
--           input-driven route to a broke kit-caster is out of reach on this
--           pool's economy (a deferring party is ground down before real
--           poverty arrives, and a Dispatch walk never spends the pool down
--           because the trash dies first), so the arm keeps the write MP := 1
--           with the bank the planned row needs built by real item turns.
--           3a, the MENU: CYAN's own command window is driven open FIRST,
--           with a bank that covers the row (so the only reason left to
--           refuse it is the price), the pool is put at 1 there, and then
--           the planned SwdTech row is greyed
--           and its confirm is REFUSED (Ot6KitConfirmMP at the tools-shell
--           confirm, mp-economy.md ruling 2) -- it buzzes, the list stays
--           open, no boost is banked and the turn is still CYAN's.  Both
--           menu sounds are counted twice over: raw, and again only at
--           CYAN's own tools shell ($7BCA up, $7BC2 == $30, ACTOR == CYAN).
--           $95 and $96 are the game's error and confirm sounds everywhere,
--           so only the narrowed counts say anything about this row.
--           3b, the EXECUTION BACKSTOP: with the real pool restored the same
--           tech is committed, and the pool goes broke AT THE LATCH,
--           which is the one hook point the universal insufficient-MP fizzle still
--           exists for (an enemy Rasp between the choice and the swing).  The
--           tech must fizzle, dealing no damage, leaving the 1 MP untouched
--           and never negative.  "No damage" is read across the tech's OWN
--           action, bracketed the way the charge's is (installWatches), not
--           across a stretch of the battle: SHADOW's dog counters with no
--           input at all, and so does a berserked ally.  A ladder over
--           fresh battles: the fighting run's camp_escaped packs carry
--           a Berserk special, and once it lands on CYAN ($3EE5,x bit 4)
--           CheckPlayerAction (battle_main.asm:1470) auto-picks his turns
--           and his window never opens again in that battle, so an
--           attempt that loses his window is void and drains its battle.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967
local TONIC, POTION = 0xE8, 0xE9
local CMD_FIGHT = 0x00
local ITEMLIST = 0x4005                  -- wItemList::Index; row r at +r*6
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
-- names for the log only (BushidoName's order, kits.md)
local TECHNAME = { [0] = "Dispatch", "Retort", "Slash", "Quadra Slam",
  "Empowerer", "Stunner", "Quadra Slice", "Cleave" }

-- Read from the ROM in the first step:
local COST = {}                          -- Ot6AbilityCostTbl
local TECH_ATK0, STANCE                  -- Cmd_07's `sbc #imm` / `cmp #imm`
-- Cmd_07 (battle_main.asm, "command $07: swdtech") by its own bytes:
--   tyx / lda $b6 / pha / sec / sbc #ATK0 / sta $b6 / pla / jsr / jsr /
--   lda $b6 / cmp #STANCE / bne
-- ATK0 is the first tech's attack id and STANCE the one tech index whose
-- cast is the Retort stance (it toggles $3e4c.0 and lands no hit).
local CMD07_SIG = { 0xBB, 0xA5, 0xB6, 0x48, 0x38, 0xE9, false, 0x85, 0xB6,
  0x68, 0x20, false, false, 0x20, false, false, 0xA5, 0xB6, 0xC9, false, 0xD0 }
local function decodeCmd07()
  local hits = {}
  for a = 0x020000, 0x02FFFF - #CMD07_SIG do
    local ok = true
    for i, b in ipairs(CMD07_SIG) do
      if b and H.readRomByte(a + i - 1) ~= b then ok = false break end
    end
    if ok then hits[#hits + 1] = a end
  end
  H.assertEq(#hits, 1, "Cmd_07's byte signature is found exactly once in bank C2")
  TECH_ATK0 = H.readRomByte(hits[1] + 6)
  STANCE = H.readRomByte(hits[1] + 19)
  H.log(string.format("Cmd_07 at $%06X: first tech id $%02X, the stance is tech %d "
    .. "($%02X)", hits[1], TECH_ATK0, STANCE, TECH_ATK0 + STANCE))
end

-- The tech this battle measures, planned from his live window: the lowest
-- row that is a hit.  Replays Ot6BushidoWindow's AUTO math over his ceiling
-- -- and the confirm then checks the list really holds it (listId), so a
-- planning slip fails there by name rather than measuring some other row.
-- The ceiling is taken from the learned set $1CF7 (save data), as
-- popcount - 1, which is what InitSkills stores in $2020 for
-- Ot6BushidoCeil.  Not from $2020 itself: read the moment a refusal battle
-- came up it still held 0 once (ceiling 0, a plan of Dispatch on row 0
-- against a list of Retort/Slash/Quadra Slam -- build/attempts/wt/
-- mpcost-anydraw/lab/mpc/n_new_k8F.log).
local plan                               -- { row, tech, id, need }
local listId                             -- the id on the row he confirmed
local function planWindow()
  local known, n = H.readByte(LEARNED), 0
  for b = 0, 7 do n = n + ((known >> b) & 1) end
  local ceil = math.max(0, n - 1)        -- nothing learned: Dispatch alone
  local base = math.max(0, ceil - 2)
  local rows = {}
  for r = 0, math.min(2, ceil) do rows[#rows + 1] = base + r end
  local p
  for r, t in ipairs(rows) do
    if p == nil and t ~= STANCE then
      p = { row = r - 1, tech = t, id = TECH_ATK0 + t, need = r }
    end
  end
  local names = {}
  for r, t in ipairs(rows) do names[#names + 1] = string.format("%d:%s", r - 1, TECHNAME[t]) end
  return p, table.concat(names, " "), ceil
end
local function planStr()
  return string.format("row %d = %s ($%02X), boost %d, %s", plan.row,
    TECHNAME[plan.tech], plan.id, plan.need,
    COST[plan.id] and (COST[plan.id] .. " MP") or "no table price")
end
-- Plan this battle's tech from its opening state.  The
-- loadout word is the player's field-menu choice, which no draw moves; the
-- plan replays the AUTO window, so that is the precondition, named.
local function planBattle(tag)
  H.assertEq(H.readWord(LOADOUT), 0, "his SwdTech loadout is AUTO ($1E1D = 0): "
    .. "the list is the moving top three the plan replays")
  local p, names, ceil = planWindow()
  H.assertEq(p ~= nil, true,
    "his SwdTech list has a row that is a hit, not only the Retort stance")
  plan, listId = p, nil
  H.log(string.format("[%s] CYAN L%d, $1CF7=%02x, ceiling %d: list {%s}; "
    .. "measuring %s", tag, H.readByte(0x1600 + 2*37 + 8), H.readByte(LEARNED),
    ceil, names, planStr()))
end

local cyan, shadow
local function bp() return H.readByte(0x3E9C + cyan*2) end
local function pend() return H.readByte(0x3E9D + cyan*2) end
local function mp() return H.readWord(0x3C08 + cyan*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function monsterHpSum()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s*2) end
  return t
end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end
local function refindSlots()
  for slot = 0, 3 do
    local id = H.readByte(0x3ED8 + slot*2)
    if id == 0x02 then cyan = slot end
    if id == 0x03 then shadow = slot end
  end
end
-- Can this character's next full gauge open a command window?  The mirror
-- of CheckPlayerAction's status gate (battle_main.asm:1470): STATUS1
-- $3EE4,x {ZOMBIE $02, PETRIFY $40, DEAD $80} and STATUS2 $3EE5,x {BERSERK
-- $10, CONFUSE $20, SLEEP $80} (const.inc STATUS1/STATUS2) each send the
-- turn to CancelAction instead of the menu.  Read, never written.
local ST1_NOMENU, ST2_NOMENU = 0x02 | 0x40 | 0x80, 0x10 | 0x20 | 0x80
local function canMenu(slot)
  return (H.readByte(0x3EE4 + slot*2) & ST1_NOMENU) == 0
     and (H.readByte(0x3EE5 + slot*2) & ST2_NOMENU) == 0
end
local function cyanCanMenu() return canMenu(cyan) end
-- A status that outlives its battle (KO, Petrify) is not waited out by
-- walking to the next encounter: it comes along.  Measured on the original
-- file at a 17-frame idle before the walk (build/lab/mpb/mc_sweep1/
-- orig_idle17.log): CYAN was KO'd in a void attempt's battle and opened
-- refusal attempts 3 and 4 at st1=80, so both were void before they began.
-- SHADOW cures it from the bag the way a player would -- a Fenix Down for
-- KO, a Soft for Petrify (camp_escaped carries 14 and 3) -- and until then
-- CYAN has not lost his window for good.
local FENIX, SOFT = 0xF0, 0xF4
local function cyanCure()
  if cyan == nil or shadow == nil then return nil end
  if hp(shadow) == 0 or not canMenu(shadow) then return nil end
  local s1 = H.readByte(0x3EE4 + cyan*2)
  if (s1 & 0x80) ~= 0 and bagIdxOf({ FENIX }) then return FENIX end
  if (s1 & 0x40) ~= 0 and bagIdxOf({ SOFT }) then return SOFT end
  return nil
end
-- The pack's HP table fills a few frames AFTER battleLoadStarted() and the
-- present mask come up (probe: live at f6670, monster HP at f6671-72), and
-- the status bytes above are the previous battle's until then.  So "CYAN
-- lost his window" is only read off a battle whose pack has HP.
local function cyanLostMenu()
  return monsterHpSum() > 0 and not cyanCanMenu() and cyanCure() == nil
end
local function packStr()
  local parts = {}
  for _, id in ipairs(H.monsterIds()) do
    if id ~= 0xFFFF then parts[#parts + 1] = string.format("%03x", id) end
  end
  return table.concat(parts, ",")
end
local function cyanStatusStr()
  return string.format("st1=%02x st2=%02x", H.readByte(0x3EE4 + cyan*2),
    H.readByte(0x3EE5 + cyan*2))
end

local mf = 0
local cyanMode = "defer"       -- "defer" | "item" | "park" | "tech:<row>"
local quietA = false                     -- suppress the menu-idle A-mash: it
                                         -- can land on a just-opened window
                                         -- and confirm a bystander's Fight
-- A void attempt's battle is fought out: every open window takes Fight.  A
-- deferring party only ends a battle when a berserked CYAN's own swings
-- finish it, and one whose CYAN is down or asleep never would.
local draining = false
local shadowCure = nil                   -- the item SHADOW is taking to CYAN
local tc = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })
local function decide()
  if H.readByte(MENU) == 0 then
    if quietA then return {} end
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if draining then
    if st == ST_CMD then
      local want = cmdRowOf(act, 0x00) or 0
      local cur = H.readByte(CMDROW + act) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
    return { [btn] = true }
  end
  if act == shadow then
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 60 then hurt = true end
    end
    -- the plan is made at the command window and held through the item
    -- and target windows: CYAN's cure first, then the party's HP
    if st == ST_CMD then
      local c = cyanCure()
      if c and c ~= shadowCure then
        H.log(string.format("[shadow f%d] CYAN %s: SHADOW takes item $%02X to him",
          H.frame, cyanStatusStr(), c))
      end
      shadowCure = c
    end
    if st == ST_CMD and not hurt and not shadowCure then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(shadow, CMD_ITEM)
      local cur = H.readByte(CMDROW + shadow) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = shadowCure and bagIdxOf({ shadowCure }) or bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + shadow) + H.readByte(0x894F + shadow)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT and shadowCure then
      -- steer's nil is "the last tap is still settling": press nothing
      local ok, r = pcall(tc.steer, cyan, mf)
      if ok then btn = r
      else
        H.log(string.format("[shadow f%d] the cursor never lit CYAN: %s -- backing out",
          H.frame, tostring(r)))
        btn, shadowCure = "b", nil
      end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif act == cyan then
    if cyanMode == "defer" then
      btn = (st == ST_CMD) and "x" or "b"
    elseif cyanMode == "park" then
      -- sit still in his own command window: the arm below needs CYAN's
      -- turn OPEN before it stages anything, and "b" at $05 would cancel
      -- back out of it
      btn = (st == ST_CMD) and nil or "b"
    elseif cyanMode == "item" then
      -- an unboosted turn pays the pip (Ot6ActionEnd): an Item while the
      -- bag holds a Tonic or Potion (SHADOW's care draws on the same bag),
      -- and a Fight once it does not
      local healer = bagIdxOf({ TONIC, POTION }) ~= nil
      if st == ST_CMD then
        local want = cmdRowOf(cyan, healer and CMD_ITEM or CMD_FIGHT)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        if want == nil then return { b = true } end   -- the last one went
        local cur = H.readByte(0x8947 + cyan) + H.readByte(0x894F + cyan)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    else
      local row = tonumber(cyanMode:match(":(%d)"))
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_SWDTECH)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_TOOLS then
        local cur = H.readByte(KROW + cyan)
        if cur < row then btn = "down"
        elseif cur > row then btn = "up"
        else
          btn = "a"
          listId = H.readByte(ITEMLIST + row * 6)   -- what the row holds
        end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    end
  else
    btn = (st == ST_CMD) and "x" or "b"
  end
  return btn and { [btn] = true } or {}
end
local function frame()
  if H.battleLoadStarted() then
    H.setPad(decide())
    return
  end
  if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
  H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
end
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(frame),
  }, tag)
end

local spells = {}
local buzzes, confirms = 0, 0            -- every $95 / $96 write, anywhere
-- ...and the same two counted only where arm 3a means them: the battle menu
-- open ($7BCA), the tools shell up ($7BC2 == $30) and CYAN the actor.  $95
-- and $96 are the game's error and confirm sounds EVERYWHERE, so a raw
-- count is not evidence about the SwdTech row: it also counts the buzz a
-- "b" press earns in a state the driver does not recognise, and the battle's
-- own opening writes them before any window is up.  See the header.
local kitBuzzes, kitConfirms = 0, 0
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end
local R = {}

-- Arm 2's instrument.  Every write to a party pool, with what the engine
-- had loaded when it made it ($b5/$b6, X) -- the callback runs before the
-- store, so `old` is the pool as the write found it and the high byte's
-- store completes `new` -- and CYAN's SwdTech as the engine runs it,
-- bracketed by the action cell $3a7c: InitPlayerAction loads it with the
-- queued command (X = the actor) as the action starts, and the next action
-- overwrites it as IT starts -- ExecAction's $12 placeholder, or a
-- counterattack's own InitPlayerAction (ExecRetal), which is what closed
-- it with $1F in two of the sweep's runs (battle_main.asm @0100/@0276/
-- @4b7b; the only other writer is an Imp's change to Fight).  So the
-- bracket opens on $3a7c := $07 with X = his offset and closes on the next
-- write: his pool and the pack's HP as it began and as it ended, and the
-- pool writes in between.  Actions serialize, so what moves inside it is
-- the tech's own doing.
local poolWrites = {}
local tech = nil                         -- the bracket, once CYAN's SwdTech starts
local techArmed = false                  -- only the arm's own tech is bracketed
local function writeStr(w)
  return string.format("f%d slot%d %d->%d ($b5=%02X $b6=%02X X=%02X)",
    w.frame, w.slot, w.old, w.new, w.cmd, w.atk, w.x)
end
local function installWatches()
  for slot = 0, 3 do
    local lo = 0x7E3C08 + slot * 2
    emu.addMemoryCallback(function(_, v)
      local old = H.readWord(lo)
      poolWrites[#poolWrites + 1] = { frame = H.frame, slot = slot, old = old,
        new = (old & 0xFF00) | v, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
        x = emu.getState()["cpu.x"] & 0xFFFF }
    end, emu.callbackType.write, lo, lo)
    emu.addMemoryCallback(function(_, v)
      local w = poolWrites[#poolWrites]
      if w and w.slot == slot and w.frame == H.frame and w.hi == nil then
        w.hi = v
        w.new = (v << 8) | (w.new & 0xFF)
      end
    end, emu.callbackType.write, lo + 1, lo + 1)
  end
  emu.addMemoryCallback(function(_, v)
    if tech and not tech.done then
      tech.done, tech.doneFrame, tech.next = true, H.frame, v
      tech.mp1, tech.hp1, tech.w1 = mp(), monsterHpSum(), #poolWrites
      return
    end
    if not techArmed or tech ~= nil or cyan == nil or v ~= CMD_SWDTECH then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) ~= cyan * 2 then return end
    tech = { frame = H.frame, mp0 = mp(), hp0 = monsterHpSum(), w0 = #poolWrites }
  end, emu.callbackType.write, 0x7E3A7C, 0x7E3A7C)
  -- ...and the attack half of the same 16-bit store
  emu.addMemoryCallback(function(_, v)
    if tech and tech.atk == nil and tech.frame == H.frame then tech.atk = v end
  end, emu.callbackType.write, 0x7E3A7D, 0x7E3A7D)
end
local CHARGE_TRIES = 4

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),

  H.call(function()
    decodeCmd07()
    local sig = { 0x5d, 0x04, 0x5e, 0x0a, 0x5f, 0x0d }   -- Pummel/AuraBolt/Suplex
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, b in ipairs(sig) do
        if H.readRomByte(a + i - 1) ~= b then ok = false break end
      end
      if ok then base = a break end
    end
    H.assertEq(base ~= nil, true, "Ot6AbilityCostTbl is found in bank F0")
    local cost, a = COST, base
    while H.readRomByte(a) ~= 0xFF and a < base + 0x200 do
      cost[H.readRomByte(a)] = H.readRomByte(a + 1)
      a = a + 2
    end
    local want = {                        -- kits.md's authored numbers
      [0x5d] = 4,  [0x64] = 99,           -- Blitz:   Pummel, Bum Rush
      -- SwdTech, all eight (any of them can be the row a battle measures):
      -- Dispatch, Retort, Slash, Quadra Slam, Empowerer, Stunner,
      -- Quadra Slice, Cleave
      [0x55] = 4,  [0x56] = 10, [0x57] = 13, [0x58] = 16,
      [0x59] = 18, [0x5a] = 28, [0x5b] = 50, [0x5c] = 99,
      [0xaa] = 4,  [0xa8] = 16, [0xa6] = 18, -- Tools:  AutoCrossbow, Drill, Chain Saw
    }
    for id, c in pairs(want) do
      H.assertEq(cost[id], c, string.format("cost table: id $%02x costs %d", id, c))
    end
    H.log("cost table verified for Blitz + SwdTech + Tools")
  end),

  H.call(function()
    installWatches()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    -- the two menu sounds, for arm 3a's confirm refusal: $95 is magic's error
    -- buzz, $96 the confirm sound the kit window stamps on every A press
    -- BEFORE the affordability gate.  Direct-page stores land in bank $00, so
    -- both the $0000xx and $7e00xx views are counted together.
    -- at CYAN's OWN kit window: the menu open flag up, the tools shell the
    -- state, and CYAN the actor.  This is the lib's own refusalNote() gate
    -- (ot6.lua, M.refusals), narrowed to one character.
    local function atKitWindow()
      return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_TOOLS
         and (H.readByte(ACTOR) & 3) == cyan
    end
    for _, base in ipairs({ 0x000000, 0x7E0000 }) do
      emu.addMemoryCallback(function()
        buzzes = buzzes + 1
        if atKitWindow() then kitBuzzes = kitBuzzes + 1 end
      end, emu.callbackType.write, base + 0x95, base + 0x95)
      emu.addMemoryCallback(function()
        confirms = confirms + 1
        if atKitWindow() then kitConfirms = kitConfirms + 1 end
      end, emu.callbackType.write, base + 0x96, base + 0x96)
    end
  end),

  H.loadState(STATE),
  H.waitFrames(30),
  -- ---------------------------------------------------------- 2. the charge --
  -- One battle per attempt.  An attempt is void when CYAN's own tech
  -- never starts in it: the Berserk special (or any status that takes his
  -- window) landed first, or the battle ended.  The void battle is fought
  -- out and the next encounter measures from its own opening bank.
  (function()
    local steps = {}
    local function voidNow()
      if not H.battleLoadStarted() then return true end
      if cyanLostMenu() then return true end
      -- the pack gone before his turn (Interceptor, a counter): nothing
      -- left for the tech to hit
      return R.packSeen and monsterHpSum() == 0
    end
    for attempt = 1, CHARGE_TRIES do
      local tag = string.format("attempt %d/%d", attempt, CHARGE_TRIES)
      steps[#steps + 1] = H.cond(function() return R.charged end, {}, {
        driveTo(function() return H.battleLoadStarted() end, 25000,
          "charge battle (" .. tag .. ")"),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
        H.waitFrames(90),
        H.call(function()
          refindSlots()
          H.assertEq(cyan ~= nil and shadow ~= nil, true,
            "CYAN and SHADOW really fight this")
          H.assertEq(H.readByte(0x3BA4 + cyan*2) & 0x02, 0x02,
            "his real katana carries the SWDTECH flag (read, not written)")
          planBattle("charge " .. tag)
          H.log(string.format("[charge %s] pack %s; cyan slot %d bp=%d mp=%d %s; "
            .. "monsters %d hp", tag, packStr(), cyan, bp(), mp(), cyanStatusStr(),
            monsterHpSum()))
          if cyanCanMenu() then
            H.assertEq(bp(), 1, "the opening bank is Ot6InitBP's 1 pip")
          end
          R.packSeen = monsterHpSum() > 0
          tech, techArmed, draining = nil, false, false
          cyanMode = "item"
        end),
        -- the bank the planned row needs, from real unboosted turns (none
        -- when the row is 0: the opening pip covers it)
        driveTo(function() return voidNow() or bp() >= plan.need end, 20000,
          "a bank that covers the planned row (" .. tag .. ")"),
        H.call(function()
          if voidNow() then return end
          H.log(string.format("[charge %s] bank %d covers %s; mp=%d", tag, bp(),
            planStr(), mp()))
          tech, techArmed = nil, true
          cyanMode = "tech:" .. plan.row
        end),
        driveTo(function()
          if not techArmed then return true end
          if tech then return tech.done end
          return voidNow()
        end, 20000, "CYAN's planned SwdTech runs, start to end ("
          .. tag .. ")"),
        H.call(function()
          techArmed = false
          cyanMode = "defer"
          if not (tech and tech.done) then
            H.log(string.format("[charge %s] void: live=%s menuable=%s bp=%d "
              .. "tech=%s monsters %d hp %s -- fighting the battle out", tag,
              tostring(H.battleLoadStarted()), tostring(cyanCanMenu()), bp(),
              tech and "in flight" or "never started", monsterHpSum(),
              cyanStatusStr()))
            draining = true
            return
          end
          local inside = {}
          for i = tech.w0 + 1, tech.w1 do
            if poolWrites[i].slot == cyan then inside[#inside + 1] = poolWrites[i] end
          end
          local desc = {}
          for _, w in ipairs(inside) do desc[#desc + 1] = writeStr(w) end
          local dmg = tech.hp0 - tech.hp1
          H.log(string.format("%s ($3a7c=%02X%02X; list row %d held $%02X) "
            .. "f%d..f%d (closed by $%02X): "
            .. "MP %d -> %d, monster damage %d (%d -> %d); his pool's writes inside "
            .. "it: %s", TECHNAME[plan.tech], tech.atk or 0xFF, CMD_SWDTECH,
            plan.row, listId or 0xFF, tech.frame, tech.doneFrame,
            tech.next, tech.mp0, tech.mp1, dmg, tech.hp0, tech.hp1,
            #desc > 0 and table.concat(desc, ", ") or "none"))
          H.assertEq(listId, plan.id, string.format(
            "the row he confirmed (%d) held the planned tech, %s ($%02X)",
            plan.row, TECHNAME[plan.tech], plan.id))
          H.assertEq(tech.atk, plan.id, string.format(
            "the action measured is his %s ($3a7c/$3a7d = $07/$%02X)",
            TECHNAME[plan.tech], plan.id))
          H.assertEq(dmg > 0, true, "the tech landed its hit")
          local price = COST[plan.id]
          H.assertEq(tech.mp0 >= price, true, string.format(
            "ON: his real pool (%d) affords the tech (%d)", tech.mp0, price))
          H.assertEq(#inside, 1, "ON: one write to his pool inside the tech's own action")
          local c = inside[1]
          H.assertEq(c.cmd == CMD_SWDTECH and c.x == cyan * 2, true,
            "ON: ...made under his own SwdTech ($b5 = $07, X = his slot)")
          H.assertEq(c.old - c.new, price, string.format(
            "ON: %s charged exactly its table cost (%d) from the pool the "
            .. "charge found", TECHNAME[plan.tech], price))
          H.assertEq(tech.mp1, tech.mp0 - price, string.format(
            "ON: the pool he ended the tech on is the one he began it on, less %d",
            price))
          H.screenshot("mpcost_on_affordable")
          R.charged = true
        end),
        H.cond(function() return not R.charged end, {
          driveTo(function() return not H.battleLoadStarted() end, 60000,
            "the void attempt's battle is fought out (" .. tag .. ")"),
          H.call(function() draining = false end),
          H.waitFrames(240),
        }, {}),
      })
    end
    steps[#steps + 1] = H.call(function()
      H.assertEq(R.charged, true, string.format("CYAN's planned SwdTech was "
        .. "measured within %d encounters", CHARGE_TRIES))
    end)
    return H.repeatN(1, steps)
  end)(),

  -- ------------------------------------------------------------ 3. refusal --
  -- The labeled isolation arm; see the header.  The bank the planned row
  -- needs is built by real item turns (for row 0 it is Ot6InitBP's opening
  -- 1) and the attempt is a real menu drive; only the poverty itself is
  -- staged.  The bank must cover the row before the press: since #232
  -- Ot6KitConfirmMP refuses a row the caster lacks the PIPS for as well, and
  -- a refusal for pips would say nothing about the price.
  --
  -- An attempt is void, not failed, when CYAN loses his window to a status
  -- (the Berserk special; see the header) or the battle ends under it.  The
  -- latch drive has to see both itself: a berserked CYAN never pends, and a
  -- battle his auto-Fights then win parks on the EXP screen, where
  -- battleLoadStarted() still reads the HP table and the quieted idle A
  -- never dismisses it -- the 30000-frame timeout, not a refusal.  A void
  -- attempt drains its battle (idle A back on) so the next one walks to a
  -- fresh encounter.
  (function()
    local done = false
    local richMp, snap, menuRefused = nil, nil, false
    local atWindow = false             -- was CYAN's own window really open?
    local steps = {}
    for attempt = 1, 4 do
      steps[#steps+1] = H.cond(function() return done end, {}, {
        driveTo(function()
          return H.battleLoadStarted() and H.monstersPresent() > 0
        end, 30000, "refusal battle (attempt " .. attempt .. ")"),
        H.call(function()
          refindSlots(); cyanMode = "item"
          planBattle("refusal arm " .. attempt)
          H.log(string.format(
            "  [refusal arm %d] pack %s; cyan slot %d bp=%d mp=%d %s",
            attempt, packStr(), cyan, bp(), mp(), cyanStatusStr()))
        end),
        driveTo(function()
          return not H.battleLoadStarted() or cyanLostMenu()
            or bp() >= plan.need
        end, 40000, "real item turns bank the planned row's pips (attempt "
          .. attempt .. ")"),
        H.cond(function()
          return H.battleLoadStarted() and not cyanLostMenu()
            and bp() >= plan.need
        end, {
          -- 3a. THE MENU REFUSAL.  Poverty is staged (the isolation write,
          -- waived and labeled) and the attempt then drives the real
          -- SwdTech submenu at a real banked pip.  Since v0.19 the
          -- tools-shell confirm asks Ot6KitConfirmMP whether the caster can
          -- pay the row (btlgfx UpdateMenuState_30 @8809), so the greyed
          -- row buzzes and the window stays open: CYAN keeps the turn and
          -- the pip.  Before v0.19 this same press committed, and the turn
          -- and the pip were gone by the time the fizzle below fired.
          --
          -- The arm's PRECONDITION is CYAN's own command window, OPEN, with
          -- the turn still his.  It is established here, not hoped for.  A
          -- fresh encounter already carries Ot6InitBP's opening 1, so the
          -- item-turn drive above is satisfied at frame 0 of the battle,
          -- before any window exists; staging the poverty there and then
          -- waiting for "a buzz" took the battle's own opening $95 write
          -- (and the "b" the driver presses in a state it does not know)
          -- for the SwdTech row saying no, and read $7BC2 == $00 where the
          -- submenu should have been.  So park in his command window first
          -- and stage the pool there, which is also what makes the list
          -- draw the row already greyed.
          H.call(function() cyanMode = "park"; quietA = true end),
          (function()
            local packSeen = false
            return driveTo(function()
              if not H.battleLoadStarted() then return true end
              local packHp = monsterHpSum()
              if packHp > 0 then packSeen = true end
              if cyanLostMenu() or (packSeen and packHp == 0) then
                return true
              end
              return (H.readByte(ACTOR) & 3) == cyan
                 and H.readByte(MSTATE) == ST_CMD
            end, 30000, "CYAN's own command window opens (attempt "
              .. attempt .. ")")
          end)(),
          H.call(function()
            atWindow = H.battleLoadStarted() and not cyanLostMenu()
              and (H.readByte(ACTOR) & 3) == cyan
              and H.readByte(MSTATE) == ST_CMD
            if not atWindow then
              cyanMode = "defer"
              quietA = false
              H.log(string.format("  [refusal arm %d] 3a void before the "
                .. "window: live=%s menuable=%s state=%02x actor=%d "
                .. "monsters %d hp %s", attempt,
                tostring(H.battleLoadStarted()), tostring(cyanCanMenu()),
                H.readByte(MSTATE), H.readByte(ACTOR) & 3, monsterHpSum(),
                cyanStatusStr()))
              return
            end
            richMp = mp()
            H.writeWord(0x3C08 + cyan*2, 1)
            snap = { bp = bp(), pend = pend(),
                     buzzes = buzzes, confirms = confirms,
                     kitBuzzes = kitBuzzes, kitConfirms = kitConfirms }
            spells = {}
            listId = nil
            cyanMode = "tech:" .. plan.row
            H.log(string.format("  [refusal arm %d] 3a menu: pool %d -> 1, "
              .. "bp=%d pend=%d; pressing %s", attempt, richMp, snap.bp,
              snap.pend, planStr()))
          end),
          -- and the stop is the A press ON THE ROW, inside the submenu
          -- ($96 with $7BC2 == $30 and CYAN the actor), not "a $95 wrote
          -- somewhere".  The buzz is then an ASSERTION below rather than
          -- the thing the drive settles for.
          driveTo(function()
            if not atWindow then return true end
            return not H.battleLoadStarted() or cyanLostMenu()
                or kitConfirms > snap.kitConfirms
          end, 30000, "the broke SwdTech row is confirmed IN the submenu "
            .. "(attempt " .. attempt .. ")"),
          H.waitFrames(90),
          H.call(function()
            menuRefused = false
            if atWindow and H.battleLoadStarted() and not cyanLostMenu()
               and kitConfirms > snap.kitConfirms then
              H.log(string.format("  [refusal arm %d] 3a: state=%02x mp=%d "
                .. "bp=%d pend=%d kitbuzz(+%d) kitconfirm(+%d) "
                .. "buzz(+%d) confirm(+%d) %s", attempt,
                H.readByte(MSTATE), mp(), bp(), pend(),
                kitBuzzes - snap.kitBuzzes, kitConfirms - snap.kitConfirms,
                buzzes - snap.buzzes, confirms - snap.confirms,
                sawSpell(plan.id) and string.format("saw $%02X", plan.id)
                  or "quiet"))
              H.assertEq(listId, plan.id, string.format(
                "ON: the row pressed (%d) held the planned tech, %s ($%02X)",
                plan.row, TECHNAME[plan.tech], plan.id))
              H.assertEq(snap.bp >= plan.need, true, string.format(
                "ON: the bank (%d) covered the row's %d pips, so the only "
                .. "reason left to refuse it is the price", snap.bp, plan.need))
              H.assertEq(kitConfirms > snap.kitConfirms, true,
                "ON: the A press reached the SwdTech list ($96 with $7BC2 "
                .. "== $30 and CYAN the actor, stamped before the gate) -- "
                .. "the refusal is a rejection, not a press that never "
                .. "arrived")
              H.assertEq(kitBuzzes > snap.kitBuzzes, true,
                "ON: and the confirm was REFUSED -- $95 buzzed inside "
                .. "CYAN's own SwdTech list, where Ot6KitConfirmMP prices "
                .. "the row")
              H.assertEq(H.readByte(MSTATE), ST_TOOLS,
                "ON: the SwdTech submenu is still open -- CYAN is still "
                .. "choosing and the turn is still his")
              H.assertEq(pend(), snap.pend,
                "ON: no boost was banked -- Ot6BushidoConfirm was never "
                .. "reached, because the MP gate refused first")
              H.assertEq(bp(), snap.bp,
                "ON: the pip is still in the bank")
              H.assertEq(mp(), 1,
                "ON: the 1 MP is untouched, never negative")
              H.assertEq(sawSpell(plan.id), false,
                "ON: and no tech was ever cast")
              H.screenshot("mpcost_on_menu_refused")
              menuRefused = true
            elseif atWindow then
              H.log(string.format("  [refusal arm %d] 3a void: live=%s "
                .. "menuable=%s state=%02x kitconfirm(+%d) %s", attempt,
                tostring(H.battleLoadStarted()), tostring(cyanCanMenu()),
                H.readByte(MSTATE), kitConfirms - snap.kitConfirms,
                cyanStatusStr()))
            end
            -- the real pool back: 3b's poverty is staged at the LATCH.
            -- Nothing was staged at all on the void-before-the-window path,
            -- so there is nothing to put back there.
            if richMp ~= nil then
              H.writeWord(0x3C08 + cyan*2, richMp)
              richMp = nil
            end
            cyanMode = "defer"
            quietA = false
          end),
          -- 3b. THE EXECUTION BACKSTOP.  The universal insufficient-MP
          -- fizzle at CalcAttackEffect is still real code and still
          -- reachable in play -- an enemy Rasp or Osmose between the choice
          -- and the swing -- so it keeps its own arm.  The poverty is
          -- staged AT THE LATCH, which is exactly that hook point: the
          -- planned tech (a hit, so "no damage" means the fizzle) is chosen
          -- and committed against a pool that could pay it, the
          -- pool then goes broke under it, and the tech must fizzle for no
          -- damage and leave the 1 MP alone.
          H.cond(function()
            return menuRefused and H.battleLoadStarted() and bp() >= plan.need
          end, {
            (function()
              local m0, latched, packSeen = nil, false, false
              local g1 = nil           -- the pack's HP at the latch, for the log
              local rich2 = nil        -- the real pool 3b stages over
              return H.repeatN(1, {
                H.call(function()
                  spells = {}
                  rich2 = mp()
                  listId = nil
                  cyanMode = "tech:" .. plan.row
                  -- quiet the idle A-mash before the latch drive: the
                  -- MENU==0 idle A can confirm a bystander's just-opened
                  -- window.  The damage verdict no longer depends on it
                  -- (it is read inside CYAN's own action, below), but a
                  -- stray bystander Fight still has no business here.
                  -- CYAN's tech still drives (cyanMode routes it whenever
                  -- his menu is open).
                  quietA = true
                end),
                -- the fizzled tech has no grant to signal on, so drive on
                -- the latch (pending banks 1 at the submenu confirm).  The
                -- drive also ends, unlatched, when the latch can no longer
                -- come: CYAN lost his window to a status, or the pack is
                -- dead (the EXP screen, which the quiet A cannot dismiss
                -- and battleLoadStarted() cannot see past).  Dead means
                -- seen alive first: a fresh battle's pack reads 0 HP for
                -- its first frames (see cyanLostMenu).
                driveTo(function()
                  if not H.battleLoadStarted() then return true end
                  local packHp = monsterHpSum()
                  if packHp > 0 then packSeen = true end
                  if cyanLostMenu() or (packSeen and packHp == 0) then
                    return true
                  end
                  if pend() >= 1 and not latched then
                    latched = true
                    -- the hook point: the action is committed, and the pool goes
                    -- broke under it before it resolves (the isolation
                    -- write, waived and labeled).  This is the only way
                    -- left to reach the execution-side gate, now that the
                    -- menu refuses an unaffordable row outright.
                    H.writeWord(0x3C08 + cyan*2, 1)
                    m0 = 1
                    g1 = monsterHpSum()
                    -- and the committed tech is bracketed the way the
                    -- charge's is (installWatches): from InitPlayerAction
                    -- loading his SwdTech into $3a7c to the next action's
                    -- start.  Actions serialize, so the pack's HP across
                    -- that bracket is the refused tech's own doing and
                    -- nobody else's -- not an Interceptor counter, not a
                    -- berserked ally, not a bystander's queued Fight.
                    -- Measured on the regenerated camp_escaped (2026-09-23):
                    -- the pack took 156 in the old 400-frame window from
                    -- SHADOW's dog ("Takedown", no pad input at all).
                    tech, techArmed = nil, true
                  end
                  return latched
                end, 30000, "the broke tech is latched (attempt "
                  .. attempt .. ")"),
                H.call(function() cyanMode = "defer" end),  -- quietA already on
                -- the refused tech runs, start to end, or the attempt
                -- is void: the battle ended or CYAN lost his window under
                -- the queued action
                driveTo(function()
                  if not latched then return true end
                  if tech then return tech.done end
                  return not H.battleLoadStarted() or cyanLostMenu()
                end, 20000, "the broke tech runs, start to end (attempt "
                  .. attempt .. ")"),
                H.call(function() techArmed = false; quietA = false end),
                H.call(function()
                 -- whatever this attempt decided, the staged poverty is put
                 -- back before the next one starts.  3b's write is the
                 -- LAST thing that touches the pool, so leaving it at 1
                 -- handed attempt N+1 a CYAN who can never afford the row
                 -- it has to latch: 3a still refused (the pool was already
                 -- broke), 3b could never commit, and the arm timed out on
                 -- "the broke Dispatch is latched" having never had a
                 -- fighting chance (build/attempts/fix1).  A void attempt
                 -- must leave the fight's own economy behind it.
                 local function measure()
                  if not latched or not (tech and tech.done) then
                    H.log(string.format("  [refusal arm %d] void before the "
                      .. "refused action ran: latched=%s dispatch=%s live=%s "
                      .. "menuable=%s monsters %d hp %s", attempt,
                      tostring(latched), tech and "in flight" or "never started",
                      tostring(H.battleLoadStarted()), tostring(cyanCanMenu()),
                      monsterHpSum(), cyanStatusStr()))
                    return
                  end
                  local left = mp()
                  local dmg = tech.hp0 - tech.hp1
                  H.log(string.format(
                    "refused %s ($3a7c=%02X%02X; list row %d held $%02X) "
                    .. "f%d..f%d (closed by $%02X): "
                    .. "MP %d -> %d (pool %d at its start, %d at its end), "
                    .. "pack damage inside it %d (%d -> %d), $3410 %s; the "
                    .. "pack's HP moved %d since the latch, every action counted",
                    TECHNAME[plan.tech], tech.atk or 0xFF, CMD_SWDTECH,
                    plan.row, listId or 0xFF, tech.frame, tech.doneFrame,
                    tech.next, m0, left, tech.mp0, tech.mp1, dmg, tech.hp0,
                    tech.hp1, sawSpell(plan.id)
                      and string.format("saw $%02X", plan.id) or "quiet",
                    g1 - monsterHpSum()))
                  H.assertEq(listId, plan.id, string.format(
                    "ON: the row committed (%d) held the planned tech, %s "
                    .. "($%02X)", plan.row, TECHNAME[plan.tech], plan.id))
                  H.assertEq(tech.atk, plan.id, string.format(
                    "ON: the action measured is his committed %s "
                    .. "($3a7c/$3a7d = $07/$%02X)", TECHNAME[plan.tech], plan.id))
                  H.assertEq(left, m0,
                    "ON: too little MP is REFUSED -- the 1 MP is untouched, "
                    .. "never negative")
                  H.assertEq(dmg <= 0, true,
                    "ON: and the refused tech dealt no damage (fizzled)")
                  H.screenshot("mpcost_on_refused")
                  done = true
                 end
                 measure()
                 if rich2 ~= nil and mp() ~= rich2 then
                   H.writeWord(0x3C08 + cyan*2, rich2)
                   H.log(string.format("  [refusal arm %d] 3b: the staged "
                     .. "poverty is put back, pool -> %d", attempt, rich2))
                 end
                end),
              })
            end)(),
          }, {}),
        }, {}),
        -- a void attempt leaves whatever battle remains; fight it out
        -- (idle A back on, so an EXP screen is dismissed, and every open
        -- window takes Fight -- a berserked CYAN's own swings alone cannot
        -- end a battle he is down in) so the next attempt starts from a
        -- FRESH encounter
        H.cond(function() return done end, {}, {
          H.call(function()
            H.log(string.format("  [refusal arm %d] void: live=%s "
              .. "menuable=%s bp=%d mp=%d %s -- draining the battle",
              attempt, tostring(H.battleLoadStarted()),
              tostring(cyanCanMenu()), bp(), mp(), cyanStatusStr()))
            cyanMode = "defer"
            quietA = false
            draining = true
          end),
          driveTo(function() return not H.battleLoadStarted() end, 60000,
            "the failed attempt's battle drains away (attempt "
            .. attempt .. ")"),
          H.call(function() draining = false end),
          H.waitFrames(240),
        }),
      })
    end
    steps[#steps+1] = H.call(function()
      H.assertEq(done, true,
        "the refusal completed inside one battle within four encounters")
    end)
    return H.repeatN(1, steps)
  end)(),

  H.logStep(function() return "mpcost complete" end),
})

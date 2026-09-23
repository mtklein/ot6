-- @suite slow savestate=camp_escaped
-- battle_bushidogrey.lua -- MP costs and BP gating: the SwdTech submenu
-- greys what Cyan cannot reach, for two reasons: not enough MP (as in Magic
-- and Blitz), and not enough BP (the boost the row would spend).

--   bp: opens at Ot6InitBP's 1; +1 per unboosted turn (an Item, or a Fight
--       when the bag holds no Tonic or Potion); minus the row's boost per
--       tech (every tech is a boosted action, so its turn regens nothing).
--       It opens at 1 in EVERY battle, so a ledger that spans a battle
--       boundary is not a ledger -- every bank read below is gated on the
--       battle it was built in (passes 2-5 are retry sweeps).
--   MP: his real pool, spent at each tech's Ot6AbilityCostTbl price.
--
-- Which techs his window shows, and so which names are read and which rows
-- must grey, is DERIVED from his live level and learned set and the ROM's
-- tables (BushidoLevelTbl, BushidoName, Cmd_07, Ot6AbilityCostTbl), never
-- from the fixture's: every ROM change regenerates the chain, and the
-- fighting run has delivered him at level 13 and at 14 so far -- at 15 the
-- window slides to Retort/Slash/Quadra Slam and Dispatch is not drawn.

-- Battles are real world encounters off the fixture tile; when the ledger's
-- casts end one (a hit tech kills; Retort is the counter stance and mostly
-- does not), the drive paces to the next.  MP persists across battles, the
-- bank does not.  SHADOW heals with real items while the bag has them, and
-- passes his turn when it does not.
--
-- The fighting run's camp_escaped packs carry a Berserk special.  Once
-- it lands on CYAN ($3EE5,x bit 4), CheckPlayerAction (battle_main.asm:1470,
-- STATUS12 {DEAD, PETRIFY, ZOMBIE, SLEEP, CONFUSE, BERSERK}) auto-picks his
-- turns and his command window never opens again in that battle -- his
-- gauge fills, $3AA0,x never gets bit 7, and he Fights on his own, banking a
-- regen pip per turn.  A drive waiting for his window then waits for the
-- battle to end, and the next battle re-seeds the bank.  So every arm that
-- needs his window bails the attempt as soon as he can no longer open one,
-- drains that battle, and rebuilds the bank in a fresh one.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM, CMD_FIGHT = 0x07, 0x01, 0x00
local KROW = 0x8967                       -- kit list cursor row (read!)
local RESTAGE = 0x57D4                    -- the gate's request byte (read!)
local WHITE, GREY = 0x21, 0x25
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D   -- known SwdTechs; Ot6 loadout word

-- ------------------------------------------------ his ladder, from the ROM --
-- (battle_bushido's derivation, the same tables)
--   BushidoLevelTbl   the level each tech is learned at ($1CF7 follows it)
--   BushidoName       the names the window draws (12 bytes, $fe a space)
--   Cmd_07            `sbc #imm` (the first tech's attack id) and
--                     `lda $b6 / cmp #imm / bne` (the Retort stance's index)
--   Ot6AbilityCostTbl each tech's MP (H.abilityCost)
local LEVELTBL = H.sym("BushidoLevelTbl") & 0x3FFFFF
local NAMETBL, NAME_LEN = H.sym("BushidoName") & 0x3FFFFF, 12
local CMD07 = H.sym("Cmd_07") & 0x3FFFFF
local TECH_ATK0, STANCE
for i = 0, 23 do
  if TECH_ATK0 == nil and H.readRomByte(CMD07 + i) == 0xE9 then   -- sbc #imm
    TECH_ATK0 = H.readRomByte(CMD07 + i + 1)
  end
  if STANCE == nil and H.readRomByte(CMD07 + i) == 0xA5           -- lda $b6
     and H.readRomByte(CMD07 + i + 1) == 0xB6
     and H.readRomByte(CMD07 + i + 2) == 0xC9                     -- cmp #imm
     and H.readRomByte(CMD07 + i + 4) == 0xD0 then                -- bne
    STANCE = H.readRomByte(CMD07 + i + 3)
  end
end
local function techId(t) return TECH_ATK0 + t end
local function techSeq(t)
  local q = {}
  for i = 0, NAME_LEN - 1 do q[#q + 1] = H.readRomByte(NAMETBL + t * NAME_LEN + i) end
  while #q > 0 and q[#q] == 0xFF do table.remove(q) end
  return q
end
local function techName(t)
  local out = ""
  for _, b in ipairs(techSeq(t)) do
    if b >= 0x80 and b <= 0x99 then out = out .. string.char(65 + b - 0x80)
    elseif b >= 0x9A and b <= 0xB3 then out = out .. string.char(97 + b - 0x9A)
    elseif b == 0xFE then out = out .. " "
    else out = out .. "?" end
  end
  return out
end
local function techCost(t) return H.abilityCost(techId(t)) end
local function popcount(v)
  local n = 0
  while v > 0 do n = n + (v & 1); v = v >> 1 end
  return n
end
local function learnedBy(level)
  local n = 0
  for i = 0, 7 do
    if H.readRomByte(LEVELTBL + i) <= level then n = n + 1 end
  end
  return n
end
-- the AUTO window at a ceiling: his top three learned techs, weakest first,
-- row r = boost r+1 (Ot6BushidoTech: base = max(0, ceiling-2))
local function window(ceil)
  local w = {}
  for t = math.max(0, ceil - 2), ceil do w[#w + 1] = t end
  return w
end
local REAL, WINDOW                         -- set at the first battle
local MP_PIN                               -- the MP arm's boundary pool
-- the lever that empties a bank of `b`: the stance row when its boost is
-- exactly b (the counter stance, not a hit, so it seldom ends the fight --
-- at ceiling 2 that is Retort at boost 2, at ceiling 3 Retort at boost 1),
-- else the row whose boost is exactly b, else the deepest row
local function stanceRow()
  for r, t in ipairs(WINDOW) do if t == STANCE then return r - 1 end end
  return nil
end
local function leverRow(b)
  local sr = stanceRow()
  if sr and sr + 1 == b then return sr end
  if b >= 1 and b <= #WINDOW then return b - 1 end
  return #WINDOW - 1
end

local cyan, shadow
local restageTrace = {}          -- OT6_RESTAGE, sampled per frame
local function bp() return H.readByte(0x3E9C + cyan*2) end
local function pend() return H.readByte(0x3E9D + cyan*2) end
local function mp() return H.readWord(0x3C08 + cyan*2) end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
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
local function monsterHpSum()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s*2) end
  return t
end
-- The pack's HP table fills a few frames AFTER battleLoadStarted() and the
-- present mask come up (probe: live at f6670, monster HP at f6671-72), and
-- the status bytes above are the previous battle's until then.  So "CYAN
-- lost his window" is only read off a battle whose pack has HP.
local function cyanLostMenu()
  return monsterHpSum() > 0 and not cyanCanMenu()
end
local function packStr()
  local parts = {}
  for _, id in ipairs(H.monsterIds()) do
    if id ~= 0xFFFF then parts[#parts + 1] = string.format("%03x", id) end
  end
  return table.concat(parts, ",")
end
-- the heal stock the drive's item turns draw on (read): when it is empty
-- the pip-paying turn is a Fight instead, and this says which one ran
local function bagStr()
  local n = { [TONIC] = 0, [POTION] = 0 }
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    if n[id] then n[id] = n[id] + H.readByte(0x2686 + i*5 + 3) end
  end
  return string.format("Tonic %d Potion %d", n[TONIC], n[POTION])
end
local function cyanStatusStr()
  return string.format("st1=%02x st2=%02x", H.readByte(0x3EE4 + cyan*2),
    H.readByte(0x3EE5 + cyan*2))
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function allMatches(seq)
  local vr = emu.memType.snesVideoRam
  local out = {}
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then out[#out+1] = { w = w, attr = emu.read(w * 2 + 1, vr) } end
  end
  return out
end
local function attrOf(seq)
  local m = allMatches(seq)
  local parts = {}
  for _, e in ipairs(m) do
    parts[#parts+1] = string.format("%04x:%02x", e.w, e.attr)
  end
  H.log("  matches: " .. table.concat(parts, " "))
  if #m == 0 then return nil end
  return m[1].attr
end
local function rowAttr(r) return attrOf(techSeq(WINDOW[r + 1])) end
local function rowName(r) return techName(WINDOW[r + 1]) end

-- ------------------------------------------------------------- the drive --
-- cyanMode: "defer" | "item" | "tech:<row>" | "park" (open submenu, hold)
local mf = 0
local cyanMode = "defer"
local shadowThreshold = 60
-- draining: a void attempt's battle is being ended.  Every window that
-- would otherwise pass Fights instead, so the drain is the party ending the
-- fight rather than waiting for a berserked CYAN's swings (measured, shift
-- 31: CYAN went down, nobody else swung, and the party wiped mid-drain).
local draining = false
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })
local shadowItem = nil                   -- what SHADOW opened Item for
-- a KO'd party member (STATUS1 DEAD, read); KO outlasts the battle, and a
-- KO'd CYAN has no window in any later one either
local function downedSlot()
  for s2 = 0, 3 do
    if H.readWord(0x3C1C + s2*2) > 0 and (H.readByte(0x3EE4 + s2*2) & 0x80) ~= 0 then
      return s2
    end
  end
  return nil
end
-- An attempt starts in a live battle with CYAN standing.  While he is KO'd
-- the party fights on (draining) and SHADOW raises him; the attempt then
-- builds its bank in whichever battle he is back up in.
local function liveUp()
  local live = H.battleLoadStarted() and H.monstersPresent() > 0
  local down = cyan ~= nil and (H.readByte(0x3EE4 + cyan*2) & 0x80) ~= 0
  draining = down
  return live and not down
end
local function toCmd(slot, cmd)
  local want = cmdRowOf(slot, cmd)
  local cur = H.readByte(CMDROW + slot) & 3
  if cur == want then return "a" end
  return (cur < want) and "down" or "up"
end
local function passOrFight(slot, st)
  if st == ST_CMD then return draining and toCmd(slot, CMD_FIGHT) or "x" end
  if st == ST_TGT and draining then return "a" end
  return "b"
end
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  tc.observe()
  if act == shadow and st == ST_TGT and shadowItem == FENIX then
    local btn = tc.steer(downedSlot(), mf)
    return btn and { [btn] = true } or {}
  end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act == shadow then                          -- heals below a threshold
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < shadowThreshold then hurt = true end
    end
    -- A KO'd member comes first (a Fenix Down while the bag has one), then
    -- the heal.  Nothing to use hands the window on: B out of an empty Item
    -- list and back into it would hold his window, and CYAN's, forever
    -- (#215, measured in battle_bushido's copy of this drive).
    local canCare = bagIdxOf({ TONIC, POTION }) ~= nil
    local canRaise = downedSlot() ~= nil and bagIdxOf({ FENIX }) ~= nil
    if st == ST_CMD then
      shadowItem = (canRaise and FENIX) or (hurt and canCare and TONIC) or nil
      if shadowItem then btn = toCmd(shadow, CMD_ITEM)
      else btn = passOrFight(shadow, st) end
    elseif st == ST_ITEM then
      local want = (shadowItem == FENIX) and bagIdxOf({ FENIX })
                                         or bagIdxOf({ TONIC, POTION })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + shadow) + H.readByte(0x894F + shadow)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif act == cyan then
    if cyanMode == "defer" then
      btn = passOrFight(cyan, st)
    elseif cyanMode == "item" then
      -- "item" is the unboosted turn that pays a pip (Ot6ActionEnd's +1).
      -- With no Tonic or Potion in the bag (the fixture's bag is whatever
      -- its run bought and SHADOW's care has left), that turn is a Fight.
      local healer = bagIdxOf({ TONIC, POTION }) ~= nil
      if st == ST_CMD then
        local want = cmdRowOf(cyan, healer and CMD_ITEM or CMD_FIGHT)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        local cur = H.readByte(0x8947 + cyan) + H.readByte(0x894F + cyan)
        if want == nil then btn = "b"         -- the last one went: Fight
        elseif cur < want then btn = "down"
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
        if row == nil then btn = nil               -- "park": hold for the reads
        else
          local cur = H.readByte(KROW + cyan)
          if cur < row then btn = "down"
          elseif cur > row then btn = "up"
          else btn = "a" end
        end
      elseif st == ST_TGT then btn = "a"
      else btn = "b" end
    end
  else
    btn = passOrFight(act, st)
  end
  return btn and { [btn] = true } or {}
end

-- the multi-battle frame: in battle, run the menus; out of battle, pace
-- the world area to the next encounter (bp and MP persist across battles)
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
local function parkRead(tag)
  return H.repeatN(1, {
    H.call(function() cyanMode = "defer" end),
    driveTo(function() return pend() == 0 end, 20000,
      tag .. ": the last action's charge has landed"),
    H.waitFrames(90),
    H.call(function() cyanMode = "park:" end),
    driveTo(function()
      return H.battleLoadStarted()
        and (H.readByte(ACTOR) & 3) == cyan and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, tag),
    H.call(function()
      H.setPad({})
      -- The bank AT STAGE TIME, which is the number the row decorator read.
      -- Logged beside the bank at read time below, because those two being
      -- different is the one way a correct decorator draws a wrong row.
      H.log(string.format("  [%s] staged at bp=%d pend=%d actor=%d cyan=%d",
        tag, bp(), pend(), H.readByte(ACTOR) & 3, cyan))
    end),
    H.waitFrames(20),
  })
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  driveTo(function() return H.battleLoadStarted() end, 25000, "first encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      local id = H.readByte(0x3ED8 + slot*2)
      if id == 0x02 then cyan = slot end
      if id == 0x03 then shadow = slot end
    end
    H.assertEq(cyan ~= nil, true, "CYAN is really in this party")
    H.assertEq(shadow ~= nil, true, "SHADOW is really in this party")
    H.assertEq(cmdRowOf(cyan, CMD_SWDTECH) ~= nil, true,
      "his real Bushido command exists")
    H.assertEq(H.readByte(0x3BA4 + cyan*2) & 0x02, 0x02,
      "his real katana carries the SWDTECH flag ($3BA4 bit 1, read not written)")
    H.assertEq(bp(), 1, "the ledger opens at Ot6InitBP's 1")
    -- his window, derived (battle_bushido's reading): the learned set is
    -- the one BushidoLevelTbl gives his live level, InitSkills' ceiling is
    -- popcount($1CF7) - 1, and the AUTO loadout shows the top three
    local level, known = H.readByte(0x1600 + 2*37 + 8), H.readByte(LEARNED)
    local taught = learnedBy(level)
    H.assertEq(known, (1 << taught) - 1, string.format(
      "his learned set $1CF7 is the one BushidoLevelTbl gives level %d: "
      .. "techs 0..%d", level, taught - 1))
    H.assertEq(TECH_ATK0 ~= nil and STANCE ~= nil, true,
      "Cmd_07 still reads `sbc #imm` (the first tech's id) and `cmp #imm / "
      .. "bne` (the Retort stance's index)")
    H.assertEq(H.readWord(LOADOUT), 0,
      "his Bushido loadout is AUTO ($1E1D = 0), the moving top-three window")
    REAL = math.max(0, popcount(known) - 1)
    WINDOW = window(REAL)
    H.assertEq(REAL >= 1, true, string.format(
      "he knows at least two techs (level %d) -- a row the opening bank of "
      .. "1 cannot reach has to exist for the BP grey", level))
    local dearest, names = 0, {}
    for r, t in ipairs(WINDOW) do
      dearest = math.max(dearest, techCost(t))
      names[#names + 1] = string.format("%d:%s(%d MP)", r - 1, techName(t),
        techCost(t))
    end
    H.assertEq(mp() >= dearest, true, string.format(
      "his real pool (%d) covers every row he is shown (the dearest costs "
      .. "%d), so the BP greys below are the BP reason alone", mp(), dearest))
    -- the MP arm's boundary: a pool row 0 pays and row 1 does not, midway
    -- between their Ot6AbilityCostTbl prices (7 for Dispatch 4 / Retort 10)
    local c0, c1 = techCost(WINDOW[1]), techCost(WINDOW[2])
    H.assertEq(c1 > c0, true, string.format(
      "row 1 (%s, %d MP) costs more than row 0 (%s, %d MP), so a pool "
      .. "between them exists for the MP arm", techName(WINDOW[2]), c1,
      techName(WINDOW[1]), c0))
    MP_PIN = c0 + (c1 - c0) // 2
    H.log(string.format("cyan slot %d L%d $1CF7=%02x bp=%d mp=%d; window "
      .. "{%s}; shadow slot %d", cyan, level, known, bp(), mp(),
      table.concat(names, " "), shadow))
  end),

  -- 1. BP grey at the natural bank -----------------------------------------
  parkRead("submenu at the opening bank"),
  H.call(function()
    local attrs, shown = {}, {}
    for r = 0, #WINDOW - 1 do
      attrs[r] = rowAttr(r)
      shown[#shown + 1] = string.format("%s=%s", rowName(r), tostring(attrs[r]))
    end
    H.log(string.format("bp=1 mp=%d -> attr %s", mp(), table.concat(shown, " ")))
    H.assertEq(attrs[0], WHITE, string.format(
      "%s (row 0, boost 1 <= bp 1) is white", rowName(0)))
    for r = 1, #WINDOW - 1 do
      H.assertEq(attrs[r], GREY, string.format(
        "%s (row %d, boost %d > bp 1) is GREY -- the BP reason, with MP "
        .. "abundant", rowName(r), r, r + 1))
    end
    H.assertEq(attrs[1] - attrs[0], 0x04,
      "grey - white == $04, magic's own disabled-bit delta")
    H.screenshot("bushidogrey_bp")
  end),

  -- 2. both clear: one real item turn banks the second pip ------------------
  -- 3. the repaint request over that same window (#77) ----------------------
  --
  -- One arm, one battle: the item turn that banks the pip, the window it is
  -- read through, and the R press over that window.  The window is read at
  -- the bank it was STAGED with (the "staged at" line beside the read), in
  -- the battle the bank was built in; a window that arrives in a later
  -- battle reads Ot6InitBP's fresh 1, which is a different claim, so the
  -- attempt is void rather than a failure.  Pass 3 runs over pass 2's parked
  -- window instead of re-parking: the same battle, no second wait for a
  -- window the Berserk special could take away in between.
  (function()
    local done = false
    local function liveBattle()
      return H.battleLoadStarted() and H.monstersPresent() > 0
    end
    local function parked()
      return (H.readByte(ACTOR) & 3) == cyan and H.readByte(MSTATE) == ST_TOOLS
    end
    local function oneAttempt(n)
      return H.cond(function() return done end, {}, {
        driveTo(function() return liveUp() end, 30000,
          "a live battle for the bp-2 arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          draining = false
          cyanMode = "item"
          H.log(string.format("  [bp-2 arm %d] pack %s; cyan slot %d bp=%d %s; bag %s",
            n, packStr(), cyan, bp(), cyanStatusStr(), bagStr()))
        end),
        driveTo(function()
          return not liveBattle() or cyanLostMenu() or bp() >= 2
        end, 40000, "one real item turn banks bp 2 (attempt " .. n .. ")"),
        H.cond(function()
          return liveBattle() and cyanCanMenu() and bp() >= 2
        end, {
          H.call(function() cyanMode = "defer" end),
          driveTo(function() return pend() == 0 end, 20000,
            "submenu at bp 2: the last action's charge has landed (attempt "
            .. n .. ")"),
          H.waitFrames(90),
          H.call(function() cyanMode = "park:" end),
          driveTo(function()
            return not liveBattle() or cyanLostMenu() or parked()
          end, 30000, "submenu at bp 2 (attempt " .. n .. ")"),
          H.call(function()
            H.setPad({})
            -- The bank AT STAGE TIME, which is the number the row decorator
            -- read.  Logged beside the bank at read time below, because those
            -- two being different is the one way a correct decorator draws a
            -- wrong row.
            H.log(string.format("  [submenu at bp 2] staged at bp=%d pend=%d "
              .. "actor=%d cyan=%d live=%s parked=%s %s",
              bp(), pend(), H.readByte(ACTOR) & 3, cyan,
              tostring(liveBattle()), tostring(parked()), cyanStatusStr()))
          end),
          H.waitFrames(20),
          H.cond(function()
            return liveBattle() and parked() and bp() >= 2 and pend() == 0
          end, {
            H.call(function()
              H.assertEq(rowAttr(1), WHITE, string.format(
                "at bp 2 %s (row 1) is white -- the grey tracks the bank, "
                .. "not unconditional", rowName(1)))
              H.assertEq(rowAttr(0), WHITE, string.format(
                "%s (row 0) stays white", rowName(0)))
            end),

            H.call(function()
              H.assertEq(H.readByte(MSTATE), ST_TOOLS,
                "the kit window is up and browsing")
              H.assertEq(H.readByte(RESTAGE), 0,
                "and no repaint is outstanding before the press")
            end),
            -- Sample the byte frame by frame across the press.  A single
            -- reading after the fact cannot tell the two ROMs apart in the
            -- direction that matters: the fixed gate spends a request in
            -- four frames (one row-pair staged per frame, because the nmi
            -- drains one line transfer per frame), so by the time a press
            -- step returns it is already back to 0, and 0 also means
            -- "nothing was ever raised".  The values in between are the
            -- signal.  The flag protocol is $80 fresh, then 3, 2, 1 as the
            -- cycle stages its lines, then 0 (ot6_hud.asm, over
            -- Ot6RestageGate_ext).
            H.call(function() restageTrace = {} end),
            H.hold({ r = true }),
            H.repeatN(20, {
              H.call(function()
                restageTrace[#restageTrace + 1] = H.readByte(RESTAGE)
              end),
              H.waitFrames(1),
            }),
            H.release(),
            H.waitFrames(60),
            -- ...and then WAIT for the byte to come to rest instead of
            -- reading it once.  "The cycle completed" is a liveness
            -- statement about the gate, and a single sample 60 frames later
            -- also scores whatever ELSE the fight raised in the meantime.
            -- #236 made that a real difference rather than a theoretical
            -- one: an uncontrolled actor now spends its bank, Ot6ActionEnd's
            -- charge arm moves it, and Ot6BankMoved raises a perfectly
            -- healthy fresh request whenever a bank moves under an open kit
            -- window.  Measured landing on the very frame this used to read
            -- (build/attempts/<branch>/lab/bushido/probe_restage, "f2089
            -- restage <- $80 pc $f00cb9" one frame after "f2089 e0 <- 0 pc
            -- $f00d10", the berserked CYAN charging 2 off his bank, with
            -- OT6_UNCTL = $01).  The wait says what was meant and says it
            -- about every request raised in the window; the unfixed gate of
            -- #77 leaves the byte $80 forever, so it still fails here -- on
            -- this wait, with the byte named.
            H.call(function()
              H.vars.restMark, H.vars.restSeen = H.frame, H.readByte(RESTAGE)
            end),
            H.waitUntil(function() return H.readByte(RESTAGE) == 0 end, 240,
              "OT6_RESTAGE to come back to rest (the gate hands it back)", 1),
            H.call(function()
              local seen, sawFresh, sawCycle = {}, false, false
              for _, v in ipairs(restageTrace) do
                seen[#seen + 1] = string.format("%02x", v)
                if v == 0x80 then sawFresh = true end
                if v >= 1 and v <= 3 then sawCycle = true end
              end
              local left = H.readByte(RESTAGE)
              local settle = H.frame - H.vars.restMark
              local aD, aR = rowAttr(0), rowAttr(1)
              H.log(string.format("[#77] restage across the press: %s -> %02x "
                .. "(60 frames on it read $%02x, at rest %d frame(s) later); "
                .. "mstate=%02x menu=%d bp=%d pending=%d %s=%s %s=%s",
                table.concat(seen, " "), left, H.vars.restSeen, settle,
                H.readByte(MSTATE),
                H.readByte(MENU), bp(), pend(), rowName(0), tostring(aD),
                rowName(1), tostring(aR)))
              -- positive control: the press has to have reached Ot6Boost at
              -- all.  Its @refold arm banks the pending boost and raises
              -- OT6_RESTAGE on the same instruction stream (ot6_hud.asm,
              -- Ot6Boost), so a pending of 1 is proof the request was raised
              -- even on a build that then throws it away.
              H.assertEq(pend(), 1, "the R press reached Ot6Boost (pending "
                .. "0 -> 1), which is the same arm that raises the repaint "
                .. "request")
              H.assertEq(sawFresh, true,
                "and the fresh request was visible in the trace")
              -- the discriminator.  1..3 is a staging cycle in progress, and
              -- only a gate that serves menu state $30 ever starts one over
              -- the kit window.
              H.assertEq(sawCycle, true,
                "the gate STARTED a staging cycle over the open kit window "
                .. "(flag 1-3) -- the unfixed gate served the magic list only "
                .. "and left it $80 (#77)")
              -- and it came back promptly.  A fresh request costs one frame
              -- to raise plus the cycle's four staged lines, so anything
              -- that rests inside one cycle is the gate draining normally
              -- and anything longer is a gate that is not draining.
              H.assertEq(settle <= 8, true, string.format(
                "and the cycle completed, handing the byte back within one "
                .. "cycle (%d frame(s) to rest, from $%02x)",
                settle, H.vars.restSeen))
              H.assertEq(H.readByte(MSTATE), ST_TOOLS,
                "the window is still up: a re-stage must not walk it shut")
              H.assertEq(aD, WHITE, string.format(
                "%s is still white after the re-stage", rowName(0)))
              H.assertEq(aR, WHITE, string.format(
                "%s is still white after the re-stage (bp 2)", rowName(1)))
            end),
            H.pressButtons({ "l" }, 6),
            H.waitFrames(60),
            H.call(function()
              H.assertEq(pend(), 0, "L put the pending boost back, so the "
                .. "ledger below is unchanged by this pass")
              done = true
            end),
          }, {}),
        }, {}),
        -- a void attempt (the battle ended under it, or CYAN lost his window
        -- to a status) leaves whatever battle remains; drain it -- a
        -- berserked CYAN's own swings end it, and the idle A taps through the
        -- EXP screen -- so the next attempt builds its bank in a FRESH one
        H.cond(function() return done end, {}, {
          H.call(function()
            H.log(string.format("  [bp-2 arm %d] void: live=%s menuable=%s "
              .. "bp=%d %s -- draining the battle", n,
              tostring(liveBattle()), tostring(cyanCanMenu()), bp(),
              cyanStatusStr()))
            cyanMode = "defer"
            draining = true
          end),
          driveTo(function() return not H.battleLoadStarted() end, 60000,
            "the failed attempt's battle drains away (attempt " .. n .. ")"),
          H.waitFrames(240),
        }),
      })
    end
    return H.repeatN(1, {
      oneAttempt(1), oneAttempt(2), oneAttempt(3), oneAttempt(4), oneAttempt(5),
      H.call(function()
        H.assertEq(done, true,
          "the bp-2 arm read a window that was STAGED on a bank of 2 in the "
          .. "battle that built it, and took the repaint request over it, "
          .. "within five attempts")
      end),
    })
  end)(),

  -- Retort is the lever.  It is the counter stance rather than a hit, so it
  -- does not end the fight the way a Dispatch does, and one cast takes a
  -- bank of exactly its boost straight to 0: the bank is built to the
  -- stance row's boost (2 at ceiling 2, where one item turn banks it; 1 at
  -- ceiling 3, the opening bank) and each of his windows spends the bank it
  -- opened at on leverRow's row until it reads 0.  The read then checks
  -- the bank it was staged with, not the bank it was driven to, and the arm
  -- is a three-attempt sweep (the house limit) because the trash can still
  -- flee or kill the fight out from under an attempt.
  (function()
    local done = false
    local function liveBattle()
      return H.battleLoadStarted() and H.monstersPresent() > 0
    end
    local function oneAttempt(n)
      return H.cond(function() return done end, {}, {
        driveTo(function() return liveUp() end, 30000,
          "a live battle for the 0-bank arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          draining = false
          cyanMode = "item"
          H.log(string.format("  [0-bank arm %d] pack %s; cyan slot %d bp=%d %s; bag %s",
            n, packStr(), cyan, bp(), cyanStatusStr(), bagStr()))
        end),
        driveTo(function()
          return not liveBattle() or cyanLostMenu()
            or bp() >= (stanceRow() or 0) + 1
        end, 40000, "the bank reaches the lever's boost (attempt " .. n .. ")"),
        H.cond(function()
          return liveBattle() and cyanCanMenu()
            and bp() >= (stanceRow() or 0) + 1
        end, {
          H.call(function()
            H.log(string.format("  [0-bank arm %d] bank %d: spending on %s "
              .. "(row %d)", n, bp(), rowName(leverRow(bp())), leverRow(bp())))
          end),
          H.driveUntil(function()
            return not liveBattle() or cyanLostMenu() or bp() == 0
          end, 40000, {
            H.call(function()
              if liveBattle() and bp() <= 5 then
                cyanMode = "tech:" .. leverRow(bp())
              end
              frame()
            end),
          }, "real boosted techs (the lever first) empty the bank (attempt "
            .. n .. ")"),
          H.cond(function()
            return liveBattle() and cyanCanMenu() and bp() == 0
          end, {
            H.call(function() cyanMode = "park:" end),
            driveTo(function()
              return not liveBattle() or cyanLostMenu()
                or ((H.readByte(ACTOR) & 3) == cyan
                    and H.readByte(MSTATE) == ST_TOOLS)
            end, 30000, "the submenu parks on the 0 bank (attempt " .. n .. ")"),
            H.call(function() H.setPad({}) end),
            H.waitFrames(20),
            H.cond(function()
              return liveBattle() and H.readByte(MSTATE) == ST_TOOLS
                and bp() == 0
            end, {
              H.call(function()
                local attrs, shown, drawn = {}, {}, true
                for r = 0, #WINDOW - 1 do
                  attrs[r] = rowAttr(r)
                  if attrs[r] == nil then drawn = false end
                  shown[#shown + 1] = string.format("%s=%s", rowName(r),
                    tostring(attrs[r]))
                end
                H.log(string.format("bp=%d pend=%d banks=%d/%d/%d/%d mp=%d " ..
                  "-> attr %s", bp(), pend(),
                  H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0),
                  H.readByte(0x3EA2), mp(), table.concat(shown, " ")))
                H.assertEq(drawn, true, string.format(
                  "all %d names are still DRAWN at 0 bp -- greyed, not "
                  .. "absent (#38)", #WINDOW))
                for r = 0, #WINDOW - 1 do
                  H.assertEq(attrs[r], GREY, string.format(
                    "%s (boost %d > 0) is grey", rowName(r), r + 1))
                end
                H.screenshot("bushidogrey_zero")
                done = true
              end),
            }, {}),
          }, {}),
        }, {}),
        H.cond(function() return done end, {}, {
          H.call(function()
            H.log(string.format("  [0-bank arm %d] void: live=%s menuable=%s "
              .. "bp=%d %s -- draining the battle", n,
              tostring(liveBattle()), tostring(cyanCanMenu()), bp(),
              cyanStatusStr()))
            cyanMode = "defer"
            draining = true
          end),
          driveTo(function() return not H.battleLoadStarted() end, 60000,
            "the failed attempt's battle drains away (attempt " .. n .. ")"),
          H.waitFrames(240),
        }),
      })
    end
    return H.repeatN(1, {
      oneAttempt(1), oneAttempt(2), oneAttempt(3),
      H.call(function()
        H.assertEq(done, true,
          "the 0-bank arm read a window that was STAGED on a 0 bank within "
          .. "three attempts")
      end),
    })
  end)(),

  H.call(function() shadowThreshold = 40 end),
  (function()
    local done = false
    local function liveBattle()
      return H.battleLoadStarted() and H.monstersPresent() > 0
    end
    local function oneAttempt(n)
      return H.cond(function() return done end, {}, {
        driveTo(function() return liveUp() end, 30000,
          "a live battle for the MP arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          draining = false
          cyanMode = "item"
          H.log(string.format("  [MP arm %d] pack %s; cyan slot %d bp=%d %s; bag %s",
            n, packStr(), cyan, bp(), cyanStatusStr(), bagStr()))
        end),
        driveTo(function()
          return not liveBattle() or cyanLostMenu() or bp() >= 2
        end, 40000, "the bank is rebuilt (attempt " .. n .. ")"),
        H.cond(function()
          return liveBattle() and cyanCanMenu() and bp() >= 2
        end, {
          H.call(function()
            -- the isolation write (waived, labeled): the boundary pool
            H.writeWord(0x3C08 + cyan*2, MP_PIN)
            cyanMode = "park:"
          end),
          driveTo(function()
            return not liveBattle() or cyanLostMenu()
              or ((H.readByte(ACTOR) & 3) == cyan
                  and H.readByte(MSTATE) == ST_TOOLS)
          end, 30000, "the submenu parks, or the battle ends (attempt "
            .. n .. ")"),
          H.call(function() H.setPad({}) end),
          H.waitFrames(20),
          H.cond(function()
            return liveBattle() and H.readByte(MSTATE) == ST_TOOLS
          end, {
            H.call(function()
              local aD, aR = rowAttr(0), rowAttr(1)
              H.log(string.format("bp=%d mp=%d -> attr %s=%s %s=%s",
                bp(), mp(), rowName(0), tostring(aD), rowName(1), tostring(aR)))
              H.assertEq(mp(), MP_PIN, "the isolation pool held for the read")
              H.assertEq(bp() >= 2, true,
                "the bank matches pass 2's (MP is the knob)")
              H.assertEq(aD, WHITE, string.format("%s (%d MP) is white on %d MP",
                rowName(0), techCost(WINDOW[1]), MP_PIN))
              H.assertEq(aR, GREY, string.format(
                "%s (%d MP) is GREY on %d MP with the bank full -- the "
                .. "MP reason, where pass 2 read it WHITE at the same bank",
                rowName(1), techCost(WINDOW[2]), MP_PIN))
              H.screenshot("bushidogrey_mp")
              done = true
            end),
          }, {}),
        }, {}),
        -- a failed attempt leaves whatever battle remains; make sure the
        -- next attempt starts from a FRESH one
        H.cond(function() return done end, {}, {
          H.call(function()
            H.log(string.format("  [MP arm %d] void: live=%s menuable=%s "
              .. "bp=%d %s -- draining the battle", n,
              tostring(liveBattle()), tostring(cyanCanMenu()), bp(),
              cyanStatusStr()))
            cyanMode = "defer"
            draining = true
          end),
          driveTo(function() return not H.battleLoadStarted() end, 60000,
            "the failed attempt's battle drains away (attempt " .. n .. ")"),
          H.waitFrames(240),
        }),
      })
    end
    return H.repeatN(1, {
      oneAttempt(1), oneAttempt(2), oneAttempt(3), oneAttempt(4), oneAttempt(5),
      H.call(function()
        H.assertEq(done, true, "the MP-grey arm completed within five battles")
        H.log("[bushidogrey] all five passes hold (four earned, one labeled)")
      end),
    })
  end)(),
})

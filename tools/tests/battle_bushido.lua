-- @suite slow savestate=camp_escaped
-- battle_bushido.lua -- the Bushido submenu: SwdTech is a tools-shell
-- submenu rather than the vanilla numeral gauge.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_BUSHIDO, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x30, 0x37, 0x38, 0x01
local ST_DEF = 0x27                   -- the Def. window Right opens
-- the frames between a press and the window it opens or closes: $01/$04/
-- $0f/$10 around every open and close, $25/$26 between Right and the Def.
-- window (build/attempts/wt/harness-faults/lab/harness-faults/repro/probe_bushido_s21.log).  A press
-- made there lands on nothing, and a B there cancels the Right.
local function settling(st)
  return st == 0x01 or st == 0x04 or st == 0x0F or st == 0x10
      or st == 0x25 or st == 0x26
end
local CMD_SWDTECH, CMD_ITEM, CMD_FIGHT = 0x07, 0x01, 0x00
local KNOWN, ITEMLIST, KROW = 0x2020, 0x4005, 0x8967
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D  -- known SwdTechs; Ot6 loadout word
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0

-- ------------------------------------------------ his ladder, from the ROM --
-- Everything the arms below expect of his window is derived here, from his
-- live level and learned set and the ROM's own tables, never from the
-- fixture's: every ROM change regenerates the chain, and his level, learned
-- set and pool come out of that wherever the fighting run leaves them.
--   BushidoLevelTbl   the level each tech is learned at (LearnAbilities /
--                     UpdateCyan set $1CF7 from it)
--   BushidoName       the names the SwdTech window draws (12 bytes each,
--                     $fe a space, $ff padding)
--   Cmd_07            `sbc #$55` (the first tech's attack id) and
--                     `lda $b6 / cmp #imm / bne` (the one tech whose cast is
--                     the Retort stance: power zeroed, no hit)
--   Ot6AbilityCostTbl each tech's MP (H.abilityCost)
--   Ot6SkillClassTbl  each tech's class byte (the chip arm's staged weakness)
local LEVELTBL = H.sym("BushidoLevelTbl") & 0x3FFFFF
local NAMETBL, NAME_LEN = H.sym("BushidoName") & 0x3FFFFF, 12
local CMD07 = H.sym("Cmd_07") & 0x3FFFFF
local CLASSTBL = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
local TECH_ATK0, STANCE                  -- read from Cmd_07 below
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
local function techSeq(t)                -- the glyph run the window draws
  local s = {}
  for i = 0, NAME_LEN - 1 do s[#s + 1] = H.readRomByte(NAMETBL + t * NAME_LEN + i) end
  while #s > 0 and s[#s] == 0xFF do table.remove(s) end
  return s
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
local function techClass(t)
  for x = 0, 62, 2 do
    local key = H.readRomByte(CLASSTBL + x)
    if key == 0xFF then return 0 end
    if key == techId(t) then return H.readRomByte(CLASSTBL + x + 1) end
  end
  return 0
end
local function popcount(v)
  local n = 0
  while v > 0 do n = n + (v & 1); v = v >> 1 end
  return n
end
-- how many techs BushidoLevelTbl has taught by `level`
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

local cyan, shadow
local function bp() return H.readByte(0x3E9C + cyan*2) end
local function pend() return H.readByte(0x3E9D + cyan*2) end
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

-- the shared drive (battle_bushidogrey's)
local mf = 0
local cyanMode = "defer"                 -- "defer"|"item"|"tech:<row>"|"park:"
local quietA = false
local sawNumeral = false
-- A KO'd party member (STATUS1 DEAD, read), and SHADOW's Fenix Down for
-- him: battle_bushidogrey's shape.  A KO'd CYAN gets no window in this
-- battle or any later one, so every arm waiting for his window waited out
-- its whole budget -- measured on camp_escaped with arm 5's confirm made
-- 20 frames later than the fixture's first run made it: a Berserk, then
-- SABIN and CYAN at 0 HP with SHADOW alone on 177 and "timeout after 30000
-- frames driving toward [zero] his next SwdTech window"
-- (build/lab/live-state-suites/suite_battle_bushido.run1.log).  Which
-- member the draw fells is not the property under test; raising him the
-- way a person would is how the arms get his window back.
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })
local shadowItem = nil                   -- what SHADOW opened Item for
local function downedSlot()
  for s2 = 0, 3 do
    if H.readWord(0x3C1C + s2*2) > 0 and (H.readByte(0x3EE4 + s2*2) & 0x80) ~= 0 then
      return s2
    end
  end
  return nil
end
local function decide()
  if H.readByte(MSTATE) == ST_BUSHIDO then sawNumeral = true end
  if H.readByte(MENU) == 0 then
    if quietA then return {} end
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if settling(st) then return {} end
  tc.observe()
  if act == shadow and st == ST_TGT and shadowItem == FENIX then
    local b = tc.steer(downedSlot(), mf)
    return b and { [b] = true } or {}
  end
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act == shadow then
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 60 then hurt = true end
    end
    -- nothing to heal with spends the turn on a Defend (measured: with the
    -- bag empty of both, B out of the list and back into Item held his
    -- window forever, and CYAN's never came).  A Defend, not X: X passes
    -- the turn to the back of the menu queue (btlgfx window_close,
    -- w7e4001,x = 4) and the battle clock does not run while a command
    -- window is up, so with SABIN's and SHADOW's gauges both full their
    -- windows cycled X for X and CYAN's queued tech never ran -- measured
    -- at seed shift 21 (build/attempts/wt/harness-faults/lab/harness-faults/repro/probe_bushido_s21.log:
    -- `q=01/00/ff pend=1 atb=91/2f/5f` on every frame from f1100 to
    -- f1432, the actor alternating 1/0), the "timeout after 900 frames
    -- driving toward the boosted tech resolves" at shifts 21 and 35.
    local canCare = bagIdxOf({ TONIC, POTION }) ~= nil
    local canRaise = downedSlot() ~= nil and bagIdxOf({ FENIX }) ~= nil
    if st == ST_CMD then
      shadowItem = (canRaise and FENIX) or (hurt and canCare and TONIC) or nil
    end
    if st == ST_CMD and shadowItem == nil then btn = "right"
    elseif st == ST_DEF then btn = "a"
    elseif st == ST_CMD then
      local want = cmdRowOf(shadow, CMD_ITEM)
      local cur = H.readByte(CMDROW + shadow) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
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
      btn = (st == ST_CMD) and "x" or "b"
    elseif cyanMode == "item" then
      -- any unboosted turn pays the pip; the camp_escaped bag can hold no
      -- Tonic or Potion by now (measured: it ships 1 Potion, SHADOW's care
      -- draws on the same bag), and then he takes the turn as a Fight
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
        if row == nil then btn = nil               -- "park:"
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
    -- the bench spends its turn on a real Defend (see SHADOW's arm above)
    if st == ST_CMD then btn = "right"
    elseif st == ST_DEF then btn = "a"
    else btn = "b" end
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
-- Waiting for a banked tech to resolve is a DRIVEN wait, not a still one.
-- Whatever window happens to be up when the previous drive stops is then
-- nobody's to close, and an open command window holds the ATB still, so
-- the queued tech can never run.  Measured on this fixture
-- (build/attempts/bushido-chip-handover/lab/bushido_probe1.log): the chip
-- arm's drive stopped on the frame SHADOW confirmed Item, his list opened
-- one frame later, and for the whole 900-frame budget nothing moved --
-- `menu=01 mstate=0a actor=1 pend=1 bp=1 atb(cyan)=009f atb(shadow)=00ff
-- atb(m0)=31ff`, the same three gauges every sample.  Which window is up
-- at the handover is the fixture's timing, not the property under test.
-- Driving through it is safe for what the arms then measure: CYAN is
-- parked in "defer" and quietA holds the A mash off, so the drive plans
-- no attack of its own -- SHADOW's care is the only action it can start,
-- and a Potion chips no shield and moves no monster HP.
local function resolveTo(pred, tag)
  return driveTo(pred, 900, tag)
end
local function park(tag)
  return H.repeatN(1, {
    H.call(function() cyanMode = "park:" end),
    driveTo(function()
      return H.battleLoadStarted()
        and (H.readByte(ACTOR) & 3) == cyan and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, tag),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
  })
end
-- Confirm `row` in CYAN's parked SwdTech window, without the tech
-- steering, and read the ROM's answer into H.vars.confirm: "banked" (his
-- pending bank moved), "refused" (the list buzzed, H.refusals) or "lost"
-- (the battle took the window before it answered).
--
-- This used to walk the cursor and edge one A, and whether that edge was
-- ever seen was the battle's timing, not the test's (#229).  Measured at
-- seed shift 2 (build/attempts/wt/harness-faults/lab/harness-faults/repro/probe_bushido_s2.log):
-- Kitty had berserked him under the open window (`st=00/10/..` from
-- f690), and on the frame the edge went down --
--   [probe f748] menu=01 act=2 st=30 krow=0 bp=1 pend=0 bcb=01 q=ff
-- -- the battle had dropped him from the menu queue (w7e4001+cyan = $ff)
-- and raised the force-close (btlgfx_main.asm @0ca4), so the window slid
-- away under the press ($30 -> $2f -> $01 -> $05 -> $0f -> $01 over the
-- next twelve frames) with nothing banked and nothing buzzed:
--   assertEq failed: row 0 banked boost 1 ($3e9d = 1): got 0, want 1
-- So the edge is made only while the window is his, repeated until the
-- ROM answers, and a window that goes unanswered is reported as "lost"
-- rather than read as an answer.  `row` is a number, or a function read
-- when the walk runs.  opts.repark parks his next window and asks again
-- until answered, for the arms whose premise (the bank the window opened
-- at) holds across windows; an arm whose premise is read at each window
-- asks once and answers "lost" itself.
local function confirmRow(row, tag, opts)
  opts = opts or {}
  local function r() return type(row) == "function" and row() or row end
  local n0, p0 = 0, 0
  local function windowUp()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
      and (H.readByte(ACTOR) & 3) == cyan and H.readByte(MSTATE) == ST_TOOLS
  end
  local function answered() return pend() ~= p0 or H.refusals.n > n0 end
  local ph = 0
  local ask = H.repeatN(1, {
    H.call(function() n0, p0 = H.refusals.n, pend() end),
    H.driveUntil(function()
      return not windowUp() or H.readByte(KROW + cyan) == r()
    end, 600, {
      H.call(function()
        ph = (ph + 1) % 8
        if ph >= 4 or not windowUp() then H.setPad({}); return end
        local cur = H.readByte(KROW + cyan)
        H.setPad({ [cur < r() and "down" or "up"] = true })
      end),
      H.waitFrames(1),
    }, tag .. ": cursor walked to the row"),
    H.call(function() H.setPad({}) end),
    H.waitFrames(8),
    H.driveUntil(function() return answered() or not windowUp() end, 600, {
      H.cond(windowUp, { H.pressButtons({ "a" }, 4) }, {}),
      H.waitFrames(12),
    }, tag .. ": the confirm answered"),
    H.waitFrames(8),
    H.call(function()
      if pend() ~= p0 then H.vars.confirm = "banked"
      elseif H.refusals.n > n0 then H.vars.confirm = "refused"
      else
        H.vars.confirm = "lost"
        H.log(string.format("%s: the window went at f%d before the confirm "
          .. "was answered", tag, H.frame))
      end
    end),
  })
  if not opts.repark then return ask end
  return H.repeatN(1, {
    H.call(function() H.vars.confirm = nil end),
    H.driveUntil(function()
      return H.vars.confirm == "banked" or H.vars.confirm == "refused"
    end, 40000, {
      H.cond(function() return not windowUp() end,
        { park(tag .. ": his SwdTech window, again") }, {}),
      ask,
    }, tag .. ": a window that answered the confirm"),
  })
end

-- Confirm `rowf()` at a window whose bank covers `needf()`, building the
-- bank with real unboosted turns first ("item": an Item, or a Fight once the
-- bag has no Tonic or Potion) -- Ot6ActionEnd's +1 per unboosted turn, in
-- the battle the confirm is then made in.  A bank opens at Ot6InitBP's 1 in
-- every battle, so the premise is read at each window: one that opens
-- short (the battle turned over under the banking) is not asked, it is
-- banked again.  Stops on an answer: "banked" or "refused".
local function confirmAtBank(rowf, needf, tag)
  local function windowUp()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
      and (H.readByte(ACTOR) & 3) == cyan and H.readByte(MSTATE) == ST_TOOLS
  end
  local function covered()
    return H.battleLoadStarted() and H.monstersPresent() > 0
      and bp() >= needf() and bp() <= 5 and pend() == 0
  end
  return H.repeatN(1, {
    H.call(function() H.vars.confirm = nil end),
    H.driveUntil(function()
      return H.vars.confirm == "banked" or H.vars.confirm == "refused"
    end, 60000, {
      -- a window already up on a covering bank is asked as it stands (the
      -- confirmRow repark shape: no re-park, no settle in front of it)
      H.cond(function() return not (windowUp() and covered()) end, {
        H.call(function() cyanMode = "item" end),
        driveTo(covered, 40000, tag .. ": a bank that covers the row"),
        park(tag .. ": his SwdTech window"),
      }, {}),
      H.cond(covered, { confirmRow(rowf, tag) }, {}),
    }, tag .. ": a window whose bank covers the row answered the confirm"),
  })
end

-- CYAN's actions as the engine starts them: one record per ExecCmd
-- (battle_main.asm, the dispatch of the action at the top of the queue)
-- with the attacker, his command and attack id.  A $3410 write is not
-- that: "last spell used" is stored when the action is staged, and the
-- actions queued ahead of his run first.  Measured
-- (build/attempts/wt/harness-faults/lab/harness-faults/repro/probe_bushido_s28c.log,
-- probe_bushido_s31c.log): $3410 read $55 at f3466 / f731; SABIN's
-- Fight and SHADOW's Defend (shift 28), two monster turns and
-- Interceptor's counter (shift 31) ran first; his ExecCmd came at
-- f3928 / f1332 and Ot6ActionEnd 440 / 415 frames after it -- 903 and
-- 1017 frames after the write, past the 900-frame resolve budget that
-- used to be counted from the write ("timeout after 900 frames driving
-- toward the boosted tech resolves", shifts 12, 21, 31, 35, 36 across the
-- sweeps).  The resolve wait now starts at his ExecCmd, the action's own
-- start.
local started = {}
local execSeq = 0                        -- ExecCmd calls seen, ever
local function techStarted(id)
  for _, s in ipairs(started) do
    if s.x == cyan * 2 and s.cmd == CMD_SWDTECH and s.atk == id then
      return true
    end
  end
  return false
end
-- the ExecCmd sequence number of his SwdTech `id`, the action the damage
-- and the multiplier below are attributed to
local function techSeqNo(id)
  for _, s in ipairs(started) do
    if s.x == cyan * 2 and s.cmd == CMD_SWDTECH and s.atk == id then
      return s.seq
    end
  end
  return nil
end

-- The tech's OWN damage, attributed at the source (#244).  Reading the
-- monster HP sum across the tech's resolve counts whatever else lands in
-- that span -- SHADOW's Interceptor counters, a berserked swing -- and the
-- cap the old reading was held to moved with every regeneration of the
-- chain.  So every HP hit is recorded where the engine applies it:
-- ApplyDmg (battle_main.asm, called per target by the apply-and-display
-- pass at the end of every attack) runs with X = the attacker and Y = the
-- target, $33D0,y the damage and $11A2 bit 7 set for MP damage.  Each hit
-- carries the ExecCmd sequence number of the action it landed in, so the
-- tech's damage is exactly the hits CYAN dealt monsters inside his own
-- SwdTech action (a counter is a separate ExecCmd, with $B1 bit 0 raised).
local hits = {}
-- the tech's own damage, and every other hit on a monster recorded since
-- hits[from] (the confirm), for the log beside the HP-sum reading
local function techDamage(seqNo, from)
  local own, other = 0, 0
  for i, h in ipairs(hits) do
    if h.seq == seqNo and h.x == cyan * 2 and (h.b1 & 1) == 0 then
      own = own + h.d
    elseif i > (from or 0) then
      other = other + h.d
    end
  end
  return own, other
end
-- ...and the multiplier's own answer.  Ot6BoostDmg (ot6_boostdmg.asm) is
-- where a boost would become x2/x4/x8 damage; its only store to $11B0 is
-- the multiply.  Every call on CYAN's behalf is recorded (the command, his
-- pending boost, the damage it was handed), and every store to $11B0 made
-- from inside the proc -- so "the boost bought the tech, not a multiplier"
-- is read off the multiplier, the same at any level or Vigor, instead of
-- off a damage figure that grows with both.
local BOOSTDMG = H.sym("Ot6BoostDmg")
local BOOSTDMG_END = H.sym("Ot6FoldCmdTbl")      -- the table after the proc
local bdCalls, bdStores = {}, {}
local ledger = {}
local function flushLedger(tag)
  for _, e in ipairs(ledger) do
    H.log(string.format("[%s] ledger f=%d bank %d -> %d (status2 $%02x%s)",
      tag, e.f, e.from, e.to, e.st2,
      (e.st2 & 0x10) ~= 0 and ": Berserk" or ""))
  end
  ledger = {}
end
local function checkWindow(ceil, tag)
  local techs = window(ceil)
  for r = 0, 3 do
    local id = H.readByte(ITEMLIST + r * 6)
    local right = H.readByte(ITEMLIST + r * 6 + 3)
    H.assertEq(right, 0xFF, string.format("%s row %d: right column empty", tag, r))
    if techs[r + 1] then
      local t = techs[r + 1]
      H.assertEq(id, techId(t), string.format("%s row %d (boost %d): %s id $%02x",
        tag, r, r + 1, techName(t), techId(t)))
      H.assertEq(H.readByte(ITEMLIST + r * 6 + 1), techCost(t), string.format(
        "%s row %d: %s costs %d (Ot6AbilityCostTbl)", tag, r, techName(t),
        techCost(t)))
    else
      H.assertEq(id, 0xFF, string.format(
        "%s row %d: no row (#38: three tiers, fewer when the learned set is "
        .. "short)", tag, r))
    end
  end
  H.assertEq(H.readByte(ITEMLIST + 3 * 6), 0xFF,
    tag .. ": the 4th window row is always empty (the 0x tier is gone)")
end

-- his real window and the rows the arms use, derived at the first battle
local REAL                               -- his real ceiling, from $1CF7
local WINDOW                             -- techs on rows 0.. at REAL
local DMG_ROW, DMG_T                     -- the lowest row that is a hit
local R = {}

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
    H.assertEq(cyan ~= nil and shadow ~= nil, true,
      "CYAN and SHADOW really fight this")
    H.assertEq(H.readByte(0x3BA4 + cyan*2) & 0x02, 0x02,
      "his real katana carries the SWDTECH flag (read, not written)")
    -- His ceiling is DERIVED, not assumed: the learned set $1CF7 is what
    -- BushidoLevelTbl gives his live level (UpdateCyan at the join,
    -- LearnAbilities at each level after), and InitSkills stores
    -- popcount($1CF7) - 1 into $2020's low byte (the high byte carries
    -- CountBits' garbage, the #4 regression's true shape).  The fighting
    -- run has delivered him at 13 and at 14 so far, and a level of 15
    -- slides the window to Retort/Slash/Quadra Slam; every arm below
    -- reads its rows from REAL and the ROM's tables.
    local level, known = H.readByte(0x1600 + 2*37 + 8), H.readByte(LEARNED)
    local taught = learnedBy(level)
    H.assertEq(known, (1 << taught) - 1, string.format(
      "his learned set $1CF7 is the one BushidoLevelTbl gives level %d: "
      .. "techs 0..%d", level, taught - 1))
    H.assertEq(TECH_ATK0 ~= nil and STANCE ~= nil, true,
      "Cmd_07 still reads `sbc #imm` (the first tech's id) and `cmp #imm / "
      .. "bne` (the Retort stance's index)")
    R.ceiling = H.readWord(KNOWN)
    H.assertEq(R.ceiling & 0xFF, (popcount(known) - 1) & 0xFF, string.format(
      "his REAL ceiling is %d: InitSkills' $2020 = popcount($1CF7) - 1",
      popcount(known) - 1))
    REAL = math.max(0, popcount(known) - 1)
    WINDOW = window(REAL)
    H.assertEq(H.readWord(LOADOUT), 0,
      "his Bushido loadout is AUTO ($1E1D = 0), so the window is the "
      .. "moving top-three the arms below derive")
    H.assertEq(REAL >= 1, true, string.format(
      "he knows at least two techs (level %d) -- a row beyond the opening "
      .. "bank of 1 has to exist for the refusal arm", level))
    for r, t in ipairs(WINDOW) do
      if DMG_ROW == nil and t ~= STANCE then DMG_ROW, DMG_T = r - 1, t end
    end
    H.assertEq(DMG_ROW ~= nil, true,
      "his window has a row that is a hit, not only the Retort stance")
    local names = {}
    for r, t in ipairs(WINDOW) do
      names[#names + 1] = string.format("%d:%s", r, techName(t))
    end
    H.log(string.format("CYAN L%d, $1CF7=%02x: ceiling %d, window {%s}; "
      .. "the stance is %s; the hit arms use row %d (%s, boost %d)", level,
      known, REAL, table.concat(names, " "), techName(STANCE), DMG_ROW,
      techName(DMG_T), DMG_ROW + 1))
    H.assertEq(bp(), 1, "the natural opening bank (Ot6InitBP)")
    emu.addMemoryCallback(function()
      pcall(function()
        execSeq = execSeq + 1
        started[#started + 1] = {
          x = emu.getState()["cpu.x"] & 0xFF, seq = execSeq,
          cmd = H.readByte(0xB5), atk = H.readByte(0x3A7D) }
      end)
    end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"))
    -- every HP hit on a monster, where the engine applies it (read only)
    emu.addMemoryCallback(function()
      pcall(function()
        local st = emu.getState()
        local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
        if y < 8 or (H.readByte(0x11A2) & 0x80) ~= 0 then return end
        local d = H.readWord(0x33D0 + y)
        if d >= 0x4000 then return end            -- $FFFF: no damage
        hits[#hits + 1] = { seq = execSeq, x = x, y = y, d = d,
                            b1 = H.readByte(0xB1) }
      end)
    end, emu.callbackType.exec, H.sym("ApplyDmg"))
    -- Ot6BoostDmg, on his behalf: its entry, and any store it makes to
    -- $11B0 (a data-bank write; both views of it are watched)
    emu.addMemoryCallback(function()
      pcall(function()
        local x = emu.getState()["cpu.x"] & 0xFF
        if x ~= cyan * 2 then return end
        bdCalls[#bdCalls + 1] = { seq = execSeq, cmd = H.readByte(0xB5),
          pend = H.readByte(0x3E9D + x), dmg = H.readWord(0x11B0) }
      end)
    end, emu.callbackType.exec, BOOSTDMG)
    for _, base in ipairs({ 0x000000, 0x7E0000 }) do
      emu.addMemoryCallback(function(_, v)
        pcall(function()
          local st = emu.getState()
          local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
          if pc >= BOOSTDMG and pc < BOOSTDMG_END then
            bdStores[#bdStores + 1] = { seq = execSeq, v = v, pc = pc }
          end
        end)
      end, emu.callbackType.write, base + 0x11B0, base + 0x11B1)
    end
    -- the bank's ledger, observed (a write watch; nothing is written): each
    -- change with the frame and his status-2 byte, so a regen that lands
    -- without a window (Berserk's auto-Fight) is on the record
    local last = bp()
    emu.addMemoryCallback(function(_, v)
      if v ~= last then
        ledger[#ledger + 1] = { f = H.frame, from = last, to = v,
          st2 = H.readByte(0x3EE5 + cyan*2) }
        last = v
      end
    end, emu.callbackType.write, 0x7E3E9C + cyan*2, 0x7E3E9C + cyan*2)
    H.log(string.format("cyan slot %d, $2020=%04x, monsters %d hp",
      cyan, R.ceiling, monsterHpSum()))
  end),

  -- 1/2/3. the gauge is gone; the real window and its names ----------------
  park("swdtech opens as the tools-shell submenu"),
  H.call(function()
    H.screenshot("bushido_window")
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "SwdTech opened the tools-shell submenu (state $30)")
    H.assertEq(sawNumeral, false,
      "the vanilla numeral gauge (state $37) never opened")
    checkWindow(REAL, "real ceiling")
    local names = {}
    for r, t in ipairs(WINDOW) do names[#names + 1] = techName(t) end
    H.log(string.format("his real window {%s} packs rows 0..%d at 1x..%dx",
      table.concat(names, ","), #WINDOW - 1, #WINDOW))
    -- every name is matched in full, off BushidoName's own bytes ($fe the
    -- space), so Quadra Slam and Quadra Slice are two different names:
    -- the window's techs are drawn, and no tech outside it -- the retired
    -- ones below its base, the unlearned ones above its top -- is
    for t = 0, 7 do
      local inWin = t >= WINDOW[1] and t <= WINDOW[#WINDOW]
      local at = findName(techSeq(t))
      if inWin then
        H.assertEq(at ~= nil, true, string.format("\"%s\" is drawn", techName(t)))
      else
        H.assertEq(at, nil, string.format("\"%s\" (tech %d, %s) is nowhere "
          .. "drawn", techName(t), t, t > REAL and "not learned yet"
          or "slid out of the window"))
      end
    end
  end),

  -- 4. a row beyond the bank cannot commit ---------------------------------
  -- (the bank is Ot6InitBP's 1 at every window he gets without acting, in
  -- this battle or the next, so a window the battle takes away is parked
  -- again and asked again)
  confirmRow(1, "row 1 at bank 1", { repark = true }),
                                       -- row 1 = boost 2 > the real bank of 1
  H.call(function()
    H.assertEq(H.vars.confirm, "refused",
      "confirming a row beyond current bp was refused (the list buzzed)")
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "confirming a row beyond current bp did not commit -- still in the submenu")
    H.assertEq(pend(), 0, "no boost was banked for the refused row")
  end),

  -- 5. confirm resolves: the lowest HIT row, at a bank that covers it -----
  -- Row 0 is that row while Dispatch or a later hit heads his window, and
  -- the opening bank of 1 covers it.  At ceiling 3 row 0 is Retort, whose
  -- cast is the stance (Cmd_07 zeroes its power) and lands nothing, so the
  -- arm takes the first hit row above it and banks the pip its boost needs
  -- with real unboosted turns first (confirmAtBank).
  -- (the chip and reveal halves live in the labeled arm below: every SwdTech
  -- is authored slash $01 and this pool's species author $02, so no
  -- chip can fire here in normal play)
  (function()
    local g0, b0, seqNo, mark
    return H.repeatN(1, {
      H.call(function() started = {} end),
      confirmAtBank(function() return DMG_ROW end,
        function() return DMG_ROW + 1 end, "the hit row"),
      H.call(function()
        -- read at the window that answered: the confirm may have been
        -- answered at a later window, in a later battle
        g0, b0, mark = monsterHpSum(), bp(), #hits
        H.assertEq(pend(), DMG_ROW + 1, string.format(
          "row %d (%s) banked boost %d ($3e9d = %d)", DMG_ROW,
          techName(DMG_T), DMG_ROW + 1, DMG_ROW + 1))
        cyanMode = "defer"; quietA = true
      end),
      driveTo(function() return techStarted(techId(DMG_T)) end, 12000,
        "the hit row's tech reaches ExecCmd"),
      resolveTo(function() return pend() == 0 end,
        "the boosted tech resolves"),
      H.waitFrames(120),
      H.call(function()
        quietA = false
        seqNo = techSeqNo(techId(DMG_T))
        local own, other = techDamage(seqNo, mark)
        H.log(string.format("%s dealt %d in its own action (monster HP sum "
          .. "moved %d across the resolve; %d of it landed from other "
          .. "actions); bp %d pend %d", techName(DMG_T), own,
          g0 - monsterHpSum(), other, bp(), pend()))
        H.assertEq(own > 0, true, "the tech actually dealt damage")
        -- the multiplier, read off Ot6BoostDmg itself: it saw his tech with
        -- the boost live (the positive control), and it stored nothing
        local seen, stored = {}, {}
        for _, c in ipairs(bdCalls) do
          if c.seq == seqNo then
            seen[#seen + 1] = string.format("cmd $%02x pend %d dmg %d",
              c.cmd, c.pend, c.dmg)
          end
        end
        for _, w in ipairs(bdStores) do
          if w.seq == seqNo then
            stored[#stored + 1] = string.format("$%02x@%06x", w.v, w.pc)
          end
        end
        H.log(string.format("[boostdmg] %s: %d call(s) {%s}, %d store(s) to "
          .. "$11B0 {%s}", techName(DMG_T), #seen, table.concat(seen, "; "),
          #stored, table.concat(stored, " ")))
        local live = false
        for _, c in ipairs(bdCalls) do
          if c.seq == seqNo and c.cmd == CMD_SWDTECH and c.pend == DMG_ROW + 1 then
            live = true
          end
        end
        H.assertEq(live, true, string.format(
          "Ot6BoostDmg was handed his %s with cmd $07 and boost %d still "
          .. "pending -- the multiplier was asked", techName(DMG_T), DMG_ROW + 1))
        H.assertEq(#stored, 0,
          "boost bought the tech, not a damage multiplier too (Ot6BoostDmg "
          .. "stored no multiplied $11B0 for it)")
        H.assertEq(bp(), b0 - (DMG_ROW + 1), string.format(
          "boost consumed (%d-%d) with no regen that turn", b0, DMG_ROW + 1))
        H.assertEq(pend(), 0, "pending cleared after the action")
        H.screenshot("bushido_resolved")
      end),
    })
  end)(),

  -- 6. reach 0 BP at an open window through play, and be refused there --
  -- Ot6ActionEnd (ot6_boost.asm) is the regen rule: a character's action
  -- end pays +1 BP unless that action spent a pending boost, which is
  -- charged instead (no regen on a boosted turn); Ot6InitBP opens every
  -- battle at 1.  So arm 5's spend leaves 0 for his NEXT window only if no
  -- other action of his ends first.  One can: measured on the regenerated
  -- camp_escaped (#215), attack $77 (Kitty) berserks him before the
  -- window reopens, each auto-Fight pays +1 up to 5, and the battle ends
  -- without a window, so the next battle's opens at Ot6InitBP's 1.  A
  -- person who wants the empty bank spends what a window shows on a real
  -- boosted tech and waits for the next one; this arm does that for as
  -- many windows as it takes (a bank of 5 is two spends), and at the
  -- window that opens at 0 asks for row 0 and must be refused.  Each
  -- window's premise -- the bank it opened at -- is read at that window,
  -- so a window the battle takes away unanswered counts for nothing and
  -- the next one is asked afresh (a lost window is what Kitty's Berserk
  -- does to an open one, #229, one more window than the spends need).
  (function()
    local WINDOWS = 8
    local seen, b0, row, boost = false, 0, 0, 1
    local spend = {
      confirmRow(function() return row end, "[zero] the spend row"),
      H.cond(function() return H.vars.confirm == "lost" end, {}, {
        H.call(function()
          H.assertEq(pend(), boost, string.format(
            "[zero] %s banked boost %d of the %d shown",
            techName(WINDOW[row + 1]), boost, b0))
          cyanMode = "defer"
        end),
        driveTo(function()
          return not H.battleLoadStarted() or pend() == 0
        end, 20000, "[zero] the spend resolves or the battle ends"),
        H.call(function()
          if not H.battleLoadStarted() then
            H.log("[zero] the battle ended before the spend resolved")
            return
          end
          H.log(string.format("[zero] %s resolved: bank %d -> %d",
            techName(WINDOW[row + 1]), b0, bp()))
          H.assertEq(bp(), b0 - boost,
            "[zero] the boosted turn was charged its boost and paid no regen")
        end),
      }),
    }
    local refuse = {
      H.call(function()
        H.assertEq(H.readByte(ITEMLIST), techId(WINDOW[1]), string.format(
          "row 0 still enumerates %s at 0 bp -- the list is shown, not emptied",
          techName(WINDOW[1])))
      end),
      confirmRow(0, "[zero] row 0 at 0 bp"),
      H.cond(function() return H.vars.confirm == "lost" end, {}, {
        H.call(function()
          H.assertEq(H.vars.confirm, "refused",
            "0 bp: the row-0 confirm was refused (the list buzzed)")
          H.assertEq(H.readByte(MSTATE), ST_TOOLS,
            "0 bp: even row 0 (boost 1) is refused -- there is no free Bushido (#38)")
          H.assertEq(pend(), 0, "and nothing was banked")
          H.assertEq(bp(), 0, "the ledger: the bank really reads 0")
          H.screenshot("bushido_zero_refused")
          seen = true
        end),
      }),
    }
    local steps = {
      H.cond(function() return not seen end, {
        park("[zero] his next SwdTech window"),
        H.call(function()
          flushLedger("zero")
          b0 = bp()
          H.log(string.format("[zero] window opens at bank %d pend %d status2 $%02x",
            b0, pend(), H.readByte(0x3EE5 + cyan*2)))
          H.assertEq(pend(), 0, "[zero] nothing is pending at an open window")
          if b0 == 0 then return end
          -- spend on the deepest HIT row the bank covers (at ceiling 2: a
          -- bank of 3+ spends 3 on Slash, a smaller one 1 on Dispatch), so
          -- Retort's stance stays out of the walk wherever the window has
          -- a hit the bank can pay; only a bank that covers nothing but the
          -- stance (1, at ceiling 3) spends on it
          row = nil
          for r = #WINDOW, 1, -1 do
            if row == nil and r <= b0 and WINDOW[r] ~= STANCE then row = r - 1 end
          end
          for r = #WINDOW, 1, -1 do
            if row == nil and r <= b0 then row = r - 1 end
          end
          boost = row + 1
          H.log(string.format("[zero] spending %d of %d on %s",
            boost, b0, techName(WINDOW[row + 1])))
        end),
        H.cond(function() return b0 == 0 end, refuse, spend),
      }, {}),
    }
    return H.repeatN(1, {
      H.repeatN(WINDOWS, steps),
      H.call(function()
        H.assertEq(seen, true, string.format(
          "[zero] one of his next %d windows opened at 0 BP and answered "
          .. "the row-0 confirm", WINDOWS))
      end),
    })
  end)(),

  -- ============ labeled isolation arms ====================================
  -- (a) the ceiling sweep and Oblivion: $2020 pokes, real ceiling restored.
  --     The submenu re-enumerates at every open, so each poke and reopen
  --     reads one AUTO window (window(), Ot6BushidoTech's own arithmetic).
  --
  --     The poke lives in battle RAM, and park() will happily ride the end
  --     of one battle and the walk into the next to find CYAN's window
  --     (measured at seed shift 1,
  --     build/attempts/bushido-chip-handover/lab/bushido_shift1.log: "reopen at
  --     swept ceiling 5 satisfied after 4685 frames" against ~16 for its
  --     neighbours, and the window it found enumerated $55 -- InitSkills had
  --     reinstated his real ceiling in the new battle).  So the poke is
  --     re-established until the window read is one it actually set: $2020's
  --     low byte still reading `ceil` at the open is the proof.
  (function()
    local steps = {}
    -- His real ceiling leaves the sweep because the arms above cover it
    -- naturally -- except 7, the last step, whose window the Oblivion
    -- checks below read.
    local function swept(ceil) return ceil ~= REAL or ceil == 7 end
    for _, ceil in ipairs({ 0, 1, 2, 3, 4, 5, 7 }) do
      local sweepOne = {}
      sweepOne[#sweepOne+1] = H.repeatN(3, {
        H.cond(function() return (H.readWord(KNOWN) & 0xFF) ~= ceil end, {
          H.call(function()
            H.setPad({})
          end),
          H.pressButtons({ "b" }, 4),                -- close the parked window
          H.waitFrames(16),
          H.call(function()
            -- the isolation write (waived, labeled): the swept ceiling, in
            -- InitSkills' own garbage-high-byte shape
            H.writeWord(KNOWN, 0xFF00 | ceil)
          end),
          park("reopen at swept ceiling " .. ceil),
        }, {}),
      })
      sweepOne[#sweepOne+1] = H.call(function()
        H.assertEq(H.readWord(KNOWN) & 0xFF, ceil, string.format(
          "ceil %d: the swept ceiling is still the one this window opened "
          .. "on (a battle turning over under the sweep reinstates his real "
          .. "one)", ceil))
        checkWindow(ceil, "ceil " .. ceil)
      end)
      steps[#steps+1] = H.cond(function() return swept(ceil) end, sweepOne, {})
    end
    steps[#steps+1] = H.call(function()
      H.assertEq(H.readByte(ITEMLIST + 2 * 6), techId(7), string.format(
        "ceiling 7 row 2 (boost 3) = tech 7 (%s/Oblivion, id $%02x) -- "
        .. "the divine top tier, the named tech-8 ceiling arm", techName(7),
        techId(7)))
      H.assertEq(findName(techSeq(0)), nil, string.format(
        "at ceiling 7 the retired \"%s\" is no longer drawn (the "
        .. "window slid weakest-out)", techName(0)))
      -- restore his real ceiling before anything else runs
      H.writeWord(KNOWN, R.ceiling)
      H.log("sweep done; real ceiling restored")
    end)
    return H.repeatN(1, steps)
  end)(),
  -- (b) the class-chip and reveal half (labeled): the
  --     tech class is slash ($01, Ot6SkillClassTbl) and this pool authors
  --     $02, so the tech's class bit is staged into every live monster's
  --     weak mask (the tech's default target is the engine's pick) and the
  --     real tech -- arm 5's hit row, Dispatch below ceiling 3, banked for
  --     with real unboosted turns where its boost is past 1 -- then runs the
  --     engine's own chip path.
  --
  --     Whether THIS battle still owes CYAN a SwdTech window is the
  --     fixture's timing, not the property under test.  Measured
  --     (build/attempts/bushido-chip-handover/lab/bushido_probe2.log): Kitty
  --     berserked him at f3360 -- `st2=$10` on every sample from there --
  --     and a berserk character never takes another window, so he
  --     auto-Fought the pool from `mon=777` down to `mon=0` and the battle
  --     ended with the arm's Dispatch never cast.  The arm used to log that
  --     and return, which is a green that asserted nothing.  It now walks
  --     into the next encounter and asks again -- Berserk does not survive
  --     a battle -- for up to TRIES encounters, and says so if none of them
  --     gave him the turn.
  (function()
    local TRIES = 4
    local sh0, rv0 = {}, {}
    local chipSeen, tries = false, 0
    local attempt = {
      H.call(function()
        tries = tries + 1
        cyanMode = "defer"; quietA = false
        H.log(string.format("[chip] attempt %d of %d", tries, TRIES))
      end),
      -- leave whatever window is parked (the sweep's, on the first pass)
      H.pressButtons({ "b" }, 4),
      H.waitFrames(16),
      -- On the first pass this is already true and costs nothing.  On a
      -- retry it rides the victory/EXP screens out (the drive's A mash),
      -- walks the field and takes the next encounter.
      driveTo(function()
        return H.battleLoadStarted() and monsterHpSum() > 0
      end, 40000, "[chip] a battle with a live pool to chip"),
      H.waitFrames(90),
      H.call(function()
        for slot = 0, 3 do
          local id = H.readByte(0x3ED8 + slot*2)
          if id == 0x02 then cyan = slot end
          if id == 0x03 then shadow = slot end
        end
        cyanMode = "item"
      end),
      driveTo(function()
        return not H.battleLoadStarted() or bp() >= DMG_ROW + 1
      end, 40000, "[chip] real unboosted turns (Item, or Fight with no Tonic or Potion left) bank the hit row's boost"),
      H.cond(function()
        return H.battleLoadStarted() and bp() >= DMG_ROW + 1
      end, {
        H.call(function()
          for m = 0, 5 do
            sh0[m] = H.readByte(0x3E38 + (8 + m*2))
            rv0[m] = H.readByte(0x3E9D + (8 + m*2))
            if H.readWord(0x3BFC + m*2) > 0 then
              -- the isolation write (waived, labeled): add the tech's class
              -- bit to the authored mask rather than replacing it
              local a = 0x3E9C + (8 + m*2)
              H.writeByte(a, H.readByte(a) | techClass(DMG_T))
            end
          end
          started = {}
          cyanMode = "tech:" .. DMG_ROW
        end),
        driveTo(function()
          return not H.battleLoadStarted() or techStarted(techId(DMG_T))
        end, 20000, "[chip] the arm's tech reaches ExecCmd"),
        H.call(function() cyanMode = "defer"; quietA = true end),
        resolveTo(function()
          return not H.battleLoadStarted() or pend() == 0
        end, "[chip] the arm's tech resolves"),
        H.waitFrames(120),
        H.call(function()
          quietA = false
          if not H.battleLoadStarted() then
            H.log("[chip] the battle ended before the tech landed; "
              .. "taking the next encounter")
            return
          end
          local chipped, slashVisible = false, false
          for m = 0, 5 do
            local sh1 = H.readByte(0x3E38 + (8 + m*2))
            local rv1 = H.readByte(0x3E9D + (8 + m*2))
            if sh1 < (sh0[m] or 0) then chipped = true end
            -- This long-lived fixture may already know slash from an
            -- upstream fight.  The contract is that the real Dispatch chip
            -- leaves its class revealed, not that this particular replay is
            -- the first time the save has ever learned it.
            if sh1 < (sh0[m] or 0) and (rv1 & techClass(DMG_T)) ~= 0 then
              slashVisible = true
            end
            if sh1 ~= sh0[m] or rv1 ~= rv0[m] then
              H.log(string.format("  monster %d: shields %d -> %d, revealed "
                .. "$%02x -> $%02x", m, sh0[m], sh1, rv0[m], rv1))
            end
          end
          H.assertEq(chipped, true, string.format(
            "the real %s chipped the (staged) class-$%02x-weak monster's "
            .. "shields", techName(DMG_T), techClass(DMG_T)))
          H.assertEq(slashVisible, true, string.format(
            "and the chipped target exposes the tech's class ($%02x)",
            techClass(DMG_T)))
          chipSeen = true
        end),
      }, {}),
    }
    return H.repeatN(1, {
      H.repeatN(TRIES, {
        H.cond(function() return not chipSeen end, attempt, {}),
      }),
      H.call(function()
        H.assertEq(chipSeen, true, string.format(
          "[chip] one of %d encounters gave CYAN the real SwdTech turn this "
          .. "arm measures (tried %d)", TRIES, tries))
      end),
    })
  end)(),
  H.call(function()
    H.log("PASSED: the submenu enumerates, refuses by bp, resolves; the "
      .. "sweep and the chip ride their labeled arms")
  end),
})

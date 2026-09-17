-- @suite slow savestate=camp_escaped
-- battle_bushido.lua -- the Bushido submenu: SwdTech is a tools-shell
-- submenu rather than the vanilla numeral gauge.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_BUSHIDO, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x30, 0x37, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM, CMD_FIGHT = 0x07, 0x01, 0x00
local KNOWN, ITEMLIST, KROW = 0x2020, 0x4005, 0x8967
local TONIC, POTION = 0xE8, 0xE9
local OT6_SLASH = 0x01
local DMG_CAP = 420                   -- an honest boost-1 Dispatch measures
                                      -- ~284 here now that CYAN reaches
                                      -- camp_escaped at level 13 (three
                                      -- techs, higher Vigor -- the
                                      -- fight-the-encounters directive at
                                      -- work; was ~117 at the lower-level,
                                      -- two-tech calibration).  An
                                      -- Ot6BoostDmg x2/x4 double-dip (~570+)
                                      -- still clears this cap easily.

local TECH = { [0] = "Dispatch", "Retort", "Slash", "Quadra Slam",
               "Empowerer", "Stunner", "Quadra Slice", "Cleave" }
-- Ot6AbilityCostTbl's SwdTech rows (ff6/src/battle/ot6_boost.asm:1503-1510)
local COST = { [0x55] = 4, [0x56] = 10, [0x57] = 13, [0x58] = 16, [0x5c] = 99 }
local WIN = {
  [0] = { 0 },
  [1] = { 0, 1 },
  [2] = { 0, 1, 2 },
  [3] = { 1, 2, 3 },
  [4] = { 2, 3, 4 },
  [5] = { 3, 4, 5 },
  [7] = { 5, 6, 7 },
}

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
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
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
local function decide()
  if H.readByte(MSTATE) == ST_BUSHIDO then sawNumeral = true end
  if H.readByte(MENU) == 0 then
    if quietA then return {} end
    return (H.frame % 8 < 4) and { a = true } or {}
  end
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
  if act == shadow then
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < 60 then hurt = true end
    end
    -- nothing to heal with hands the window on too (measured: with the bag
    -- empty of both, B out of the list and back into Item held his window
    -- forever, and CYAN's never came)
    local canCare = bagIdxOf({ TONIC, POTION }) ~= nil
    if st == ST_CMD and not (hurt and canCare) then btn = "x"
    elseif st == ST_CMD then
      local want = cmdRowOf(shadow, CMD_ITEM)
      local cur = H.readByte(CMDROW + shadow) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
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
-- move the parked cursor onto `row` and edge one A, without the tech
-- steering (for the refusal arms, whose confirm must be refused)
-- (`row` is a number, or a function read when the walk runs)
local function pressRowOnce(row)
  local function r() return type(row) == "function" and row() or row end
  return H.repeatN(1, {
    (function()
      local ph = 0
      return H.driveUntil(function()
        return H.readByte(MSTATE) == ST_TOOLS and H.readByte(KROW + cyan) == r()
      end, 600, {
        H.call(function()
          ph = (ph + 1) % 8
          if ph >= 4 then H.setPad({}); return end
          local cur = H.readByte(KROW + cyan)
          H.setPad({ [cur < r() and "down" or "up"] = true })
        end),
        H.waitFrames(1),
      }, type(row) == "function" and "cursor walked to the spend row"
                                  or ("cursor walked to row " .. row))
    end)(),
    H.call(function() H.setPad({}) end),
    H.waitFrames(8),
    H.pressButtons({ "a" }, 4),
    H.waitFrames(16),
  })
end

local spells = {}
local ledger = {}
local function flushLedger(tag)
  for _, e in ipairs(ledger) do
    H.log(string.format("[%s] ledger f=%d bank %d -> %d (status2 $%02x%s)",
      tag, e.f, e.from, e.to, e.st2,
      (e.st2 & 0x10) ~= 0 and ": Berserk" or ""))
  end
  ledger = {}
end
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end
local function checkWindow(ceil, tag)
  local techs = WIN[ceil]
  for r = 0, 3 do
    local id = H.readByte(ITEMLIST + r * 6)
    local right = H.readByte(ITEMLIST + r * 6 + 3)
    H.assertEq(right, 0xFF, string.format("%s row %d: right column empty", tag, r))
    if techs[r + 1] then
      local want = 0x55 + techs[r + 1]
      H.assertEq(id, want, string.format("%s row %d (boost %d): %s id $%02x",
        tag, r, r + 1, TECH[techs[r + 1]], want))
      if COST[id] then
        H.assertEq(H.readByte(ITEMLIST + r * 6 + 1), COST[id], string.format(
          "%s row %d: %s costs %d", tag, r, TECH[techs[r + 1]], COST[id]))
      end
    else
      H.assertEq(id, 0xFF, string.format(
        "%s row %d: no row (#38: three tiers, fewer when the learned set is "
        .. "short)", tag, r))
    end
  end
  H.assertEq(H.readByte(ITEMLIST + 3 * 6), 0xFF,
    tag .. ": the 4th window row is always empty (the 0x tier is gone)")
end

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
    H.assertEq(H.readByte(0x1600 + 2*37 + 8), 14,
      "CYAN arrives at camp_escaped at level 14 -- the fighting lineage "
      .. "runs one level ahead of the fled curve, still past "
      .. "BushidoLevelTbl's third threshold (12) and below its fourth "
      .. "(15), which is what sets the ceiling below")
    R.ceiling = H.readWord(KNOWN)
    H.assertEq(R.ceiling & 0xFF, 2,
      "his REAL ceiling is 2 (three techs learned by level 14, "
      .. "BushidoLevelTbl 1/6/12 with 15 still ahead; the high byte "
      .. "carries InitSkills' garbage, the #4 regression's true shape)")
    H.assertEq(bp(), 1, "the natural opening bank (Ot6InitBP)")
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
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
    checkWindow(2, "real ceiling")
    H.log("his real window {Dispatch,Retort,Slash} packs rows 0/1/2 at 1x/2x/3x")
    H.assertEq(findName(glyphs("Dispatch")) ~= nil, true, "\"Dispatch\" is drawn")
    H.assertEq(findName(glyphs("Retort")) ~= nil, true, "\"Retort\" is drawn")
    H.assertEq(findName(glyphs("Slash")) ~= nil, true, "\"Slash\" is drawn")
    -- glyphs() has no mapping for a space, so match the first word.  It is
    -- unambiguous here: Quadra Slam (tech 3) and Quadra Slice (tech 6) are
    -- both above his ceiling, so neither may be drawn.
    H.assertEq(findName(glyphs("Quadra")), nil,
      "\"Quadra\" -- Quadra Slam is the first tech he has NOT learned -- "
      .. "is nowhere drawn")
  end),

  -- 4. a row beyond the bank cannot commit ---------------------------------
  pressRowOnce(1),                     -- Retort = boost 2 > the real bank of 1
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "confirming a row beyond current bp did not commit -- still in the submenu")
    H.assertEq(pend(), 0, "no boost was banked for the refused row")
  end),

  -- 5. confirm resolves: row 0 at the real bank ----------------------------
  -- (the chip and reveal halves live in the labeled arm below: every SwdTech
  -- is authored slash $01 and this pool's species author $02, so no
  -- chip can fire here in normal play)
  (function()
    local g0
    return H.repeatN(1, {
      H.call(function()
        g0 = monsterHpSum()
        spells = {}
      end),
      pressRowOnce(0),                 -- Dispatch = boost 1 = the whole bank
      H.call(function()
        H.assertEq(pend(), 1, "row 0 banked boost 1 ($3e9d = 1)")
        cyanMode = "defer"; quietA = true
      end),
      driveTo(function() return sawSpell(0x55) end, 12000,
        "Dispatch reaches $3410"),
      resolveTo(function() return pend() == 0 end,
        "the boosted tech resolves"),
      H.waitFrames(120),
      H.call(function()
        quietA = false
        local dmg = g0 - monsterHpSum()
        H.log(string.format("Dispatch dealt %d; bp %d pend %d", dmg, bp(), pend()))
        H.assertEq(dmg > 0, true, "the tech actually dealt damage")
        H.assertEq(dmg < DMG_CAP, true,
          "boost bought the tech, not a damage multiplier too")
        H.assertEq(bp(), 0, "boost consumed (1-1) with no regen that turn")
        H.assertEq(pend(), 0, "pending cleared after the action")
        H.screenshot("bushido_resolved")
      end),
    })
  end)(),

  -- 6. reach 0 BP at an open window through play ----------------------
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
  -- many windows as it takes (a bank of 5 is two spends).
  (function()
    local WINDOWS = 6
    local seen, b0, row, boost = false, 0, 0, 1
    local spend = {
      pressRowOnce(function() return row end),
      H.call(function()
        H.assertEq(pend(), boost, string.format(
          "[zero] %s banked boost %d of the %d shown", TECH[row], boost, b0))
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
          TECH[row], b0, bp()))
        H.assertEq(bp(), b0 - boost,
          "[zero] the boosted turn was charged its boost and paid no regen")
      end),
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
          if b0 == 0 then seen = true; return end
          -- his window here is Dispatch/Retort/Slash at boost 1/2/3: a bank
          -- of 3+ spends 3 on Slash, a smaller one 1 on Dispatch (Retort's
          -- stance stays out of the walk)
          if b0 >= 3 then row, boost = 2, 3 else row, boost = 0, 1 end
          H.log(string.format("[zero] spending %d of %d on %s",
            boost, b0, TECH[row]))
        end),
        H.cond(function() return not seen end, spend, {}),
      }, {}),
    }
    return H.repeatN(1, {
      H.repeatN(WINDOWS, steps),
      H.call(function()
        H.assertEq(seen, true, string.format(
          "[zero] one of his next %d windows opened at 0 BP", WINDOWS))
      end),
    })
  end)(),
  H.call(function()
    H.assertEq(bp(), 0, "the ledger: the bank really reads 0")
    H.assertEq(H.readByte(ITEMLIST), 0x55,
      "row 0 still enumerates Dispatch at 0 bp -- the list is shown, not emptied")
  end),
  pressRowOnce(0),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "0 bp: even row 0 (boost 1) is refused -- there is no free Bushido (#38)")
    H.assertEq(pend(), 0, "and nothing was banked")
    H.screenshot("bushido_zero_refused")
  end),

  -- ============ labeled isolation arms ====================================
  -- (a) the ceiling sweep and Oblivion: $2020 pokes, real ceiling restored.
  --     The submenu re-enumerates at every open, so each poke and reopen
  --     reads one window of the WIN table.
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
    -- Ceiling 2 leaves the sweep because the arms above cover it naturally.
    for _, ceil in ipairs({ 0, 1, 3, 4, 5, 7 }) do
      steps[#steps+1] = H.repeatN(3, {
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
      steps[#steps+1] = H.call(function()
        H.assertEq(H.readWord(KNOWN) & 0xFF, ceil, string.format(
          "ceil %d: the swept ceiling is still the one this window opened "
          .. "on (a battle turning over under the sweep reinstates his real "
          .. "one)", ceil))
        checkWindow(ceil, "ceil " .. ceil)
      end)
    end
    steps[#steps+1] = H.call(function()
      H.assertEq(H.readByte(ITEMLIST + 2 * 6), 0x5c,
        "ceiling 7 row 2 (boost 3) = tech 7 (Cleave/Oblivion, id $5c) -- "
        .. "the divine top tier, the named tech-8 ceiling arm")
      H.assertEq(findName(glyphs("Dispatch")), nil,
        "at ceiling 7 the retired \"Dispatch\" is no longer drawn (the "
        .. "window slid weakest-out)")
      -- restore his real ceiling before anything else runs
      H.writeWord(KNOWN, R.ceiling)
      H.log("sweep done; real ceiling restored")
    end)
    return H.repeatN(1, steps)
  end)(),
  -- (b) the class-chip and reveal half (labeled): the
  --     tech class is slash ($01, Ot6SkillClassTbl) and this pool authors
  --     $02, so the $01 bit is staged into every live monster's weak mask
  --     (the tech's default target is the engine's pick) and the real
  --     Dispatch then runs the engine's own chip path.
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
        return not H.battleLoadStarted() or bp() >= 1
      end, 40000, "[chip] a real unboosted turn (Item, or Fight with no Tonic or Potion left) rebanks the pip"),
      H.cond(function() return H.battleLoadStarted() and bp() >= 1 end, {
        H.call(function()
          for m = 0, 5 do
            sh0[m] = H.readByte(0x3E38 + (8 + m*2))
            rv0[m] = H.readByte(0x3E9D + (8 + m*2))
            if H.readWord(0x3BFC + m*2) > 0 then
              -- the isolation write (waived, labeled): add the slash bit to
              -- the authored mask rather than replacing it
              local a = 0x3E9C + (8 + m*2)
              H.writeByte(a, H.readByte(a) | OT6_SLASH)
            end
          end
          spells = {}
          cyanMode = "tech:0"
        end),
        driveTo(function()
          return not H.battleLoadStarted() or sawSpell(0x55)
        end, 20000, "[chip] the arm's Dispatch reaches $3410"),
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
            if sh1 < (sh0[m] or 0) and (rv1 & OT6_SLASH) ~= 0 then
              slashVisible = true
            end
            if sh1 ~= sh0[m] or rv1 ~= rv0[m] then
              H.log(string.format("  monster %d: shields %d -> %d, revealed "
                .. "$%02x -> $%02x", m, sh0[m], sh1, rv0[m], rv1))
            end
          end
          H.assertEq(chipped, true,
            "the real tech chipped the (staged) slash-weak monster's shields")
          H.assertEq(slashVisible, true,
            "and the chipped target exposes the slash class ($01)")
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

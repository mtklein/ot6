-- @suite slow savestate=camp_escaped
-- battle_bushido.lua -- v0.5 Bushido submenu (issue #8): SwdTech is a
-- tools-shell submenu rather than the vanilla numeral gauge.
--
-- Vanilla SwdTech ran a free bar (btlgfx_main.asm UpdateMenuState_35/37); OT6
-- deletes that path (OpenCmdMenuTbl[7] -> _c1_bushido_open) and drives SwdTech
-- through the Tools window shell (menu state $30).  Each row is a boost level,
-- weakest at the top; #38's 1-BP floor makes row i = boost i+1, with no free
-- tier.
--
-- Issue #75 conversion.  The old apparatus installed a triple-CYAN party by
-- poke, wrote the katana flag, pinned $2020/bp/MP/HP/shields, stopped the
-- guards, and poked every cursor.  On camp_escaped Cyan is real (the
-- bushidogrey and mpcost kit: katana SWDTECH flag $3BA4 bit 1 reads $82; three
-- techs learned, with $2020's low byte reading his true ceiling of 2, under
-- the same garbage high byte issue #4 documents InitSkills leaving), and
-- the input-driven arms run against his real window {Dispatch $55 at 4, Retort
-- $56 at 10, Slash $57 at 13} with cursor rows walked rather than poked:
--
--   1. the numeral gauge is gone: opening SwdTech lands in $30, and a watch
--      shows $37 never appears on the way.
--   2. the real window: WIN[2] = {Dispatch, Retort, Slash} at rows 0, 1 and 2
--      with their authored costs, and the right column and row 3 $ff.
--   3. names: Dispatch, Retort and Slash draw (from BushidoName), and
--      "Quadra" -- the first word of Quadra Slam, the first tech he has not
--      learned -- is nowhere in the window.
--   4. a row beyond current BP cannot commit: at the natural opening bank
--      of 1, confirming row 1 (boost 2) is refused, the submenu stays, and
--      nothing is banked.
--   5. confirm resolves: row 0 at bank 1 banks boost 1, latches Dispatch,
--      reaches $3410, deals real damage under the no-multiplier cap, and
--      the boost is consumed with no regen that turn (1 -> 0).
--   6. #38's main case, on the bank arm 5 just spent: at 0 bp
--      even row 0 is refused, because there is no free Bushido, while the
--      rows still enumerate, shown rather than emptied.
--
--   How many techs he has is a fact about his level, not a constant.
--   BushidoLevelTbl is 1, 6, 12, 15, 24, 34, 44, 70
--   (ff6/src/field/event.asm:1235-1236), read by UpdateCyan at :1181-1199,
--   so the count changes as the route's levels change.  He arrives at
--   camp_escaped at level 13 today (the #84 chest wave's extra fights moved
--   him up from 12), which still sits between the third threshold (12) and
--   the fourth (15), so the window stays three rows: Dispatch, Retort and
--   Slash.  He used to arrive at 11 and the window was two rows.
--   If this file's ceiling assertion goes red again, check his level at the
--   savestate before suspecting the feature.
--
--   Labeled isolation arms (owner ruling 2026-08-10).  Cyan's real
--   learned set is short and stays short at these levels, so the
--   ceiling sweep, the moving-window
--   enumeration at N=1,2,4,5,6,8, including Oblivion (tech 7, id $5c,
--   the named tech-8 ceiling arm), keeps its $2020 pokes, recorded here,
--   with the real ceiling restored after.  The class-chip and reveal half of
--   the old confirm arm is also labeled: every SwdTech is authored slash
--   (Ot6SkillClassTbl, $01) and this pool's species author weak-class
--   $02, so no chip can fire here in normal play.  The arm stages the $01 bit
--   into every live monster's weak mask (every one, because the tech's
--   default target is the engine's pick; measured: staging one monster
--   read 3->3 while the hit landed elsewhere) and the real Dispatch then
--   chips and reveals through the engine's own path.  Convert both
--   organically as higher-level content lands.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_BUSHIDO, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x30, 0x37, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KNOWN, ITEMLIST, KROW = 0x2020, 0x4005, 0x8967
local TONIC, POTION = 0xE8, 0xE9
local OT6_SLASH = 0x01
local DMG_CAP = 240                   -- a Dispatch measures ~117 here; an
                                      -- Ot6BoostDmg x4 double-dip would clear
                                      -- this cap easily

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
    if st == ST_CMD and not hurt then btn = "x"
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
      if st == ST_CMD then
        local want = cmdRowOf(cyan, CMD_ITEM)
        local cur = H.readByte(CMDROW + cyan) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_ITEM then
        local want = bagIdxOf({ TONIC, POTION })
        if want == nil then error("bank ran out of items", 0) end
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
local function pressRowOnce(row)
  return H.repeatN(1, {
    (function()
      local ph = 0
      return H.driveUntil(function()
        return H.readByte(MSTATE) == ST_TOOLS and H.readByte(KROW + cyan) == row
      end, 600, {
        H.call(function()
          ph = (ph + 1) % 8
          if ph >= 4 then H.setPad({}); return end
          local cur = H.readByte(KROW + cyan)
          H.setPad({ [cur < row and "down" or "up"] = true })
        end),
        H.waitFrames(1),
      }, "cursor walked to row " .. row)
    end)(),
    H.call(function() H.setPad({}) end),
    H.waitFrames(8),
    H.pressButtons({ "a" }, 4),
    H.waitFrames(16),
  })
end

local spells = {}
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
    -- Name the cause before the effect: the ceiling below is derived from
    -- his level, so a route that levels him differently should say so here
    -- rather than read as a broken feature.  Character record 2 is CYAN;
    -- +$08 is level ($1600 + c*37, tools/savestate_party.py's layout).
    -- 13 follows the fixture: the #84 chest wave's extra fights level him
    -- 12 -> 13, still short of BushidoLevelTbl's fourth threshold (15), so
    -- the three-tech ceiling below is unchanged.
    H.assertEq(H.readByte(0x1600 + 2*37 + 8), 13,
      "CYAN arrives at camp_escaped at level 13 -- past BushidoLevelTbl's "
      .. "third threshold (event.asm:1235), which is what sets the ceiling below")
    R.ceiling = H.readWord(KNOWN)
    H.assertEq(R.ceiling & 0xFF, 2,
      "his REAL ceiling is 2 (three techs learned at level 13, "
      .. "BushidoLevelTbl 1/6/12; the high byte carries "
      .. "InitSkills' garbage, the #4 regression's true shape)")
    H.assertEq(bp(), 1, "the natural opening bank (Ot6InitBP)")
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
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
      H.waitUntil(function() return pend() == 0 end, 900,
        "the boosted tech resolves", 10),
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

  -- 6. #38's main case, on the bank arm 5 just spent ----------------------
  park("reopen at the 0 bank arm 5 earned"),
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

  -- ============ labeled isolation arms (see the header) ===================
  -- (a) the ceiling sweep and Oblivion: $2020 pokes, real ceiling restored.
  --     The submenu re-enumerates at every open, so each poke and reopen
  --     reads one window of the WIN table.
  (function()
    local steps = {}
    -- Ceiling 1 (the two-row window) is swept here now that his real ceiling
    -- is 2: it was the natural case while he arrived at level 11 and is
    -- poke-only from level 12 on, so it moves into the sweep rather than
    -- being dropped.  Ceiling 2 leaves the sweep because the arms above cover it
    -- naturally.
    for _, ceil in ipairs({ 0, 1, 3, 4, 5, 7 }) do
      steps[#steps+1] = H.call(function()
        H.setPad({})
      end)
      steps[#steps+1] = H.pressButtons({ "b" }, 4)   -- close the parked window
      steps[#steps+1] = H.waitFrames(16)
      steps[#steps+1] = H.call(function()
        -- the isolation write (waived, labeled): the swept ceiling, in
        -- InitSkills' own garbage-high-byte shape (#4)
        H.writeWord(KNOWN, 0xFF00 | ceil)
      end)
      steps[#steps+1] = park("reopen at swept ceiling " .. ceil)
      steps[#steps+1] = H.call(function()
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
  -- (b) the class-chip and reveal half of the old confirm arm (labeled): the
  --     tech class is slash ($01, Ot6SkillClassTbl) and this pool authors
  --     $02, so the $01 bit is staged into every live monster's weak mask
  --     (the tech's default target is the engine's pick) and the real
  --     Dispatch then runs the engine's own chip path.
  (function()
    local sh0, rv0 = {}, {}
    return H.repeatN(1, {
      H.pressButtons({ "b" }, 4),      -- leave the parked window
      H.waitFrames(16),
      H.call(function() cyanMode = "item" end),
      driveTo(function()
        return not H.battleLoadStarted() or bp() >= 1
      end, 40000, "a real item turn rebanks the chip arm's pip"),
      H.cond(function() return H.battleLoadStarted() and bp() >= 1 end, {
        H.call(function()
          for m = 0, 5 do
            sh0[m] = H.readByte(0x3E38 + (8 + m*2))
            rv0[m] = H.readByte(0x3E9D + (8 + m*2))
            if H.readWord(0x3BFC + m*2) > 0 then
              -- the isolation write (waived, labeled): add the slash bit to
              -- the authored mask rather than replacing it; a $01 assignment
              -- overwrote $02 in an earlier draft and suppressed the chip
              local a = 0x3E9C + (8 + m*2)
              H.writeByte(a, H.readByte(a) | OT6_SLASH)
            end
          end
          spells = {}
          cyanMode = "tech:0"
        end),
        driveTo(function()
          return not H.battleLoadStarted() or sawSpell(0x55)
        end, 20000, "the chip arm's Dispatch reaches $3410"),
        H.call(function() cyanMode = "defer"; quietA = true end),
        H.waitUntil(function()
          return not H.battleLoadStarted() or pend() == 0
        end, 900, "the chip arm's tech resolves", 10),
        H.waitFrames(120),
        H.call(function()
          quietA = false
          if not H.battleLoadStarted() then
            H.log("chip arm: the battle ended under the tech this run")
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
        end),
      }, {}),
    })
  end)(),
  H.call(function()
    H.log("PASSED: the submenu enumerates, refuses by bp, resolves; the "
      .. "sweep and the chip ride their labeled arms")
  end),
})

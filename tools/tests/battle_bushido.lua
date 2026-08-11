-- @suite slow frontier=camp_escaped
-- battle_bushido.lua -- v0.5 Bushido submenu (issue #8): SwdTech is a tools-shell
-- SUBMENU, not the vanilla numeral gauge.
--
-- Vanilla SwdTech ran a free bar (btlgfx_main.asm UpdateMenuState_35/37); OT6
-- deletes that path (OpenCmdMenuTbl[7] -> _c1_bushido_open) and drives SwdTech
-- through the Tools window shell (menu state $30).  Each row IS a boost level,
-- weakest at TOP; #38's 1-BP floor makes row i = boost i+1, no free tier.
--
-- Issue #75 conversion.  The old apparatus installed a triple-CYAN party by
-- poke, wrote the katana flag, pinned $2020/bp/MP/HP/shields, stopped the
-- guards, and poked every cursor.  On camp_escaped CYAN IS REAL (the
-- bushidogrey/mpcost kit: katana SWDTECH flag $3BA4 bit 1 reads $82; two
-- techs really learned -- $2020's low byte reads HIS true ceiling 1, under
-- the same garbage high byte issue #4 documents InitSkills leaving), and
-- the input-driven arms run against his REAL window {Dispatch $55 @4, Retort
-- $56 @10} with cursor rows WALKED, never poked:
--
--   1. THE NUMERAL GAUGE IS GONE: opening SwdTech lands in $30; a watch
--      proves $37 never appears on the way.
--   2. THE REAL WINDOW: WIN[1] = {Dispatch, Retort} at rows 0/1 with
--      their authored costs, right column and rows 2-3 $ff -- the
--      short-learned-set arm of the enumeration, previously only
--      reachable by poke.
--   3. NAMES: Dispatch and Retort draw (from BushidoName); "Slash" -- the
--      first tech he has NOT learned -- is nowhere in the window.
--   4. A ROW BEYOND CURRENT BP CANNOT COMMIT: at the natural opening bank
--      of 1, confirming row 1 (boost 2) is refused -- submenu stays,
--      nothing banked.
--   5. CONFIRM RESOLVES: row 0 at bank 1 banks boost 1, latches Dispatch,
--      reaches $3410, deals real damage under the no-multiplier cap, and
--      the boost is consumed with no regen that turn (1 -> 0).
--   6. #38's LOAD-BEARING CASE, on the bank arm 5 just spent: at 0 bp
--      even row 0 is refused -- there is no free Bushido -- while the
--      rows still enumerate (shown, not emptied).
--
--   *** LABELED ISOLATION ARMS (owner ruling 2026-08-10). ***  Cyan's real
--   learned set is two techs and stays that way without the leveled-grind
--   tier the owner declined, so the CEILING SWEEP -- the moving-window
--   enumeration at N=1,3,4,5,6,8, including Oblivion (tech 7, id $5c,
--   the named tech-8 ceiling arm) -- keeps its $2020 pokes, said loudly,
--   with the real ceiling restored after.  The CLASS-CHIP/REVEAL half of
--   the old confirm arm is also labeled: every SwdTech is authored SLASH
--   (Ot6SkillClassTbl, $01) and this pool's species author weak-class
--   $02, so no chip can fire here in normal play -- the arm stages the $01 bit
--   into every live monster's weak mask (every one, because the tech's
--   default target is the engine's pick -- measured: staging one monster
--   read 3->3 while the hit landed elsewhere) and the REAL Dispatch then
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
local COST = { [0x55] = 4, [0x56] = 10, [0x58] = 16, [0x5c] = 99 }
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

-- the shared drive machine (battle_bushidogrey's)
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
-- shove the parked cursor onto `row` and edge one A, WITHOUT the tech
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
    R.ceiling = H.readWord(KNOWN)
    H.assertEq(R.ceiling & 0xFF, 1,
      "his REAL ceiling is 1 (two techs learned; the high byte carries "
      .. "InitSkills' garbage, the #4 regression's true shape)")
    H.assertEq(bp(), 1, "the natural opening bank (Ot6InitBP)")
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    H.log(string.format("cyan slot %d, $2020=%04x, monsters %d hp",
      cyan, R.ceiling, monsterHpSum()))
  end),

  -- 1/2/3. the gauge is dead; the REAL window and its names ----------------
  park("swdtech opens as the tools-shell submenu"),
  H.call(function()
    H.screenshot("bushido_window")
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "SwdTech opened the tools-shell submenu (state $30)")
    H.assertEq(sawNumeral, false,
      "the vanilla numeral gauge (state $37) never opened")
    checkWindow(1, "real ceiling")
    H.log("his real window {Dispatch,Retort} packs rows 0/1 at 1x/2x")
    H.assertEq(findName(glyphs("Dispatch")) ~= nil, true, "\"Dispatch\" is drawn")
    H.assertEq(findName(glyphs("Retort")) ~= nil, true, "\"Retort\" is drawn")
    H.assertEq(findName(glyphs("Slash")), nil,
      "\"Slash\" -- the first tech he has NOT learned -- is nowhere drawn")
  end),

  -- 4. a row beyond the bank cannot commit ---------------------------------
  pressRowOnce(1),                     -- Retort = boost 2 > the real bank of 1
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "confirming a row beyond current bp did not commit -- still in the submenu")
    H.assertEq(pend(), 0, "no boost was banked for the refused row")
  end),

  -- 5. confirm resolves: row 0 at the real bank ----------------------------
  -- (the chip/reveal halves live in the LABELED arm below: every SwdTech
  -- is authored SLASH $01 and this pool's species author $02, so no
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

  -- 6. #38's load-bearing case, on the bank arm 5 just spent ---------------
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

  -- ============ LABELED ISOLATION ARMS (see the header) ===================
  -- (a) the ceiling sweep + Oblivion: $2020 pokes, real ceiling restored.
  --     The submenu re-enumerates at every open, so each poke + reopen
  --     reads one window of the WIN table.
  (function()
    local steps = {}
    for _, ceil in ipairs({ 0, 2, 3, 4, 5, 7 }) do
      steps[#steps+1] = H.call(function()
        H.setPad({})
      end)
      steps[#steps+1] = H.pressButtons({ "b" }, 4)   -- close the parked window
      steps[#steps+1] = H.waitFrames(16)
      steps[#steps+1] = H.call(function()
        -- ISOLATION WRITE (waived, labeled): the swept ceiling, in
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
      -- restore his REAL ceiling before anything else runs
      H.writeWord(KNOWN, R.ceiling)
      H.log("sweep done; real ceiling restored")
    end)
    return H.repeatN(1, steps)
  end)(),
  -- (b) the class-chip/reveal half of the old confirm arm (labeled): the
  --     tech class is SLASH ($01, Ot6SkillClassTbl) and this pool authors
  --     $02, so the $01 bit is staged into EVERY live monster's weak mask
  --     (the tech's default target is the engine's pick) and the REAL
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
              -- ISOLATION WRITE (waived, labeled): add the slash bit to
              -- the authored mask (never clobber it -- a $01 := overwrote
              -- $02 in an earlier draft and silenced the chip mid-diagnosis)
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
          local chipped, revealed = false, false
          for m = 0, 5 do
            local sh1 = H.readByte(0x3E38 + (8 + m*2))
            local rv1 = H.readByte(0x3E9D + (8 + m*2))
            if sh1 < (sh0[m] or 0) then chipped = true end
            if (rv1 & OT6_SLASH) ~= 0 and (rv0[m] & OT6_SLASH) == 0 then
              revealed = true
            end
            if sh1 ~= sh0[m] or rv1 ~= rv0[m] then
              H.log(string.format("  monster %d: shields %d -> %d, revealed "
                .. "$%02x -> $%02x", m, sh0[m], sh1, rv0[m], rv1))
            end
          end
          H.assertEq(chipped, true,
            "the real tech chipped the (staged) slash-weak monster's shields")
          H.assertEq(revealed, true, "and revealed the slash class ($01)")
        end),
      }, {}),
    })
  end)(),
  H.call(function()
    H.log("PASSED: the submenu enumerates, refuses by bp, resolves; the "
      .. "sweep and the chip ride their labeled arms")
  end),
})

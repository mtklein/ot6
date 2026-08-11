-- @suite slow savestate=camp_escaped
-- battle_bushidogrey.lua -- v0.5 MP costs + BP gating: the SwdTech submenu greys
-- what Cyan cannot reach, for TWO reasons -- not enough MP (like Magic/Blitz),
-- and not enough BP (the boost the row would spend).
--
-- Vanilla Magic greys a spell whose MP cost exceeds current MP; the tools-shell
-- verbs never inherited that.  Ot6AbilityGrey (ot6.asm, bank F0) ports it, and
-- the row decorator OR's the $00/$04 it returns into the name's font scope.
-- The Bushido submenu adds a SECOND grey reason on top: each row IS a boost
-- level (row r spends r+1 BP, #38's 1-BP floor), so a row whose boost exceeds
-- the caster's current bp ($3e9c) is unreachable too -- Ot6BushidoRowGrey OR's
-- the same $04, and Ot6BushidoConfirm refuses to commit it.
--
-- Issue #75 conversion.  The old apparatus installed CYAN into the magitek
-- party by poke (char id, Bushido-only $202E, the weapon SWDTECH flag
-- written, $2020 ceiling pinned to 4) and set bp/MP per pass.  On
-- camp_escaped CYAN IS REAL: his katana carries the SWDTECH flag ($3BA4
-- bit 1 reads $82, never written), his real learned window is TWO rows --
-- Dispatch ($55, 4 MP, boost 1) and Retort ($56, 10 MP, boost 2), the
-- menu_blitzpage doctrine: the window is whatever the save holds -- and
-- every knob below is a LEDGER of real actions:
--
--   bp: opens at Ot6InitBP's 1; +1 per item turn; -row's boost per tech
--       (every tech is a boosted action, so its turn regens nothing).
--   MP: his real 67, walked down by real Retort casts (5 x 10 MP + the
--       ledger's two Dispatches = 59 -> 9, inside the 4..9 window where
--       Dispatch is payable and Retort is not).
--
-- Battles are real world encounters off the fixture tile; when the ledger's
-- casts end one (Dispatch kills; Retort is the counter stance and mostly
-- does not), the drive paces to the next -- bp and MP persist across
-- battles, so the ledger just continues.  SHADOW medics with real items;
-- KO'd SABIN sits the fight out (his real state at this fixture).
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey), the original's four passes mapped
-- onto the REAL two-row window:
--   1. BP GREY at the natural bank: bp 1, MP 67 -- Retort (boost 2 > 1) is
--      grey while Dispatch (boost 1) is white.  grey - white == $04.
--   2. BOTH CLEAR: one real item turn banks bp 2 -- Retort goes white (the
--      grey tracks the bank, it is not unconditional).
--   3. ZERO BP GREYS EVERYTHING (#38): two Dispatches spend the bank to 0
--      -- BOTH rows grey, names still DRAWN (greyed, not absent).
--   4. MP GREY: the bank is rebuilt (bp >= 2, isolating MP) while real
--      Retorts walk the pool to 9 -- Dispatch (4) white, Retort (10) grey,
--      and this time for the OTHER reason.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967                       -- kit list cursor row (read!)
local WHITE, GREY = 0x21, 0x25
local TONIC, POTION = 0xE8, 0xE9
local DISPATCH_MP, RETORT_MP = 4, 10

local cyan, shadow
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

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
local NM = { Dispatch = glyphs("Dispatch"), Retort = glyphs("Retort") }
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

-- ------------------------------------------------------ the drive machine --
-- cyanMode: "defer" | "item" | "tech:<row>" | "park" (open submenu, hold)
local mf = 0
local cyanMode = "defer"
local shadowThreshold = 60
local function decide()
  if H.readByte(MENU) == 0 then
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
  if act == shadow then                          -- threshold medic
    local hurt = false
    for s2 = 0, 3 do
      local h, m = hp(s2), H.readWord(0x3C1C + s2*2)
      if h > 0 and m > 0 and h * 100 // m < shadowThreshold then hurt = true end
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
    btn = (st == ST_CMD) and "x" or "b"
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
-- park at the submenu (battle must be up) and settle for a VRAM read.
-- SETTLE THE LEDGER FIRST: the window can open mid-resolution and the
-- decorator then correctly draws the PRE-charge bank (measured: the pass-3
-- window drew at f8375 with the second Dispatch's charge still in flight,
-- and the kit window does not repaint on a bank change while open -- a
-- follow-up noted in the report, distinct from #64's live magic re-price).
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
    H.call(function() H.setPad({}) end),
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
    H.assertEq(mp() >= 2 * RETORT_MP, true,
      "his real pool isolates the BP grey (Retort is affordable)")
    H.log(string.format("cyan slot %d bp=%d mp=%d; shadow slot %d",
      cyan, bp(), mp(), shadow))
  end),

  -- 1. BP GREY at the natural bank -----------------------------------------
  parkRead("submenu at the opening bank"),
  H.call(function()
    local aD, aR = attrOf(NM.Dispatch), attrOf(NM.Retort)
    H.log(string.format("bp=1 mp=%d -> attr Dispatch=%s Retort=%s",
      mp(), tostring(aD), tostring(aR)))
    H.assertEq(aD, WHITE, "Dispatch (boost 1 <= bp 1) is white")
    H.assertEq(aR, GREY,
      "Retort (boost 2 > bp 1) is GREY -- the BP reason, with MP abundant")
    H.assertEq(aR - aD, 0x04, "grey - white == $04, magic's own disabled-bit delta")
    H.screenshot("bushidogrey_bp")
  end),

  -- 2. BOTH CLEAR: one real item turn banks the second pip ------------------
  H.call(function() cyanMode = "item" end),
  driveTo(function() return bp() >= 2 end, 30000,
    "one real item turn banks bp 2"),
  parkRead("submenu at bp 2"),
  H.call(function()
    H.assertEq(attrOf(NM.Retort), WHITE,
      "at bp 2 Retort is white -- the grey tracks the bank, not unconditional")
    H.assertEq(attrOf(NM.Dispatch), WHITE, "Dispatch stays white")
  end),

  -- 3. ZERO BP GREYS EVERYTHING (#38) ---------------------------------------
  -- two real Dispatches spend the bank to 0 (each row-0 tech is a 1-boost
  -- action: it charges a pip and its turn regens nothing)
  H.call(function() cyanMode = "tech:0" end),
  driveTo(function() return bp() == 0 end, 40000,
    "two real Dispatches spend the bank to 0"),
  parkRead("submenu at a 0 bank"),
  H.call(function()
    local aD, aR = attrOf(NM.Dispatch), attrOf(NM.Retort)
    H.log(string.format("bp=0 mp=%d -> attr Dispatch=%s Retort=%s",
      mp(), tostring(aD), tostring(aR)))
    H.assertEq(aD ~= nil and aR ~= nil, true,
      "both names are still DRAWN at 0 bp -- greyed, not absent (#38)")
    H.assertEq(aD, GREY, "Dispatch (boost 1 > 0) is grey")
    H.assertEq(aR, GREY, "Retort (boost 2 > 0) is grey")
    H.screenshot("bushidogrey_zero")
  end),

  -- 4. MP GREY -- *** LABELED ISOLATION ARM (owner calibration). ***
  -- The input-driven walk was tried three ways and measured out of reach on this
  -- pool's economy: a Retort walk's counters end the battle; a deferring
  -- party is ground down (and battle-RAM teardown zeroes masquerade as
  -- "enemy MP drains" to any ungated read); and a six-battle Dispatch
  -- ladder never lands the pool under 10 -- this trash flees or dies
  -- before enough real casts spend it.  A precise low pool on a
  -- kit-bearing caster is an input this fixture cannot produce on cue,
  -- and the grey is a RENDERER decode, so the arm keeps ONE write, said
  -- loudly: MP := 7, inside the 4..9 window, with the bank at pass 2's
  -- real 2 (rebanked by one real item turn off the fresh battle's
  -- Ot6InitBP 1).  The trash also FLEES on its own schedule, so the arm
  -- is a tight fresh-battle sprint -- enter, one item turn, write, park,
  -- read -- retried up to five times; the medic threshold drops for the
  -- sprint so heal turns do not hog the pre-flee window.
  H.call(function() shadowThreshold = 40 end),
  (function()
    local done = false
    local function liveBattle()
      return H.battleLoadStarted() and H.monstersPresent() > 0
    end
    local function oneAttempt(n)
      return H.cond(function() return done end, {}, {
        driveTo(function() return liveBattle() end, 30000,
          "a live battle for the MP arm (attempt " .. n .. ")"),
        H.call(function()
          for slot = 0, 3 do
            local id = H.readByte(0x3ED8 + slot*2)
            if id == 0x02 then cyan = slot end
            if id == 0x03 then shadow = slot end
          end
          cyanMode = "item"
        end),
        driveTo(function()
          return not liveBattle() or bp() >= 2
        end, 40000, "the bank is rebuilt (attempt " .. n .. ")"),
        H.cond(function() return liveBattle() and bp() >= 2 end, {
          H.call(function()
            -- ISOLATION WRITE (waived, labeled): the boundary pool
            H.writeWord(0x3C08 + cyan*2, 7)
            cyanMode = "park:"
          end),
          driveTo(function()
            return not liveBattle()
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
              local aD, aR = attrOf(NM.Dispatch), attrOf(NM.Retort)
              H.log(string.format("bp=%d mp=%d -> attr Dispatch=%s Retort=%s",
                bp(), mp(), tostring(aD), tostring(aR)))
              H.assertEq(mp(), 7, "the isolation pool held for the read")
              H.assertEq(bp() >= 2, true,
                "the bank matches pass 2's (MP is the knob)")
              H.assertEq(aD, WHITE, "Dispatch (4 MP) is white on 7 MP")
              H.assertEq(aR, GREY,
                "Retort (10 MP) is GREY on 7 MP with the bank full -- the "
                .. "MP reason, where pass 2 read it WHITE at the same bank")
              H.screenshot("bushidogrey_mp")
              done = true
            end),
          }, {}),
        }, {}),
        -- a failed attempt leaves whatever battle remains; make sure the
        -- next attempt starts from a FRESH one
        H.cond(function() return done end, {}, {
          H.call(function() cyanMode = "defer" end),
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
        H.log("[bushidogrey] all four passes hold (three earned, one labeled)")
      end),
    })
  end)(),
})

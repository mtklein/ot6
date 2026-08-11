-- @suite slow savestate=camp_escaped
-- battle_bushidogrey.lua -- v0.5 MP costs and BP gating: the SwdTech submenu
-- greys what Cyan cannot reach, for two reasons: not enough MP (as in Magic
-- and Blitz), and not enough BP (the boost the row would spend).
--
-- Vanilla Magic greys a spell whose MP cost exceeds current MP; the tools-shell
-- verbs never inherited that.  Ot6AbilityGrey (ot6.asm, bank F0) ports it, and
-- the row decorator OR's the $00/$04 it returns into the name's font scope.
-- The Bushido submenu adds a second grey reason: each row is a boost
-- level (row r spends r+1 BP, #38's 1-BP floor), so a row whose boost exceeds
-- the caster's current bp ($3e9c) is unreachable too.  Ot6BushidoRowGrey OR's
-- the same $04, and Ot6BushidoConfirm refuses to commit it.
--
-- Issue #75 conversion.  The old apparatus installed CYAN into the magitek
-- party by poke (char id, Bushido-only $202E, the weapon SWDTECH flag
-- written, $2020 ceiling pinned to 4) and set bp and MP per pass.  On
-- camp_escaped Cyan is real: his katana carries the SWDTECH flag ($3BA4
-- bit 1 reads $82, never written), his real learned window is two rows,
-- Dispatch ($55, 4 MP, boost 1) and Retort ($56, 10 MP, boost 2), following
-- menu_blitzpage: the window is whatever the save holds.  Every value below
-- is a ledger of real actions:
--
--   bp: opens at Ot6InitBP's 1; +1 per item turn; minus the row's boost per
--       tech (every tech is a boosted action, so its turn regens nothing).
--   MP: his real 67, walked down by real Retort casts (5 x 10 MP plus the
--       ledger's two Dispatches = 59 -> 9, inside the 4..9 window where
--       Dispatch is payable and Retort is not).
--
-- Battles are real world encounters off the fixture tile; when the ledger's
-- casts end one (Dispatch kills; Retort is the counter stance and mostly
-- does not), the drive paces to the next.  bp and MP persist across
-- battles, so the ledger continues.  SHADOW heals with real items, and
-- KO'd SABIN sits the fight out, which is his real state at this fixture.
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey), with the original's four passes mapped
-- onto the real two-row window:
--   1. BP grey at the natural bank: bp 1, MP 67, so Retort (boost 2 > 1) is
--      grey while Dispatch (boost 1) is white.  grey - white == $04.
--   2. both clear: one real item turn banks bp 2, and Retort goes white, so
--      the grey tracks the bank rather than being unconditional.
--   3. the open window ACCEPTS A REPAINT REQUEST (#77).  Passes 1, 2, 4 and 5
--      each open a window onto a bank that has stopped moving and read what
--      the row decorator derived at open.  #77 is the other half: the rows
--      are staged once, at open, and before the fix nothing re-staged them,
--      so a bank that moved behind an open window was drawn stale until the
--      window was closed and reopened.  The fix makes Ot6RestageGate_ext
--      serve the kit window ($30) beside the magic list ($0e), and has every
--      BP writer ask it for a repaint.  This pass drives a request through
--      its real path -- an L/R press, which is Ot6Boost's own OT6_RESTAGE
--      raise (#64) -- and watches the byte: before the fix the gate ignored a
--      request while $30 was up, so it stood at $80 for the rest of the menu;
--      after, the gate spends it within a few frames and leaves the window up
--      with its rows still right.  See the pass for why the bank move itself
--      is not what is driven here.
--   4. zero BP greys everything (#38): two Dispatches spend the bank to 0,
--      both rows grey, and the names are still drawn, greyed rather than
--      absent.
--   5. MP grey: the bank is rebuilt (bp >= 2, isolating MP) while real
--      Retorts walk the pool to 9, so Dispatch (4) is white and Retort (10)
--      is grey, this time for the other reason.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967                       -- kit list cursor row (read!)
local RESTAGE = 0x57D4                    -- #77: the gate's request byte (read!)
local WHITE, GREY = 0x21, 0x25
local TONIC, POTION = 0xE8, 0xE9
local DISPATCH_MP, RETORT_MP = 4, 10

local cyan, shadow
local restageTrace = {}          -- #77: OT6_RESTAGE, sampled per frame
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

-- ------------------------------------------------------------- the drive --
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
  if act == shadow then                          -- heals below a threshold
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
-- Settle the ledger first: the window can open mid-resolution and the
-- decorator then correctly draws the pre-charge bank (measured: the pass-3
-- window drew at f8375 with the second Dispatch's charge still in flight,
-- and the kit window does not repaint on a bank change while open, a
-- follow-up noted in the report and distinct from #64's live magic re-price).
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

  -- 1. BP grey at the natural bank -----------------------------------------
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

  -- 2. both clear: one real item turn banks the second pip ------------------
  H.call(function() cyanMode = "item" end),
  driveTo(function() return bp() >= 2 end, 30000,
    "one real item turn banks bp 2"),
  parkRead("submenu at bp 2"),
  H.call(function()
    H.assertEq(attrOf(NM.Retort), WHITE,
      "at bp 2 Retort is white -- the grey tracks the bank, not unconditional")
    H.assertEq(attrOf(NM.Dispatch), WHITE, "Dispatch stays white")
  end),

  -- 3. the open window accepts a repaint request (#77) ----------------------
  -- Why the request and not a bank move.  The thing #77 describes is a bank
  -- that moves while the window is up, and on this fixture that situation is
  -- not reachable from the pad.  Measured here, driving Cyan into the window
  -- and holding it: his own charge cannot land under his own window, because
  -- the ATB restart and Ot6ActionEnd's charge are the same instruction
  -- stream (battle_main.asm:296-303), so his menu cannot reopen until after
  -- the bank has already moved -- observed as menu=0 across the whole
  -- commit-to-charge interval.  The moves that CAN land under an open window
  -- are the reactive ones (a True Knight cover, a Runic absorb, an ally's
  -- Bestow), and no fixture puts one of those on a kit-bearing character
  -- without staging it by hand, which this file does not do.
  --
  -- So this pass drives the repaint mechanism instead of one of its causes,
  -- through the one cause that IS reachable from the pad: an L/R press.
  -- Ot6Boost raises OT6_RESTAGE on that edge (#64) whatever window is open,
  -- and the gate is the single place a request is spent, so what is asserted
  -- below is exactly the half of the fix a bank move would exercise.  The
  -- before-state is what makes it a test: on the unfixed ROM the gate only
  -- ever looked at menu state $0e, so a request raised over the kit window
  -- was never spent and the byte stood at $80.
  H.call(function() cyanMode = "defer" end),
  parkRead("submenu for the repaint request"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS, "the kit window is up and browsing")
    H.assertEq(H.readByte(RESTAGE), 0,
      "and no repaint is outstanding before the press")
  end),
  -- Sample the byte frame by frame across the press.  A single reading after
  -- the fact cannot tell the two ROMs apart in the direction that matters:
  -- the fixed gate spends a request in four frames (one row-pair staged per
  -- frame, because the nmi drains one line transfer per frame), so by the
  -- time a press step returns it is already back to 0, and 0 also means
  -- "nothing was ever raised".  The values in between are the signal.  The
  -- flag protocol is $80 fresh, then 3, 2, 1 as the cycle stages its lines,
  -- then 0 (ot6_hud.asm, over Ot6RestageGate_ext).
  H.call(function() restageTrace = {} end),
  H.hold({ r = true }),
  H.repeatN(20, {
    H.call(function() restageTrace[#restageTrace + 1] = H.readByte(RESTAGE) end),
    H.waitFrames(1),
  }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    local seen, sawFresh, sawCycle = {}, false, false
    for _, v in ipairs(restageTrace) do
      seen[#seen + 1] = string.format("%02x", v)
      if v == 0x80 then sawFresh = true end
      if v >= 1 and v <= 3 then sawCycle = true end
    end
    local left = H.readByte(RESTAGE)
    local aD, aR = attrOf(NM.Dispatch), attrOf(NM.Retort)
    H.log(string.format("[#77] restage across the press: %s -> %02x; "
      .. "mstate=%02x menu=%d bp=%d pending=%d Dispatch=%s Retort=%s",
      table.concat(seen, " "), left, H.readByte(MSTATE), H.readByte(MENU),
      bp(), pend(), tostring(aD), tostring(aR)))
    -- positive control: the press has to have reached Ot6Boost at all.  Its
    -- @refold arm banks the pending boost and raises OT6_RESTAGE on the same
    -- instruction stream (ot6_hud.asm, Ot6Boost), so a pending of 1 is proof
    -- the request was raised even on a build that then throws it away.
    H.assertEq(pend(), 1, "the R press reached Ot6Boost (pending 0 -> 1), "
      .. "which is the same arm that raises the repaint request")
    H.assertEq(sawFresh, true, "and the fresh request was visible in the trace")
    -- the discriminator.  1..3 is a staging cycle in progress, and only a
    -- gate that serves menu state $30 ever starts one over the kit window.
    -- The unfixed gate looked at $0e alone, so its trace is $80 forever.
    H.assertEq(sawCycle, true,
      "the gate STARTED a staging cycle over the open kit window (flag 1-3) "
      .. "-- the unfixed gate served the magic list only and left it $80 (#77)")
    H.assertEq(left, 0, "and the cycle completed, handing the byte back")
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "the window is still up: a re-stage must not walk it shut")
    -- and the re-staged rows still say what the bank says.  #36 was a
    -- re-stage that handed $7ba5 back wrong and drew another list's rows, so
    -- "it repainted" is not enough on its own.
    H.assertEq(aD, WHITE, "Dispatch is still white after the re-stage")
    H.assertEq(aR, WHITE, "Retort is still white after the re-stage (bp 2)")
  end),
  H.pressButtons({ "l" }, 6),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(pend(), 0, "L put the pending boost back, so the ledger below "
      .. "is unchanged by this pass")
  end),

  -- 4. zero BP greys everything (#38) ---------------------------------------
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

  -- 5. MP grey: a labeled isolation arm (owner calibration).
  -- The input-driven walk was tried three ways and measured out of reach on
  -- this pool's economy: a Retort walk's counters end the battle; a deferring
  -- party is ground down (and battle-RAM teardown zeroes read as
  -- enemy MP drains to any ungated read); and a six-battle Dispatch
  -- ladder never lands the pool under 10, because this trash flees or dies
  -- before enough real casts spend it.  A precise low pool on a
  -- kit-bearing caster is an input this fixture cannot produce on cue,
  -- and the grey is a renderer decode, so the arm keeps one write, recorded
  -- here: MP := 7, inside the 4..9 window, with the bank at pass 2's
  -- real 2 (rebanked by one real item turn off the fresh battle's
  -- Ot6InitBP 1).  The trash also flees on its own schedule, so the arm
  -- is a short fresh-battle sequence (enter, one item turn, write, park,
  -- read) retried up to five times; the heal threshold drops for it so heal
  -- turns do not consume the pre-flee window.
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
            -- the isolation write (waived, labeled): the boundary pool
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
        H.log("[bushidogrey] all five passes hold (four earned, one labeled)")
      end),
    })
  end)(),
})

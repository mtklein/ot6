-- @suite slow savestate=camp_escaped
-- battle_bushidogrey.lua -- MP costs and BP gating: the SwdTech submenu
-- greys what Cyan cannot reach, for two reasons: not enough MP (as in Magic
-- and Blitz), and not enough BP (the boost the row would spend).

--   bp: opens at Ot6InitBP's 1; +1 per item turn; minus the row's boost per
--       tech (every tech is a boosted action, so its turn regens nothing).
--       It opens at 1 in EVERY battle, so a ledger that spans a battle
--       boundary is not a ledger -- every bank read below is gated on the
--       battle it was built in (passes 2-5 are retry ladders).
--   MP: his real pool (92 on the fighting lineage), spent 4 a Dispatch and
--       10 a Retort.

-- Battles are real world encounters off the fixture tile; when the ledger's
-- casts end one (Dispatch kills; Retort is the counter stance and mostly
-- does not), the drive paces to the next.  MP persists across battles, the
-- bank does not.  SHADOW heals with real items.
--
-- The fighting lineage's camp_escaped packs carry a Berserk special.  Once
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
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local KROW = 0x8967                       -- kit list cursor row (read!)
local RESTAGE = 0x57D4                    -- the gate's request byte (read!)
local WHITE, GREY = 0x21, 0x25
local TONIC, POTION = 0xE8, 0xE9
local DISPATCH_MP, RETORT_MP = 4, 10

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
local function cyanStatusStr()
  return string.format("st1=%02x st2=%02x", H.readByte(0x3EE4 + cyan*2),
    H.readByte(0x3EE5 + cyan*2))
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
local NM = { Dispatch = glyphs("Dispatch"), Retort = glyphs("Retort"),
             Slash = glyphs("Slash") }
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
    H.assertEq(mp() >= 2 * RETORT_MP, true,
      "his real pool isolates the BP grey (Retort is affordable)")
    H.log(string.format("cyan slot %d bp=%d mp=%d; shadow slot %d",
      cyan, bp(), mp(), shadow))
  end),

  -- 1. BP grey at the natural bank -----------------------------------------
  parkRead("submenu at the opening bank"),
  H.call(function()
    local aD, aR, aS = attrOf(NM.Dispatch), attrOf(NM.Retort), attrOf(NM.Slash)
    H.log(string.format("bp=1 mp=%d -> attr Dispatch=%s Retort=%s Slash=%s",
      mp(), tostring(aD), tostring(aR), tostring(aS)))
    H.assertEq(aD, WHITE, "Dispatch (boost 1 <= bp 1) is white")
    H.assertEq(aR, GREY,
      "Retort (boost 2 > bp 1) is GREY -- the BP reason, with MP abundant")
    H.assertEq(aS, GREY,
      "Slash (boost 3 > bp 1) is GREY too -- the third row he learned at "
      .. "level 12, on the same BP reason")
    H.assertEq(aR - aD, 0x04, "grey - white == $04, magic's own disabled-bit delta")
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
        driveTo(function() return liveBattle() end, 30000,
          "a live battle for the bp-2 arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          cyanMode = "item"
          H.log(string.format("  [bp-2 arm %d] pack %s; cyan slot %d bp=%d %s",
            n, packStr(), cyan, bp(), cyanStatusStr()))
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
              H.assertEq(attrOf(NM.Retort), WHITE,
                "at bp 2 Retort is white -- the grey tracks the bank, not "
                .. "unconditional")
              H.assertEq(attrOf(NM.Dispatch), WHITE, "Dispatch stays white")
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
                table.concat(seen, " "), left, H.readByte(MSTATE),
                H.readByte(MENU), bp(), pend(), tostring(aD), tostring(aR)))
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
              H.assertEq(left, 0, "and the cycle completed, handing the byte back")
              H.assertEq(H.readByte(MSTATE), ST_TOOLS,
                "the window is still up: a re-stage must not walk it shut")
              H.assertEq(aD, WHITE, "Dispatch is still white after the re-stage")
              H.assertEq(aR, WHITE,
                "Retort is still white after the re-stage (bp 2)")
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

  -- Retort is the lever.  It costs boost 2, so one cast takes a bank of 2
  -- straight to 0, and it is the counter stance rather than a hit, so it
  -- does not end the fight the way a Dispatch does.  The read then checks
  -- the bank it was staged with, not the bank it was driven to, and the arm
  -- is a three-attempt ladder (the house limit) because the trash can still
  -- flee or kill the fight out from under an attempt.
  (function()
    local done = false
    local function liveBattle()
      return H.battleLoadStarted() and H.monstersPresent() > 0
    end
    local function oneAttempt(n)
      return H.cond(function() return done end, {}, {
        driveTo(function() return liveBattle() end, 30000,
          "a live battle for the 0-bank arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          cyanMode = "item"
          H.log(string.format("  [0-bank arm %d] pack %s; cyan slot %d bp=%d %s",
            n, packStr(), cyan, bp(), cyanStatusStr()))
        end),
        driveTo(function()
          return not liveBattle() or cyanLostMenu() or bp() >= 2
        end, 40000, "the bank reaches 2 (attempt " .. n .. ")"),
        H.cond(function()
          return liveBattle() and cyanCanMenu() and bp() >= 2
        end, {
          H.call(function() cyanMode = "tech:1" end),
          driveTo(function()
            return not liveBattle() or cyanLostMenu() or bp() == 0
          end, 40000,
            "one real Retort (boost 2) empties the bank (attempt " .. n .. ")"),
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
                local aD = attrOf(NM.Dispatch)
                local aR = attrOf(NM.Retort)
                local aS = attrOf(NM.Slash)
                H.log(string.format("bp=%d pend=%d banks=%d/%d/%d/%d mp=%d " ..
                  "-> attr Dispatch=%s Retort=%s Slash=%s",
                  bp(), pend(),
                  H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0),
                  H.readByte(0x3EA2), mp(),
                  tostring(aD), tostring(aR), tostring(aS)))
                H.assertEq(aD ~= nil and aR ~= nil and aS ~= nil, true,
                  "all three names are still DRAWN at 0 bp -- greyed, not "
                  .. "absent (#38)")
                H.assertEq(aD, GREY, "Dispatch (boost 1 > 0) is grey")
                H.assertEq(aR, GREY, "Retort (boost 2 > 0) is grey")
                H.assertEq(aS, GREY, "Slash (boost 3 > 0) is grey")
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
        driveTo(function() return liveBattle() end, 30000,
          "a live battle for the MP arm (attempt " .. n .. ")"),
        H.call(function()
          refindSlots()
          cyanMode = "item"
          H.log(string.format("  [MP arm %d] pack %s; cyan slot %d bp=%d %s",
            n, packStr(), cyan, bp(), cyanStatusStr()))
        end),
        driveTo(function()
          return not liveBattle() or cyanLostMenu() or bp() >= 2
        end, 40000, "the bank is rebuilt (attempt " .. n .. ")"),
        H.cond(function()
          return liveBattle() and cyanCanMenu() and bp() >= 2
        end, {
          H.call(function()
            -- the isolation write (waived, labeled): the boundary pool
            H.writeWord(0x3C08 + cyan*2, 7)
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
          H.call(function()
            H.log(string.format("  [MP arm %d] void: live=%s menuable=%s "
              .. "bp=%d %s -- draining the battle", n,
              tostring(liveBattle()), tostring(cyanCanMenu()), bp(),
              cyanStatusStr()))
            cyanMode = "defer"
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

-- @suite slow
-- battle_slots.lua -- boost-tiered Slot (Setzer): on chance verbs boost
-- buys certainty in the verb's own terms.  Slot's terms are vanilla's
-- single rig byte (w7e6179, one Rand at the first A press) and the drift
-- and avoid code it drives:
--   blessed icon (rig & SlotRateTbl[icon] == 0): reels 2 and 3 drift up to
--     w7e617d extra icons toward the pair or triple (vanilla budget 4);
--   cursed icon: no help, and a landed pair gets w7e617c bit 7, so reel 3
--     refuses to stop on the completing icon (the rigged miss).

-- The hooks under test:
--   Ot6SlotRig    -- stores the spin's tier ($57ba) at the first press and
--                    stores the rig byte: untouched at 0-1 bp, forced 0 (or
--                    $3c under the $2f49.2 joker-doom battle gate) at 2-3 bp.
--   Ot6SlotDrift  -- blessed drift budget: 4 to the byte below 3 bp, $ff at
--                    3 bp (longer than the 16-icon strip).
--   Ot6SlotMiss   -- the rigged miss: vanilla avoid-mark at 0 bp, bought off
--                    at 1+ bp.  A 7-pair under the joker gate stays refused.
--   Ot6SlotCommit -- re-banks the stored tier into OT6_BOOST_REVEALED at
--                    the commit press, so Ot6ActionEnd charges exactly the
--                    tier the reels were spun with.
--   Ot6BoostDmg's $0f gate: slot attacks never get the damage multiplier.

-- battle_slotsboot covers tier 0 and tier 3 end to end on a natural
-- checkpoint boot.  This file covers the rest, in two parts:
--
--   The input-driven half (no writes): a second natural boot of the
--   terra-returned-v1 SRAM checkpoint, driving the two tiers slotsboot
--   leaves unchecked with real R presses on earned bp:
--     H1 (1 bp): store = 1, the 1-bp charge with regen skipped, and the
--        commit re-bank.  Tier 1 leaves the drawn rig alone, so no rig
--        value is asserted here; that half lives in the quarantine lab
--        where the byte can be planted.
--     H2 (2 bp): store = 2, the rig forced benevolent ($00, or $3c under a
--        real joker gate), read rather than written, with reel-2 help
--        blessed toward the icon reel 1 stopped on, vanilla's 4-icon
--        budget stored by the $f0 hook, and the 2-bp charge.  H2 is played
--        in a SECOND drawn battle, since a bank does not cross a battle
--        boundary (Ot6InitBP re-seeds 1): the second fight opens at 1 bp,
--        one plain spin banks the 2, and both fights are two resolutions.
--
--   Labeled quarantine lab: the icon and rig-byte arms.  No player input
--   selects a reel icon: the reels free-run at frame rate and a press
--   stops them wherever the frame parity fell, so a cursed pair of 3s, the
--   same triple at tier 0 and tier 3 (the exemption A/B), and a 7-pair
--   under the joker gate cannot be produced on cue by any input-driven
--   drive.  Those arms stay below as one labeled block on the old
--   entry-point install rig: rig bytes planted, reel positions parked,
--   stopped reels restarted to replay the driver's boundary walk, and
--   monsters staged so nothing dies mid-observation.  Arms: T0
--   byte-vanilla and the rigged miss; T1 the miss bought off (same drive,
--   one pending byte different); T2 the drift walk replayed on a fresh
--   budget; T3b the exemption A/B damage ratio on identical triples; T3j
--   the joker gate refusing a bought 7-pair at 3 bp.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local RIG, HELP1, MARK, DRIFT = 0x6179, 0x617B, 0x617C, 0x617D
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }   -- reel 1/2/3 position (icon = >>4)
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }   -- reel stopped flags
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }  -- press stores 1/2/3
local SLOTTIER, JOKER = 0x57BA, 0x2F49
local SETZER, NONE = 0x09, 0xFF
local PARTY = { 0, 1, 2 }
local function ENT_M(s) return 8 + s * 2 end
local function bp(s)   return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end

-- the reel strips (SlotReelTbl, btlgfx_main.asm @a800), mirrored so asserts
-- can name icons: icon = strip[pos >> 4]
local REEL = {
  { 0,4,5,3,4,5,2,5,1,4,5,3,5,2,3,1 },
  { 0,4,1,5,3,4,1,5,4,3,2,5,4,3,2,5 },
  { 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5 },
}
local function icon(r) return REEL[r][(H.readByte(POS[r]) >> 4) + 1] end

local actor, msPresent = nil, {}
local actEnd, actEndF, actEndCmd = {}, {}, {}  -- entity -> actions ended (Ot6ActionEnd) / last frame / last $b5
local results = {}      -- $2bb0-row writes from bank $c1 = the slot commit
local driftW = {}       -- w7e617d writes: { k = writer bank, v = value }
local mulHits = {}      -- Ot6BoostDmg multiplier writes during cmd $0f

local function lastF0Drift()
  for i = #driftW, 1, -1 do
    if driftW[i].k == 0xF0 then return driftW[i].v end
  end
  return nil
end

local function armWatches()
  -- the commit press writes the result index to $2bb0,y from bank $c1
  emu.addMemoryCallback(function(a, v)
    pcall(function()
      local s = emu.getState()
      if s["cpu.k"] == 0xC1 then results[#results + 1] = { addr = a, v = v } end
    end)
  end, emu.callbackType.write, 0x7E2BB0, 0x7E2BC9)
  -- who writes the drift budget, and what: the hook stores from $f0, the
  -- vanilla inline store / the driver's decrements from $c1
  emu.addMemoryCallback(function(_, v)
    pcall(function()
      local s = emu.getState()
      driftW[#driftW + 1] = { k = s["cpu.k"], v = v }
    end)
  end, emu.callbackType.write, 0x7E617D, 0x7E617D)
  -- the exemption watch (cheap guards first)
  local BOOSTDMG = H.sym("Ot6BoostDmg")
  emu.addMemoryCallback(function(_, v)
    if not (v > 0 and H.readByte(0xB5) == 0x0F) then return end
    pcall(function()
      local s = emu.getState()
      local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
      if pc >= BOOSTDMG and pc < BOOSTDMG + 0xA0 then
        mulHits[#mulHits + 1] = v
      end
    end)
  end, emu.callbackType.write, 0x7E3ECE, 0x7E3ECE)
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ========================================================================
-- The input-driven half: the natural checkpoint boot (battle_slotsboot's
-- pattern)
-- ========================================================================
local slotOf = {}
local function ent() return actor * 2 end
local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

-- The other members' windows.  Nobody but Setzer attacks (the formation
-- has to stand through two resolutions per battle), so each of their
-- turns is care or a Defend, chosen once when the window opens:
--   * a dead member is raised with a Fenix Down, Setzer first, one raise in
--     flight at a time;
--   * else a living member below CARE_PCT of max HP gets a Potion (a Tonic
--     when the bag has no Potion), Setzer first, then the most hurt, one
--     heal in flight per member;
--   * else Defend (RIGHT opens the Def. side window, A commits it): the
--     member guards while Setzer's spin is queued, and the window closes.
-- Before this the windows were handed on with X or left open, and a draw
-- that wore Setzer down left him spinning at 34/556 HP with nobody to heal
-- him: at MesenCE 2.2.1 shift 0 he died with the tier-2 spin committed and
-- unresolved, and the drive waited out its budget on LOCKE's open window
-- while the party bled out (build/attempts/wt/suites-2.2.1/).
local CARE_PCT = 50
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local CMD_ITEM, ST_CMD, ST_ITEM, ST_TGT, ST_DEF = 0x01, 0x05, 0x0A, 0x38, 0x27
local BATTINV, ITEMSCR, ITEMROW = 0x2686, 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local function chid(s) return H.readByte(0x3ED8 + s * 2) end
local function php(s) return H.readWord(0x3BF4 + s * 2) end
local function pmax(s) return H.readWord(0x3C1C + s * 2) end
local function seated(s) return chid(s) ~= 0xFF and pmax(s) > 0 end
local function partyLine()
  local t = {}
  for s = 0, 3 do
    if seated(s) then
      t[#t + 1] = string.format("%02X:%d/%d bp%d", chid(s), php(s), pmax(s), bp(s))
    end
  end
  return table.concat(t, " ")
end
local function invIdx(item)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == item and H.readByte(BATTINV + i * 5 + 3) > 0 then
      return i
    end
  end
end
local function invCount(item)
  local i = invIdx(item)
  return i and H.readByte(BATTINV + i * 5 + 3) or 0
end
local raising = nil                       -- { e, f }: a Fenix Down in flight
local healing = {}                        -- e -> { f, hp }: a heal in flight
local cared = { heal = 0, raise = 0 }
local W = { actor = nil, n = 0, plan = nil, tgt = nil, idx = nil, via = nil }
local function carePlan(a)
  if raising and (php(raising.e) > 0 or H.frame - raising.f > 900) then raising = nil end
  for e, h in pairs(healing) do
    if php(e) > h.hp or php(e) == 0 or H.frame - h.f > 900 then healing[e] = nil end
  end
  local order = {}
  for s = 0, 3 do if seated(s) and chid(s) == SETZER then order[#order + 1] = s end end
  for s = 0, 3 do if seated(s) and chid(s) ~= SETZER then order[#order + 1] = s end end
  local itemCell = nil
  for r = 0, 3 do
    if H.readByte(0x202E + a * 12 + r * 3) == CMD_ITEM then itemCell = r end
  end
  if itemCell == nil then return "defend" end
  if raising == nil and invIdx(FENIX) then
    for _, s in ipairs(order) do
      if php(s) == 0 then return "raise", s, invIdx(FENIX), itemCell end
    end
  end
  local item = invIdx(POTION) and POTION or (invIdx(TONIC) and TONIC or nil)
  if item == nil then return "defend" end
  local pick, pickPct = nil, nil
  for i, s in ipairs(order) do
    local pct = php(s) * 100 // math.max(pmax(s), 1)
    if php(s) > 0 and pct < CARE_PCT and healing[s] == nil then
      -- Setzer first; otherwise the most hurt
      if pick == nil or (chid(pick) ~= SETZER and pct < pickPct) then
        pick, pickPct = s, pct
      end
    end
  end
  if pick then return "heal", pick, invIdx(item), itemCell, item end
  return "defend"
end
-- One frame of another member's window (MENU open, ACTOR not Setzer).
local function otherWindow()
  local a = H.readByte(ACTOR) & 3
  -- a new window (another actor, or the same one after the menu closed)
  -- chooses its plan
  if W.actor ~= a then
    W.actor, W.via, W.n = a, nil, 0
    W.plan, W.tgt, W.idx, W.cell, W.item = carePlan(a)
    if W.plan ~= "defend" then
      H.log(string.format("[care] f%d actor %d (%02X): %s slot %d (%02X) with $%02X " ..
        "(%d in the bag) | party %s", H.frame, a, chid(a), W.plan, W.tgt, chid(W.tgt),
        W.plan == "raise" and FENIX or W.item,
        invCount(W.plan == "raise" and FENIX or W.item), partyLine()))
    end
  end
  W.n = W.n + 1
  local ph = W.n % 10
  local st = H.readByte(MSTATE)
  local function tap(b) H.setPad(ph < 5 and { [b] = true } or {}) end
  if W.plan == "defend" then
    if st == ST_CMD then
      if pend(a) > 0 then tap("l") else tap("right") end
    elseif st == ST_DEF then tap("a")
    elseif st == 0x0A or st == 0x30 or st == 0x16 or st == 0x24 or st == 0x0E
        or st == ST_TGT then tap("b")
    else H.setPad({}) end
    return
  end
  if st == ST_CMD then
    local cur = H.readByte(0x890F + a)
    if cur ~= W.cell then tap(cur < W.cell and "down" or "up"); return end
    if pend(a) > 0 then tap("l"); return end             -- care goes unboosted
    W.via = "cmd"
    tap("a")
  elseif st == ST_ITEM then
    local cur = H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
    if cur ~= W.idx then tap(cur < W.idx and "down" or "up"); return end
    W.via = "item"
    tap("a")
  elseif st == ST_TGT then
    if W.via ~= "item" and W.via ~= "confirmed" then tap("b"); return end
    local chars = H.readByte(TGTCHARS)
    if H.readByte(TGTMONS) ~= 0 or chars == 0 then
      tap(H.battleLayout().toChars[1])
      return
    end
    if chars ~= (1 << W.tgt) then
      local cur = 0
      for s = 3, 0, -1 do if chars & (1 << s) ~= 0 then cur = s end end
      tap(cur < W.tgt and "down" or "up")
      return
    end
    if ph < 5 and W.via == "item" then
      W.via = "confirmed"
      if W.plan == "raise" then raising = { e = W.tgt, f = H.frame }
      else healing[W.tgt] = { f = H.frame, hp = php(W.tgt) } end
      cared[W.plan] = cared[W.plan] + 1
      H.log(string.format("[care] f%d actor %d confirms the %s on slot %d (#%d)",
        H.frame, a, W.plan, W.tgt, cared[W.plan]))
    end
    tap("a")
  elseif st == 0x30 or st == 0x16 or st == 0x24 or st == 0x27 or st == 0x0E then
    tap("b")                                  -- a window care never means to be in
  else
    H.setPad({})
  end
end
local function otherWindowsReset() W.actor, W.plan = nil, nil end

-- Setzer falling.  A character who falls with a command queued never runs
-- it: measured at MesenCE 2.2.1 shift 0 (the old suite), Setzer committed
-- the tier-2 spin at 34/556 HP and died at f11701 with pend 2 / bp 2, which
-- stayed so to the timeout.  And the bank does not survive it: in a
-- fault-injected lab (his HP written to 1 after the H2 commit; not play)
-- the cancelled spin reached Ot6ActionEnd as CmdNoEffect while he lay
-- dead and was charged there, pend 2 / bp 2 -> 0
-- (build/attempts/wt/suites-2.2.1/).  So a fall costs that battle its
-- tiers, and battleHalf plays a fresh one.
local lostBattle, lostBattles, MAX_LOST = false, 0, 3
local function watchFall(tag)
  if not lostBattle and actor and H.battleLoadStarted() and seated(actor)
     and php(actor) == 0 then
    lostBattle = true
    lostBattles = lostBattles + 1
    H.log(string.format("[slots] f%d %s: SETZER fell (pend=%d bp=%d) -- this " ..
      "battle is lost to the test (#%d); raising him, then a fresh battle | " ..
      "party %s", H.frame, tag, pend(actor), bp(actor), lostBattles, partyLine()))
  end
  return lostBattle
end
-- One frame of the party while Setzer waits on a queued spin or lies
-- fallen: messages paged with A, the other members' windows played
-- (otherWindow), his own window left alone.
local function partyTurn()
  if H.readByte(MENU) == 0 then
    otherWindowsReset()
    H.setPad(H.frame % 8 < 4 and { a = true } or {})
  elseif H.readByte(ACTOR) ~= actor then
    otherWindow()
  else
    otherWindowsReset()
    H.setPad({})
  end
end

-- wait for a character's menu; the other members' windows get care or a
-- Defend (otherWindow, above), and a fall ends the wait (watchFall)
local stallShot = nil
local function menuFor(charId, what)
  local ph = 0
  local hb = -600
  local started = nil
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.withReset(H.driveUntil(function() return up() or lostBattle end, 30000, {
    H.call(function()
      ph = ph + 1
      started = started or H.frame
      watchFall(what)
      -- Where is the machine?  A menu that never arrives is usually a battle
      -- that has ended or a party that is dying, and neither says so on its
      -- own: the drive just stops logging until the budget runs out.
      if H.frame - hb >= 600 then
        hb = H.frame
        local hps, st1, st4, atb = {}, {}, {}, {}
        for s = 0, 3 do
          hps[#hps+1] = tostring(H.readWord(0x3BF4 + s*2))
          st1[#st1+1] = string.format("%02x", H.readByte(0x3EE4 + s*2))
          st4[#st4+1] = string.format("%02x", H.readByte(0x3EF4 + s*2))
          atb[#atb+1] = string.format("%02x", H.readByte(0x3218 + s*2))
        end
        H.log(string.format("  [%s hb f%d] live=%s menu=%02x actor=%d "
          .. "mstate=%02x mons=%d hp=%s st1=%s st4=%s atb=%s", what, H.frame,
          tostring(H.battleLoadStarted()), H.readByte(MENU),
          H.readByte(ACTOR), H.readByte(MSTATE), H.monstersPresent(),
          table.concat(hps, "/"), table.concat(st1, "/"),
          table.concat(st4, "/"), table.concat(atb, "/")))
        -- One picture of a wait that has clearly stalled: the battle may
        -- have been won already, with no menu ever going to arrive.
        if stallShot == nil and H.frame - started > 3000 then
          stallShot = true
          H.screenshot("slots_stall")
        end
      end
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        otherWindow()
      else
        otherWindowsReset()
        H.setPad({})
      end
    end),
  }, what), function() ph, started = 0, nil; otherWindowsReset() end)
end

-- Setzer's window is up: the menu open flag with him as the actor.  The
-- reels are that window in state $08 (btlgfx UpdateMenuState_08).
local function setzerWindow()
  return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[SETZER]
end
local function reelsLive()
  return setzerWindow() and H.readByte(MSTATE) == 0x08
end

-- Bank boost pips with real R presses, by feedback.  Ot6Boost stores a
-- press ($57d2) only on frames it runs, and it does not run while an
-- enemy's hit animation plays over the command window: on this ROM the
-- second of two fixed-cadence presses fell on such a frame and banked
-- nothing (measured 2026-09: "two real R presses bank pending 2: got 1").
-- A person keeps pressing until the pip shows; so does this.  Taps only
-- while Setzer's window is up, stops the moment the count reads `want`,
-- says how many taps it took, and fails on its own if a dozen taps do
-- not get there.  The caller's assertion on the count stays.
local function bankPending(want, what)
  local taps = 0
  return H.withReset(H.repeatN(1, {
    H.driveUntil(function() return lostBattle or pend(actor) >= want end, 1500, {
      H.call(function()
        if taps >= 12 then
          error(string.format("%s: R tapped %d times and pending still reads "
            .. "%d (want %d) -- the press is not being stored at all",
            what, taps, pend(actor), want), 0)
        end
        H.assertEq(setzerWindow(), true,
          what .. ": setzer's command window is up for the R tap")
        taps = taps + 1
      end),
      H.pressButtons({ "r" }, 6), H.waitFrames(20),
    }, what .. ": R taps bank pending " .. want),
    H.call(function()
      if want == 0 and taps == 0 then return end
      H.log(string.format("%s: pending %d after %d R tap(s)%s", what,
        pend(actor), taps, taps > want and string.format(
          " (%d landed on frames Ot6Boost did not run)", taps - want) or ""))
    end),
  }), function() taps = 0 end)
end

-- Open the Slot window from Setzer's command window: the cursor onto the
-- Slot row (verified against the live cursor cell), A, and the live reel
-- state.  Every press is made only while the window is still his, and
-- each drive also ends when it is not, so a window the battle takes away
-- here is answered by the caller rather than tapped at.
local function openSlotWindow(what)
  local row = nil
  return H.repeatN(1, {
    H.call(function()
      row = nil
      for r = 0, 3 do
        if H.readByte(0x202E + slotOf[SETZER] * 12 + r * 3) == 0x0F then
          row = r
        end
      end
      H.assertEq(row ~= nil, true, "setzer's menu offers Slot")
    end),
    H.driveUntil(function()
      return not setzerWindow() or H.readByte(0x890F + slotOf[SETZER]) == row
    end, 900, {
      H.call(function()
        local cur = H.readByte(0x890F + slotOf[SETZER])
        if not setzerWindow() then H.setPad({})
        elseif cur < row then H.setPad({ down = true })
        elseif cur > row then H.setPad({ up = true }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(10),
    }, what .. ": cursor on the Slot row"),
    H.driveUntil(function()
      return not setzerWindow()
        or (H.readByte(MSTATE) == 0x08 and H.readByte(PRESS[1]) == 0
            and H.readByte(STOP[1]) == 0)
    end, 1500, {
      H.call(function() H.setPad(setzerWindow() and { a = true } or {}) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(20),
    }, what .. ": slot window open"),
    H.cond(reelsLive, { H.waitFrames(12) }, {}),
  })
end

-- Walk the plain until an encounter worth spinning in turns up, then take
-- the party's slots off it.  Used twice: once for the battle H1 is played
-- in, once for the fresh battle H2 needs (see the comment at that call).
-- The floor is two live bodies and 900 total max HP, which is what a
-- formation needs to still be standing after two Slot resolutions.
local function drawBattle(tag, tries)
  local steps = { H.call(function() H.vars.suitable = false end) }
  local pattern = { "down", "down", "right", "right", "down", "down",
                    "left", "left" }
  for n = 1, tries do
    local w = {
      (function()
        local ph = 0
        return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
          H.call(function()
            ph = ph + 1
            H.setPad({ [pattern[(math.floor(ph / 20) % #pattern) + 1]] = true })
          end),
        }, tag .. ": a real world encounter fires (draw " .. n .. ")")
      end)(),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900,
        tag .. ": battle active (draw " .. n .. ")", 30),
      H.waitFrames(240),
      H.call(function()
        msPresent = {}
        for m = 0, 5 do
          if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
            msPresent[#msPresent + 1] = m
          end
        end
        local mhp = 0
        for _, m in ipairs(msPresent) do mhp = mhp + H.readWord(0x3BFC + m * 2) end
        H.vars.suitable = (#msPresent >= 2 and mhp >= 900)
        H.log(string.format("%s draw %d: %d bodies, %d total max HP -> %s",
          tag, n, #msPresent, mhp, H.vars.suitable and "FIGHT" or "flee"))
      end),
      H.cond(function() return not H.vars.suitable end, {
        H.fleeBattle(9000),
        H.waitUntil(function()
          return H.worldMode() and H.worldHasControl()
        end, 1200, tag .. ": back on the plain after draw " .. n, 10),
        H.waitFrames(30),
      }, {}),
    }
    if n == 1 then
      for _, s in ipairs(w) do steps[#steps + 1] = s end
    else
      steps[#steps + 1] = H.cond(function() return not H.vars.suitable end, w, {})
    end
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.vars.suitable, true,
      tag .. ": the pool dealt a two-resolution formation")
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    H.assertEq(slotOf[SETZER] ~= nil, true, tag .. ": SETZER present")
    actor = slotOf[SETZER]
    H.log(string.format("%s: setzer slot %d monsters={%s} joker=$%02x",
      tag, actor, table.concat(msPresent, ","), H.readByte(JOKER)))
  end)
  return steps
end

-- One Slot spin at pending tier `want`, played through real input and
-- driven to its commit; asserts run via `checks`.
--
-- The reels are not a window the drive can hold.  Every frame the battle
-- force-closes an open menu whose character has left the menu queue
-- (btlgfx_main.asm @0ca4: w7e4001,x == $ff sets w7e7bcb), and a status
-- that takes Setzer's turn does exactly that mid-spin.  Measured at seed
-- shifts 21 and 28 (build/attempts/wt/harness-faults/lab/harness-faults/repro/slots_s21.log,
-- slots_s28.log): Mind Candy put him to sleep with the reels up, EDGAR's
-- command window replaced them within 128 frames
-- (repro/slots_s21/frames/f4608.png the reels, f4736.png EDGAR's window),
-- and the A taps meant for reel 1 (shift 21) and the commit (shift 28)
-- fell on the windows that followed -- the shift-28 run ended on the
-- world map with the battle fought out by those taps.  So every tap here
-- is made only while the reels are Setzer's, a spin that loses its window
-- is void, and the drive plays another from his next turn: the menu, the
-- bank, the Slot row, the reels, the commit.  The per-reel checks run on
-- the spin that is live; the commit check on the one that committed.
local function playedSpin(tag, checks, want)
  local spins, committed = 0, false
  local function tapA(pred, what)
    return H.driveUntil(function() return not reelsLive() or pred() end, 3000, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
    }, what)
  end
  local function pressReel(r)
    return tapA(function() return H.readByte(PRESS[r]) ~= 0 end,
      tag .. " press" .. r)
  end
  local function waitStop(r)
    return H.waitUntil(function()
      return not reelsLive() or H.readByte(STOP[r]) ~= 0
    end, 900, tag .. " reel" .. r, 2)
  end
  local function live(steps) return H.cond(reelsLive, steps, {}) end
  local function check(name)
    return H.call(function() if checks[name] then checks[name]() end end)
  end
  local attempt = {
    menuFor(SETZER, tag .. ": setzer's window"),
    bankPending(want, tag),
    openSlotWindow(tag),
    H.call(function() spins = spins + 1 end),
    live({ pressReel(1) }),
    live({ check("afterPress1"), waitStop(1) }),
    live({ pressReel(2) }),
    live({ check("afterPress2"), waitStop(2) }),
    live({ pressReel(3) }),
    live({ waitStop(3) }),
    live({
      H.call(function() results = {} end),
      tapA(function()
        if #results > 0 then committed = true end
        return committed
      end, tag .. " commit"),
    }),
    H.call(function()
      if not committed then
        H.log(string.format("%s: the reels went at f%d before spin %d "
          .. "committed -- playing another from his next turn", tag, H.frame,
          spins))
      end
    end),
  }
  return {
    H.call(function() spins, committed = 0, false end),
    H.driveUntil(function()
      return committed or lostBattle or not H.battleLoadStarted()
    end, 30000, attempt, tag .. ": a spin played to its commit"),
    H.call(function()
      if lostBattle then return end
      H.assertEq(committed, true,
        tag .. ": a spin was played to its commit before the battle ended")
      H.log(string.format("%s: committed on spin %d", tag, spins))
      if checks.afterCommit then checks.afterCommit() end
    end),
  }
end

-- After the commit: drive the battle until the spin resolves, the battle
-- ends, Setzer falls (watchFall: the battle is lost to the test), or the
-- spin is dropped.  A spin is queued, not resolved, at its commit; it has
-- resolved when his action has ended (Ot6ActionEnd with his entity) and his
-- books have moved -- the pending tier spent (a boosted spin) or the bank
-- regenerated (a plain one) -- and the caller then asserts the exact
-- numbers.  His window coming back with the books unmoved and no action
-- of his ended means the spin was dropped: it never reached execution
-- (measured: a plain spin at shift 13, and at shift 7 with the other
-- windows handed on by X, came back 1,500-1,900 frames after the commit
-- with no Ot6ActionEnd for him), and it is played again from that turn.
-- One that ended and moved nothing is an economy defect, asserted.
-- Meanwhile every window that is not his gets care or a Defend, so no
-- window sits open while the party bleeds.
local spinVoid, spinDone = false, false
local function resolveLoop(tag)
  local hb, p0, b0, r0, away, res = -600, nil, nil, nil, false, nil
  return H.withReset(H.driveUntil(function()
    if p0 == nil then
      p0, b0, r0 = pend(actor), bp(actor), actEnd[actor * 2] or 0
      -- what the commit wrote ($2bb0 row, bank $c1), for the lines below
      local t = {}
      for _, e in ipairs(results) do
        t[#t + 1] = string.format("%04X=%02X", e.addr & 0xFFFF, e.v)
      end
      res = table.concat(t, " ")
    end
    if not setzerWindow() then away = true end
    if H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("[%s f%d] pend=%d bp=%d menu=%02x act=%02x st=%02x " ..
        "live=%s mons=%d | party %s", tag, H.frame, pend(actor), bp(actor),
        H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
        tostring(H.battleLoadStarted()), H.monstersPresent(), partyLine()))
    end
    if not H.battleLoadStarted() or watchFall(tag) then return true end
    local ran = (actEnd[actor * 2] or 0) - r0
    if pend(actor) ~= p0 or bp(actor) ~= b0 then
      H.assertEq(ran > 0, true, string.format("%s: Setzer's books moved (pend %d " ..
        "-> %d, bp %d -> %d) at the end of an action of his", tag, p0,
        pend(actor), b0, bp(actor)))
      spinDone = true
      H.log(string.format("[%s] f%d resolved: pend %d -> %d, bp %d -> %d; his " ..
        "action ended %d time(s) since the commit, the last as command $%02X; " ..
        "commit wrote %s", tag, H.frame, p0, pend(actor), b0, bp(actor), ran,
        actEndCmd[actor * 2] or 0xFF, res))
      return true
    end
    if away and setzerWindow() then
      H.assertEq(ran, 0, string.format("%s: his window came back at f%d with his " ..
        "books unmoved (pend %d, bp %d) and no action of his ended since the " ..
        "commit (one that ended, last at f%d, and charged nothing would be an " ..
        "economy defect)", tag, H.frame, pend(actor), bp(actor),
        actEndF[actor * 2] or -1))
      spinVoid = true
      H.log(string.format("[%s] f%d SETZER's window is back and his spin never " ..
        "ran (pend=%d bp=%d; commit wrote %s): it was dropped; played again " ..
        "from this turn", tag, H.frame, pend(actor), bp(actor), res))
      return true
    end
    return false
  end, 15000, {
    H.call(function() partyTurn() end),
    H.waitFrames(1),
  }, tag), function()
    hb, p0, b0, r0, away, res = -600, nil, nil, nil, false, nil
    otherWindowsReset()
  end)
end

-- A spin played to its commit and then to its resolution, played again
-- from Setzer's next turn when it was dropped (resolveLoop).  A fall ends
-- it unresolved; battleHalf answers that.
local function resolvedSpin(tag, checks, want)
  local body = {}
  for _, s in ipairs(playedSpin(tag, checks, want)) do body[#body + 1] = s end
  body[#body + 1] = resolveLoop(tag .. " resolve")
  body[#body + 1] = H.call(function()
    if spinVoid then
      spinVoid = false
      H.log(tag .. ": the spin was dropped; playing it again")
    end
  end)
  return H.cond(function() return true end, {
    H.call(function() spinVoid, spinDone = false, false end),
    H.driveUntil(function()
      return spinDone or lostBattle or not H.battleLoadStarted()
    end, 60000, body, tag .. ": the spin resolves"),
    H.call(function()
      if lostBattle then return end
      H.assertEq(spinDone, true, tag .. ": the spin resolved before the battle ended")
    end),
  })
end

-- One battle's half of the test: draw a formation (drawBattle), then its
-- phases.  If Setzer falls the battle is lost to the test (watchFall):
-- the remaining phases are skipped, the party raises him and heals him
-- past CARE_PCT (care; a battle run from with him down, or raised to an
-- eighth of his HP, leaves him down or nearly so on the plain -- in the
-- fault lab, raised only, he fell again at the next battle's open three
-- times running), runs, and draws a fresh battle, which opens at 1 bp again (Ot6InitBP), for the phases to
-- be played over -- at most MAX_LOST times in the run.
local function battleHalf(tag, phases)
  local done = false
  local body = { H.call(function() lostBattle = false end) }
  for _, s in ipairs(drawBattle(tag, 6)) do body[#body + 1] = s end
  for _, s in ipairs(phases) do
    body[#body + 1] = H.cond(function() return not lostBattle end, { s })
  end
  body[#body + 1] = H.cond(function() return lostBattle end, {
    H.call(function()
      H.assertEq(lostBattles <= MAX_LOST, true, string.format("Setzer fell in %d " ..
        "battles (the bound is %d): the party cannot keep him standing through " ..
        "a spin", lostBattles, MAX_LOST))
    end),
    H.driveUntil(function()
      return (php(actor) > 0 and php(actor) * 100 >= pmax(actor) * CARE_PCT)
        or not H.battleLoadStarted()
    end, 9000, { H.call(function() partyTurn() end), H.waitFrames(1) },
      tag .. ": SETZER raised and healed after his fall"),
    H.fleeBattle(12000),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl()
    end, 1800, tag .. ": back on the plain for a fresh battle", 10),
    H.waitFrames(60),
  }, { H.call(function() done = true end) })
  return { H.driveUntil(function() return done end, 150000, body, tag .. ": played") }
end

add({
  -- every battle's key ($be at InitBattle's seed store, the group, the
  -- encounter counters; H.firstBattleKey's form), so a sweep counts the H1
  -- and H2 fights by distinct key and not only the run's first battle
  H.call(function()
    -- and every action that ends, by entity (Ot6ActionEnd's X, where the
    -- bank is charged or regenerated), with its command ($b5): the resolve
    -- loop tells a spin that came to its end from one that never did.  A
    -- spin can end as CmdNoEffect ($b5 = $12, ExecAction's placeholder for
    -- an action removed from the queue): a plain spin at shift 3 did, with
    -- no Cmd_0f for him, and still regenerated its pip.  So did the
    -- cancelled spin of a fallen Setzer (watchFall), which is why a fall is
    -- caught before the books are read.
    local ae = H.sym("Ot6ActionEnd")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xffff
      actEnd[x] = (actEnd[x] or 0) + 1
      actEndF[x] = H.frame
      actEndCmd[x] = H.readByte(0xB5)
    end, emu.callbackType.exec, ae, ae)
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      local seed = emu.getState()["cpu.a"] & 0xff
      H.log(string.format("[slots] battle f%d key %s", H.frame,
        H.firstBattleKey(seed, H.readWord(0x11e0))))
    end, emu.callbackType.exec, addr, addr)
  end),
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("terra-returned-v1") end),

  -- disembark guard
  (function()
    local ph2 = 0
    return H.driveUntil(function()
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
})

add({ H.call(function() armWatches() end) })

-- walk the plain and choose the draw (slotsboot's check); H1, and the plain
-- spin that banks its pip back
add(battleHalf("H1 battle", {
  -- ---------------------------------------------- H1: the tier-1 spin
  menuFor(SETZER, "setzer menu (H1)"),
  H.call(function()
    H.assertEq(bp(actor), 1, "battle opens at 1 bp (Ot6InitBP)")
  end),
  bankPending(1, "H1"),
  H.call(function()
    H.assertEq(pend(actor), 1, "one real R press banks pending 1")
  end),
  resolvedSpin("H1", {
    afterPress1 = function()
      H.assertEq(H.readByte(SLOTTIER), 1,
        "H1: Ot6SlotRig stored tier 1 at the first press")
      H.log(string.format("H1: rig drawn $%02x (tier 1 leaves it alone -- "
        .. "value is the roll's own)", H.readByte(RIG)))
    end,
    afterCommit = function()
      H.assertEq(pend(actor), 1, "H1: the commit re-banked the stored tier 1")
    end,
  }, 1),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(actor), 0,
      "H1: 1 bp - 1 spent = 0, regen skipped on a boosted turn")
  end),
  -- --------------------------- bank the first pip back with a plain spin
  menuFor(SETZER, "setzer menu (bank spin 1)"),
  resolvedSpin("bank1", {}, 0),
  H.call(function()
    H.assertEq(bp(actor), 1, "bank1: unboosted spin regens 0 -> 1")
  end),
}))

-- A fresh fight opens at 1 bp, so one plain spin banks the 2 that H2 needs
-- and the fight is only two resolutions long, which the same formations do
-- survive.  Nothing is given up: the boundary re-seed is asserted on the
-- way in, so the fresh battle's opening bank is checked rather than
-- assumed, and both regen steps (0 -> 1 in the first fight, 1 -> 2 in the
-- second) are still real unboosted spins.
add({
  H.fleeBattle(12000),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl()
  end, 1800, "back on the plain for H2's own battle", 10),
  H.waitFrames(60),
})
add(battleHalf("H2 battle", {
  H.call(function()
    H.assertEq(bp(actor), 1,
      "the second battle re-seeds the bank at Ot6InitBP's 1 -- a bank is "
      .. "per battle, which is why H2 gets its own")
  end),
  menuFor(SETZER, "setzer menu (bank spin 2)"),
  resolvedSpin("bank2", {}, 0),
  H.call(function()
    H.assertEq(bp(actor), 2, "bank2: unboosted spin regens 1 -> 2")
  end),
  -- ---------------------------------------------- H2: the tier-2 spin
  menuFor(SETZER, "setzer menu (H2)"),
  bankPending(2, "H2"),
  H.call(function()
    H.assertEq(pend(actor), 2, "two real R presses bank pending 2")
    driftW = {}
  end),
  resolvedSpin("H2", {
    afterPress1 = function()
      H.assertEq(H.readByte(SLOTTIER), 2, "H2: stored tier 2")
      local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
      H.assertEq(H.readByte(RIG), want, string.format(
        "H2: THE RIG FORCED BENEVOLENT ($%02x) at 2 bp -- read off the "
        .. "machine, not written to it", want))
    end,
    afterPress2 = function()
      -- reel 1 stopped wherever the real press fell; the bless must aim
      -- reel 2 at that icon, unless it is the joker-gated 7
      local i1 = icon(1)
      local gated = i1 == 0 and (H.readByte(JOKER) & 4) ~= 0
      if gated then
        H.log("H2: reel 1 landed the gated 7 -- no help, documented exception")
        H.assertEq(H.readByte(HELP1), 0xFF, "H2: 7s stay gated")
      else
        H.assertEq(H.readByte(HELP1), i1, string.format(
          "H2: reel 2 blessed toward reel 1's actual icon %d", i1))
        H.assertEq(lastF0Drift(), 0x04,
          "H2: with vanilla's 4-icon budget, stored by the $f0 hook")
      end
    end,
    afterCommit = function()
      H.assertEq(pend(actor), 2, "H2: the commit re-banked the stored tier 2")
    end,
  }, 2),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(actor), 0, "H2: 2 bp - 2 spent = 0")
    H.assertEq(#mulHits, 0,
      "EXEMPTION (unrigged half): the damage multiplier never ran under cmd "
      .. "$0f across all four natural resolutions")
    H.log("unrigged half complete: tier-1 and tier-2 store/rig/bless/economy "
      .. "on a natural boot")
  end),
}))

local function stageEnemies(hp)
  for _, m in ipairs(msPresent) do
    local e = ENT_M(m)
    if hp then H.writeWord(0x3BFC + m * 2, 0xF000) end                -- never dies
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)            -- stopped
    H.writeByte(0x3AA1 + e, H.readByte(0x3AA1 + e) | 0x04)            -- death-proof
  end
end

local function hpsum()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(0x3BFC + m * 2) end
  return t
end

local function installSetzer()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, SETZER)
    H.writeByte(0x202E + s * 12, 0x0F)                                -- Slot, alone
    H.writeByte(0x2031 + s * 12, NONE)
    H.writeByte(0x2034 + s * 12, NONE)
    H.writeByte(0x2037 + s * 12, NONE)
    if actor and s ~= actor then
      -- non-actors are wounded rather than stopped: a stopped character's
      -- pending menu stays open indefinitely and starves the actor's next
      -- turn.
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) | 0x80)
      H.writeWord(0x3BF4 + s * 2, 0)
    else
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & 0x77)  -- -magitek -wound
      H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) & 0xCF)  -- -muddle/-berserk
      H.writeWord(0x3BF4 + s * 2, 999)                                -- actor hp pinned
    end
  end
end

local function pin() stageEnemies(true); installSetzer() end
local function pinNoHp() stageEnemies(false); installSetzer() end     -- damage windows

local function pressAUntilFn(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
  }, what)
end
local function pressAUntil(addr, what)
  return pressAUntilFn(function() return H.readByte(addr) ~= 0 end, what)
end
local function pressCommit(what)
  return H.repeatN(1, {
    H.call(function() results = {} end),
    pressAUntilFn(function() return #results > 0 end, what),
  })
end

local function openReels()
  return H.repeatN(1, {
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
    end, 12000, { H.call(pin), H.waitFrames(1) }, "setzer's menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return H.readByte(0x7BC2) == 0x08 and H.readByte(PRESS[1]) == 0
             and H.readByte(STOP[1]) == 0
    end, 1200, {
      H.call(function() pin(); H.setPad({ "a" }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(20),
    }, "slot window open (state 8)"),
    H.waitFrames(12),
  })
end

-- restart a stopped reel from a chosen position: clear its stop flag and let
-- the driver replay its boundary walk against the current mode cells
local function restartReel(r, pos)
  return H.call(function()
    H.writeByte(POS[r], pos)
    H.writeByte(STOP[r], 0)
  end)
end

local function waitStop(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

local hp3, d3, hp0, d0

add({
  H.call(function()
    H.log("*** entering the LABELED QUARANTINE LAB (entry-point install rig; "
      .. "see header) ***")
    msPresent = {}
    actor = nil
  end),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function()
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          local seen = false
          for _, x in ipairs(msPresent) do if x == m then seen = true end end
          if not seen then msPresent[#msPresent + 1] = m end
        end
      end
      pin()
    end),
    H.waitFrames(1),
  }, "menu opens (Setzer installed)"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("lab actor slot %d id=$%02x monsters={%s} joker=$%02x",
      actor, H.readByte(0x3ED8 + actor * 2),
      table.concat(msPresent, ","), H.readByte(JOKER)))
    pin()
    mulHits = {}
  end),

  -- ============================================================= arm T0: 0 bp
  -- byte-vanilla, including the rigged miss.  An all-cursed rig is poked after
  -- the draw, a pair of 3s is forced, and reel 3 restarted at $24 in the
  -- resulting avoid mode must skip the completing boundary $20 and halt at
  -- $10.  Economy: +1 regen, nothing charged.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 2)
    H.writeByte(0x3E9D + actor * 2, 0)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t0 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 0, "t0: store = 0 (tier-0 spin)")
    H.log(string.format("t0: rig drawn $%02x, poking $ff (all-cursed)", H.readByte(RIG)))
    H.writeByte(RIG, 0xFF)
  end),
  waitStop(1, "t0 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),   -- icon1 = REEL1[3] = 3
  pressAUntil(PRESS[2], "t0 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF, "t0: cursed reel 2 gets no help (w7e617b = $ff)")
  end),
  waitStop(2, "t0 reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x40) end),   -- icon2 = REEL2[4] = 3: a pair
  pressAUntil(PRESS[3], "t0 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x83,
      "t0: THE RIGGED MISS -- the cursed pair is avoid-marked (icon|$80)")
  end),
  waitStop(3, "t0 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- replay the walk into the completing boundary $20
  waitStop(3, "t0 reel3 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[3]), 0x10,
      "t0: avoid mode SKIPPED the completing boundary $20 and halted at $10")
    H.assertEq(icon(3), 1, "t0: the miss stands (icon 1, no triple)")
    H.assertEq(lastF0Drift() == nil, true, "t0: no $f0 writer touched the drift budget")
  end),
  pressCommit("t0 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 7, "t0: non-triple resolves lagomorph (index 7)")
  end),
  H.driveUntil(function() return bp(actor) == 3 end, 6000,
    { H.call(pin), H.waitFrames(1) }, "t0: unboosted turn regens +1 (2->3)"),
  H.call(function()
    H.assertEq(pend(actor), 0, "t0: nothing pending after the turn")
  end),

  -- ============================================================= arm T1: 1 bp
  -- the rigged miss is bought off.  Identical drive to T0, with the same poked
  -- rig, the same forced pair and the same reel-3 restart, and one pending
  -- byte different.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 1)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t1 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 1, "t1: store = 1")
    H.writeByte(RIG, 0xFF)          -- tier 1 keeps the drawn rig: curse it all
  end),
  waitStop(1, "t1 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),
  pressAUntil(PRESS[2], "t1 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF,
      "t1: reel-2 help is still rig-rolled at 1 bp (cursed: no help)")
  end),
  waitStop(2, "t1 reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x40) end),
  pressAUntil(PRESS[3], "t1 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x03,
      "t1: the pair is BLESSED, not avoid-marked (the miss is bought off)")
    H.assertEq(lastF0Drift(), 0x04,
      "t1: the hook budgeted vanilla's 4 (an $f0 write -- the bless is Ot6SlotMiss's)")
  end),
  waitStop(3, "t1 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- the very walk vanilla refused...
  waitStop(3, "t1 reel3 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[3]), 0x20,
      "t1: ...now HALTS on the completing boundary $20")
    H.assertEq(icon(3), 3, "t1: the triple lands")
  end),
  pressCommit("t1 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 4, "t1: triple 3s resolve index 4 (icon+1)")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t1: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 4, "t1: 5 bp - 1 spent = 4, regen skipped")
  end),

  -- ============================================================= arm T2: 2 bp
  -- the drift walk itself, replayed: restarted three icons shy of the match
  -- it must spend two budget icons and halt on the pair.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 2)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t2 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 2, "t2: store = 2")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want,
      string.format("t2: rig forced benevolent ($%02x)", want))
  end),
  waitStop(1, "t2 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),
  pressAUntil(PRESS[2], "t2 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0x03, "t2: reel 2 is blessed toward icon 3")
    H.assertEq(lastF0Drift(), 0x04, "t2: with vanilla's 4-icon budget (the $f0 store)")
  end),
  waitStop(2, "t2 reel2 stops (naturally)"),
  H.call(function() H.writeByte(DRIFT, 0x04) end),  -- replay with a fresh budget
  restartReel(2, 0x64),   -- $60 -> icon 1, $50 -> icon 4, $40 -> icon 3 (match)
  waitStop(2, "t2 reel2 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[2]), 0x40, "t2: reel 2 DRIFTED to the pair ($64 -> $40)")
    H.assertEq(H.readByte(DRIFT), 0x02, "t2: spending two of the four budget icons")
    H.assertEq(icon(2), 3, "t2: a machine-made pair of 3s")
  end),
  pressAUntil(PRESS[3], "t2 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x03, "t2: the pair is blessed onward")
  end),
  waitStop(3, "t2 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- match at the first boundary: budget-independent
  waitStop(3, "t2 reel3 re-stops"),
  H.call(function()
    H.assertEq(icon(3), 3, "t2: triple")
  end),
  pressCommit("t2 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 4, "t2: index 4")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t2: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 3, "t2: 5 bp - 2 spent = 3")
  end),

  -- ==================================================== arm T3b: exemption A/B
  -- the same triple at 3 bp and then at 0 bp: unboosted damage D0 must sit
  -- in the same range as boosted D3, since the multiplier would have made D3
  -- about 8x.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 3)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3 press1"),
  H.call(function()
    H.assertEq(H.readByte(SLOTTIER), 3, "t3: store = 3")
  end),
  waitStop(1, "t3 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x50) end),   -- icon1 = REEL1[5] = 5
  pressAUntil(PRESS[2], "t3 press2"),
  waitStop(2, "t3 reel2 stops"),
  H.call(function()
    H.assertEq(icon(2), 5, "t3: reel 2 sought the chosen icon (whole-strip budget)")
  end),
  pressAUntil(PRESS[3], "t3 press3"),
  waitStop(3, "t3 reel3 stops"),
  H.call(function()
    H.assertEq(icon(3), 5, "t3: the triple completes")
    stageEnemies(true)
    hp3 = hpsum()
  end),
  pressCommit("t3 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 6, "t3: triple 5s resolve index 6 (megaflare)")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 12000,
    { H.call(pinNoHp), H.waitFrames(1) },   -- NO hp re-pin: the damage must stand
    "t3: boosted triple resolves"),
  H.call(function()
    d3 = hp3 - hpsum()
    H.log(string.format("t3: boosted triple-5 damage = %d", d3))
    H.assertEq(d3 > 0, true, "t3: the boosted attack dealt damage")
    H.writeByte(0x3E9C + actor * 2, 2)
    H.writeByte(0x3E9D + actor * 2, 0)
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3b press1"),
  waitStop(1, "t3b reel1 stops"),
  pressAUntil(PRESS[2], "t3b press2"),
  waitStop(2, "t3b reel2 stops"),
  pressAUntil(PRESS[3], "t3b press3"),
  waitStop(3, "t3b reel3 stops"),
  H.call(function()
    H.writeByte(POS[1], 0x50)       -- REEL1[5]=5, REEL2[3]=5, REEL3[5]=5:
    H.writeByte(POS[2], 0x30)       --   the same triple 5s, tier 0
    H.writeByte(POS[3], 0x50)
    stageEnemies(true)
    hp0 = hpsum()
  end),
  pressCommit("t3b commit"),
  H.call(function()
    H.assertEq(results[#results].v, 6, "t3b: same result index at 0 bp")
  end),
  H.driveUntil(function() return bp(actor) == 3 end, 12000,
    { H.call(pinNoHp), H.waitFrames(1) }, "t3b: unboosted triple resolves (+1 regen)"),
  H.call(function()
    d0 = hp0 - hpsum()
    H.log(string.format("exemption: D0=%d D3=%d ratio=%.2f", d0, d3, d3 / d0))
    H.assertEq(d0 > 0, true, "t3b: the unboosted attack dealt damage")
    H.assertEq(d3 < d0 * 2, true,
      "EXEMPTION: boosted slot damage is NOT multiplied (x8 would show here)")
    H.assertEq(#mulHits, 0,
      "EXEMPTION: Ot6BoostDmg's multiplier path never ran under cmd $0f")
  end),

  -- ================================================= arm T3j: the joker gate
  -- $2f49.2 poked on: even at 3 bp the rig is $3c, a 7 gets no reel-2 help,
  -- and a forced 7-pair keeps the vanilla avoid mark, so the battle's own
  -- prohibition cannot be bought.  (BP is still spent, because certainty was
  -- offered on every other icon.)
  H.call(function()
    H.writeByte(JOKER, H.readByte(JOKER) | 0x04)
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 3)
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3j press1"),
  H.call(function()
    H.assertEq(H.readByte(RIG), 0x3C, "t3j: joker-gated rig ($3c) even at 3 bp")
  end),
  waitStop(1, "t3j reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x00) end),   -- icon1 = 0: the 7
  pressAUntil(PRESS[2], "t3j press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF, "t3j: no reel-2 help toward 7s")
  end),
  waitStop(2, "t3j reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x00) end),   -- forced 7-pair
  pressAUntil(PRESS[3], "t3j press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x80, "t3j: the 7-pair stays avoid-marked at 3 bp")
  end),
  waitStop(3, "t3j reel3 stops"),
  H.call(function()
    -- park reel 3 on a safe icon: 7-7-BAR is the self-doom result and 7-7-7
    -- may be script-forbidden here, while 7-7-4 is a plain lagomorph
    H.writeByte(POS[3], 0x30)       -- REEL3[3] = 4
  end),
  pressCommit("t3j commit"),
  H.call(function()
    H.assertEq(results[#results].v, 7, "t3j: no bought 777 -- lagomorph")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t3j: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 2, "t3j: the spend stands (certainty was offered elsewhere)")
    H.writeByte(JOKER, H.readByte(JOKER) & 0xFB)
    H.screenshot("slots_tiers_done")
  end),
})

H.run({ maxFrames = 400000 }, steps)

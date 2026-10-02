-- @suite slow
-- battle_slotsboot.lua -- boost-tiered Slot on a natural boot: cold-Continue
-- the terra-returned-v1 SRAM checkpoint (party LOCKE EDGAR SABIN SETZER,
-- save-point boundary F, lettered in tools/tests/savestate_graph.py; the
-- Continue restores the party on foot at the grounded Blackjack's tile),
-- pace the plain south of Zozo into a world encounter the spins can run in
-- (H.newEncounterDraw: budgeted from the pool's decode, the rest run from or
-- fought out), and drive real Slot spins with real button presses. No pokes
-- on either side: BP accumulates through Ot6ActionEnd's own regen (battle
-- opens at 1, +1 per unboosted turn), boost is spent with real R presses,
-- and the reels are stopped by real A presses. Whatever icons they land on,
-- the tier promises are asserted as invariants of the mechanism's own cells.

-- The spins:
--   spin 1 (0 bp): nothing is pending, the stored tier is 0, the result is
--     the landed icons' own, and the turn regens +1 bp.
--   bank spins (0 bp): unboosted spins until the bank holds 3.
--   spin 3 (3 bp, real R presses): the reel is chosen, so whatever icon
--     reel 1 was stopped on, reels 2 and 3 must find it (whole-strip drift
--     budget), the queued result is that icon's triple, and Ot6ActionEnd
--     charges exactly 3 with no regen.  If reel 1 lands the 7 in a battle
--     whose $2f49.2 forbids joker doom, the promise is documented to fold,
--     because the battle gate outranks boost, and it is asserted per that
--     rule instead.
-- Every number is taken against a baseline at the spin's own commit, and
-- a spin that never ran (its window lost, his action cancelled or
-- dropped) is played again from his next turn, as battle_slots plays them.

-- Setzer's control (H.newSpinnerCare, shared with battle_slots).  Before
-- each of his windows, and whenever the reels go, the drive reads what
-- takes his command (H.controlTaken: Death, Petrify, Zombie, Imp, Sleep,
-- Muddle, Berserk, Stop, Frozen) and the party gives it back the way a
-- person would: an ally's plain Fight on him for Sleep and Muddle, or the
-- item the ROM's records say cures it.  A status with no cure in reach
-- (for a hit: no ally in control with a Fight row) fails at once, naming
-- it.  The fight is given up instead -- lost to the test, Fought out, a
-- fresh battle drawn -- at the lost point: Setzer fallen; the formation
-- down to a monster whose conditional control attack is now live (the
-- Iron Fist casts an all-target Stone, Muddle, once it stands alone:
-- `if_num_monsters 1 / attack BATTLE, STONE, STONE`); two or more members
-- out of control; no ally left in control.  Spinning on into the lone
-- Stone wiped the party in the hold lab (h3_k9_s15 at 3c0d68d8).
--
-- The resolve loop's void branches need a status or a fall to land in the
-- few frames between his commit and his spin running, which this pool's
-- fights do not deal.  "dropped" is reached by the candy lab (the draw
-- blind to any-turn control attacks, so it fights Mind Candy packs:
-- build/attempts/wt/slotsboot-v024/runs4/cd6_k0_s8, its control
-- mut6_drop1).  Untested here: "cancelled" (reached by the same lab one
-- version earlier, lab4_attempts/cd5_k0_s7, not at this one) and the fall
-- with the spin queued, which asserts his books unmoved (the fellsetzer
-- lab, allies Fighting Setzer down, 8 shifts, did not reach it:
-- lab4_attempts/fs5_*).

-- The Ot6BoostDmg exemption rides the whole run as a write-watch: the
-- multiplier's $f0-bank OT6_SCR_BIT store must never happen under cmd $0f.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local RIG, HELP1 = 0x6179, 0x617B
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }
local SLOTTIER, JOKER = 0x57BA, 0x2F49
local SETZER = 0x09

local REEL = {
  { 0,4,5,3,4,5,2,5,1,4,5,3,5,2,3,1 },
  { 0,4,1,5,3,4,1,5,4,3,2,5,4,3,2,5 },
  { 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5 },
}
local function icon(r) return REEL[r][(H.readByte(POS[r]) >> 4) + 1] end

local slotOf = {}
local actor = nil
local function bp()   return H.readByte(0x3E9C + actor * 2) end
local function pend() return H.readByte(0x3E9D + actor * 2) end
local results, mulHits = {}, {}
local actEnd, actEndF, actEndCmd = {}, {}, {}  -- entity -> actions ended / last frame / last $b5
local actEnd0 = 0                              -- his count as the slot fight opened

local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

-- ---- reaching a formation the spins can run in -------------------------
-- The spins need a fight that outlasts three of them (two bodies, 600 max
-- HP between them) and no monster that can take Setzer's turn on any of
-- its own (H.judgeFormation: a control-taking attack outside a
-- conditional block; the Mind Candy's SleepSting, which tears a sleeping
-- spinner's slot window down, aea0cbe5).  A conditional one (the Iron
-- Fist's lone Stone) is let through and answered in the fight, below.
-- On the v0.24 ROM the Blackjack's plain rolls group 10, where only
-- Vulture + Iron Fist (80/256) suits; the checkpoint's Continue seeds the
-- counter from SRAM's $307ff1 ($D1 -> $DF, lib/ot6_field.lua above
-- M.ENCOUNTER_ODDS), which deals slots 3,3,2,4,4,2,2,2,3,1: the fight is
-- encounter 10, and six draws covered only 84.9% of counter states (the
-- budget is the worst of all of them, 21; after a Continue it is 15:
-- build/attempts/wt/slotsboot-v024/worstcase.txt and
-- build/attempts/review/slotsboot-v024-5bcf3044/worstcase_independent.txt).
-- The old clock-driven walk crossed into the forest's group 11 and once
-- into a town (build/attempts/wt/slotsboot-v024/runs/new1_mut_oldwalk.log.gz).
local draw = H.newEncounterDraw({ tag = "slotsboot", minBodies = 2, minHp = 600 })

-- ---- the party around the spinner --------------------------------------
-- The other members' windows and Setzer's control, from the library
-- (H.newSpinnerCare, lib/ot6_field.lua, shared with battle_slots): care
-- or a Defend, and when his control is taken (H.controlTaken) the cure a
-- person beside him gives -- an ally's plain Fight for Sleep or Muddle, the
-- item the ROM's records name for the rest -- with a fail-fast naming any
-- status nothing in reach cures.
local DENY_MAX = 6000            -- frames his control may stay taken with a cure in reach
local care = H.newSpinnerCare({ spinner = function() return actor end, denyMax = DENY_MAX })
local partyLine, otherWindow, otherWindowsReset = care.partyLine, care.window, care.reset
local setzerTaken, watchControl, cmdCell = care.spinnerTaken, care.watch, care.cmdCell
local taken, cared = care.taken, care.cared
local function php(s) return H.readWord(0x3BF4 + s * 2) end

local function setzerWindow()
  return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
end
local function reelsLive()
  return setzerWindow() and H.readByte(MSTATE) == 0x08
end

local function monstersDown()
  for m = 0, 5 do
    if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 then
      return false
    end
  end
  return true
end
local function fallen() return monstersDown() or not H.battleLoadStarted() end
-- The battle is lost to the test when its formation falls before spin 3
-- resolves, or at the lost point (care.lostPoint: the formation down to
-- the lone Iron Fist, whose Stone is then live; two or more members out
-- of control; no ally left in control).  The party then ends it with a
-- Fight (care.fightOut) rather than spin into Stone, cares, and the
-- draw deals a fresh battle (Ot6InitBP's 1 again) for the spins to be
-- played over, at most MAX_BATTLES in the run (three lost): in the
-- round-3 sweep (build/attempts/wt/slotsboot-v024/runs4/n6_*, 30 runs) no
-- run lost more than one.
local lost, battles, MAX_BATTLES = false, 0, 4
local done, armedOnce, spin3Resolved = false, false, false
local function markLost(what, why)
  if not lost then
    lost = true
    H.log(string.format("[slotsboot] f%d %s: %s (battle #%d) -- this battle is lost to the "
      .. "test | party %s", H.frame, what, why, battles, partyLine()))
  end
end
-- a committed spin not yet read by the resolve loop: the lost point waits
-- until it is read (spin 3's own triple can fell the formation as it
-- resolves, and that is the spin resolving, not the battle lost)
local spinInFlight = false
local function checkLost(what)
  if lost or spinInFlight or not H.battleLoadStarted() then return lost end
  if monstersDown() then markLost(what, "the formation fell before spin 3 resolved")
  else
    local why = care.lostPoint()
    if why then markLost(what, why) end
  end
  return lost
end

-- One frame of the party while Setzer waits: messages paged with A, the
-- other windows played, his own left alone unless his control is taken.
local function partyTurn(what)
  -- the lost point is marked here but ends nothing in flight: a spin queued
  -- as the formation thins is still played to its resolution, and the
  -- windows keep their care meanwhile
  if not checkLost(what) then watchControl(what) end
  if H.readByte(MENU) == 0 then
    otherWindowsReset()
    H.setPad(H.frame % 8 < 4 and { a = true } or {})
  elseif H.readByte(ACTOR) ~= actor or setzerTaken() then
    otherWindow()
  else
    otherWindowsReset()
    H.setPad({})
  end
end

-- wait for Setzer's own window with his control his: the other windows get
-- care, a cure or a Defend; the lost point ends the wait
local function menuFor(what)
  local hb = nil
  return H.withReset(H.driveUntil(function()
    return (setzerWindow() and setzerTaken() == nil) or lost or fallen()
  end, 30000, {
    H.call(function()
      if hb == nil or H.frame - hb >= 600 then
        if hb ~= nil then
          H.log(string.format("  [%s hb f%d] menu=%02x actor=%d mstate=%02x | party %s",
            what, H.frame, H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
            partyLine()))
        end
        hb = H.frame
      end
      if checkLost(what) then H.setPad({}); return end
      watchControl(what)
      if H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) ~= actor or setzerTaken()) then
        otherWindow()
      else
        otherWindowsReset()
        H.setPad({})
      end
    end),
  }, what), function() hb = nil; otherWindowsReset() end)
end
local function stillOn(what)
  return H.call(function() checkLost(what) end)
end

-- Bank boost pips with real R presses, by feedback (battle_slots'
-- bankPending): taps only while his window is up, stops at `want`.
local function bankPending(want, what)
  local taps = 0
  return H.withReset(H.repeatN(1, {
    H.driveUntil(function() return not setzerWindow() or pend() >= want or bp() < want end, 1500, {
      H.call(function()
        if taps >= 12 then
          error(string.format("%s: R tapped %d times and pending still reads "
            .. "%d (want %d) -- the press is not being stored at all",
            what, taps, pend(), want), 0)
        end
        taps = taps + 1
      end),
      H.pressButtons({ "r" }, 6), H.waitFrames(20),
    }, what .. ": R taps bank pending " .. want),
    H.call(function()
      if taps > 0 then
        H.log(string.format("%s: pending %d after %d R tap(s)", what, pend(), taps))
      end
    end),
  }), function() taps = 0 end)
end

-- move the command cursor onto the Slot row (verified against the live
-- cursor cell w7e890f+slot), confirm, and wait for the live reel state;
-- every drive also ends when the window is no longer his
local function openSlotWindow(what)
  local row = nil
  return H.repeatN(1, {
    H.call(function()
      row = cmdCell(actor, 0x0F)
      H.assertEq(row ~= nil, true, "setzer's menu offers Slot")
    end),
    H.driveUntil(function()
      return not setzerWindow() or H.readByte(0x890F + actor) == row
    end, 900, {
      H.call(function()
        local cur = H.readByte(0x890F + actor)
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

-- One spin at pending tier `want` played to its commit (battle_slots'
-- playedSpin): every tap only while the reels are his; a spin whose
-- window goes is void, its cause said, and played again from his next
-- turn once his control is back.  checks run on the live spin.
local spinVoid, spinDone, resolvedB0 = false, false, nil
-- a tier the bank no longer covers (a muddled turn dumped it: Ot6Retaliate)
local bankShort = false
local replays, MAX_REPLAYS = { lost = 0, dropped = 0, cancelled = 0, fell = 0 }, 2  -- battle_slots' bound
local MAX_BANK = 4               -- unboosted bank spins: 2 from Ot6InitBP's 1, and a re-bank
local function replayed(kind, tag)
  replays[kind] = replays[kind] + 1
  local n = replays.lost + replays.dropped + replays.cancelled + replays.fell
  H.assertEq(n <= MAX_REPLAYS, true, string.format("%s: %d spins replayed in this "
    .. "run (%d window lost, %d dropped, %d cancelled, %d fell; the bound is %d)",
    tag, n, replays.lost, replays.dropped, replays.cancelled, replays.fell, MAX_REPLAYS))
end
local function playedSpin(tag, checks, want)
  local spins, committed = 0, false
  local function tapA(pred, what)
    return H.driveUntil(function() return not reelsLive() or pred() end, 3000, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
    }, what)
  end
  local function pressReel(r)
    return tapA(function() return H.readByte(PRESS[r]) ~= 0 end, tag .. " press" .. r)
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
    menuFor(tag .. ": setzer's window"),
    stillOn(tag),
    bankPending(want, tag),
    H.call(function()
      if pend() < want then
        bankShort = true
        H.log(string.format("%s: the bank holds %d, short of tier %d (pend %d) -- banking "
          .. "unboosted spins first | party %s", tag, bp(), want, pend(), partyLine()))
      end
    end),
    H.cond(function() return bankShort or lost end, {}, { openSlotWindow(tag) }),
    H.call(function() spins = spins + 1 end),
    live({ pressReel(1) }),
    live({ check("afterPress1"), waitStop(1) }),
    live({ check("afterStop1"), pressReel(2) }),
    live({ check("afterPress2"), waitStop(2) }),
    live({ pressReel(3) }),
    live({ waitStop(3) }),
    live({
      H.call(function() results = {} end),
      tapA(function()
        if #results > 0 then committed, spinInFlight = true, true end
        return committed
      end, tag .. " commit"),
    }),
    H.call(function()
      if not committed and not bankShort and not lost and not fallen() then
        local c = setzerTaken()
        H.log(string.format("%s: the reels went at f%d before spin %d committed (%s) "
          .. "-- playing another from his next turn | party %s", tag, H.frame, spins,
          c and ("SETZER " .. c.name) or "his control is his", partyLine()))
        replayed("lost", tag)
      end
    end),
  }
  return {
    H.call(function() spins, committed = 0, false end),
    H.driveUntil(function()
      return committed or bankShort or lost or fallen()
    end, 30000, attempt, tag .. ": a spin played to its commit"),
    H.call(function()
      if bankShort then return end
      if not committed then markLost(tag, "the battle ended before the spin committed"); return end
      H.log(string.format("%s: committed on spin %d", tag, spins))
      if checks.afterCommit then checks.afterCommit() end
    end),
  }
end

-- After the commit: drive the battle until the spin resolves (his action
-- ended as Slot, $b5 = $0F, and his books moved), or it never ran:
-- cancelled (his action ended as CmdNoEffect, $12: settled as an
-- unboosted turn that bought nothing), dropped (his window came back with
-- nothing of his ended), or he fell with it queued.  The void ones are
-- played again (battle_slots' resolveLoop).
local CMD_SLOT, CMD_NOEFFECT = 0x0F, 0x12
local function resolveLoop(tag)
  local p0, b0, r0, away, hb = nil, nil, nil, false, -600
  return H.withReset(H.driveUntil(function()
    if p0 == nil then p0, b0, r0 = pend(), bp(), actEnd[actor * 2] or 0 end
    if not setzerWindow() then away = true end
    if H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("[%s f%d] pend=%d bp=%d menu=%02x act=%02x st=%02x live=%s | party %s",
        tag, H.frame, pend(), bp(), H.readByte(MENU), H.readByte(ACTOR),
        H.readByte(MSTATE), tostring(H.battleLoadStarted()), partyLine()))
    end
    if not H.battleLoadStarted() then return true end
    local ran = (actEnd[actor * 2] or 0) - r0
    local cmd = actEndCmd[actor * 2] or 0xFF
    if php(actor) == 0 and ran == 0 then
      -- a fall with the spin queued: it never ran, and nothing was charged
      -- for it (Ot6ActionEnd never took his action: battle_slots' #346)
      H.assertEq(pend() == p0 and bp() == b0, true, string.format("%s: he fell with the "
        .. "spin queued and his books unmoved (pend %d -> %d, bp %d -> %d)", tag, p0,
        pend(), b0, bp()))
      H.log(string.format("[%s] f%d SETZER fell with the spin queued (pend %d bp %d): "
        .. "it never ran; raised, then played again", tag, H.frame, pend(), bp()))
      replayed("fell", tag)
      spinVoid = true
      return true
    end
    if ran > 0 and cmd ~= CMD_SLOT then
      H.assertEq(cmd, CMD_NOEFFECT, string.format("%s: his action ended as command $%02X, "
        .. "neither the spin ($0F) nor a cancelled action ($12)", tag, cmd))
      H.assertEq(pend() == 0 and bp() == math.min(b0 + 1, 5), true, string.format("%s: a "
        .. "cancelled spin costs nothing and regenerates as an unboosted turn: pend %d -> "
        .. "%d (want 0), bp %d -> %d (want %d)", tag, p0, pend(), b0, bp(), math.min(b0 + 1, 5)))
      H.log(string.format("[%s] f%d CANCELLED: his action ended as $%02X; played again",
        tag, H.frame, cmd))
      replayed("cancelled", tag)
      spinVoid = true
      return true
    end
    if pend() ~= p0 or bp() ~= b0 then
      H.assertEq(ran > 0, true, string.format("%s: Setzer's books moved (pend %d -> %d, "
        .. "bp %d -> %d) at the end of an action of his", tag, p0, pend(), b0, bp()))
      spinDone, resolvedB0 = true, b0
      H.log(string.format("[%s] f%d resolved: pend %d -> %d, bp %d -> %d; his action "
        .. "ended %d time(s) since the commit, the last as $%02X", tag, H.frame, p0,
        pend(), b0, bp(), ran, cmd))
      return true
    end
    if away and setzerWindow() and setzerTaken() == nil then
      H.assertEq(ran, 0, string.format("%s: his window came back with his books unmoved "
        .. "(pend %d, bp %d) and no action of his ended since the commit", tag, pend(), bp()))
      H.log(string.format("[%s] f%d his window is back and the spin never ran: dropped; "
        .. "played again", tag, H.frame))
      replayed("dropped", tag)
      spinVoid = true
      return true
    end
    return false
  end, 9000, {
    H.call(function() partyTurn(tag) end),
    H.waitFrames(1),
  }, tag), function()
    p0, b0, r0, away, hb = nil, nil, nil, false, -600
    otherWindowsReset()
  end)
end
-- onResolved runs when the spin resolved, before the in-flight mark is
-- cleared, so a lost point marked while it was in flight cannot end the
-- caller's wait first
local function resolvedSpin(tag, checks, want, onResolved)
  local body = {}
  for _, s in ipairs(playedSpin(tag, checks, want)) do body[#body + 1] = s end
  body[#body + 1] = H.cond(function() return not bankShort and (spinInFlight or not lost) end,
    { resolveLoop(tag .. " resolve") }, {})
  body[#body + 1] = H.call(function() if not spinDone then spinInFlight = false end end)
  body[#body + 1] = H.call(function()
    if spinVoid then spinVoid = false end
  end)
  return H.repeatN(1, {
    H.call(function() spinVoid, spinDone, spinInFlight = false, false, false end),
    H.driveUntil(function()
      return spinDone or bankShort or (lost and not spinInFlight) or not H.battleLoadStarted()
    end, 60000, body, tag .. ": the spin resolves"),
    H.call(function()
      if spinDone and onResolved then onResolved() end
      spinInFlight = false
      if bankShort then return end
      if not spinDone then markLost(tag, "the battle ended before the spin resolved") end
    end),
  })
end

-- ------------------------------- spin 3: real R presses, the icon chosen
local spin3Done = false
local SPIN3 = resolvedSpin("spin3", {
    afterPress1 = function()
      H.assertEq(pend(), 3, "spin3: real R presses banked pending 3")
      H.assertEq(H.readByte(SLOTTIER), 3, "spin3: stored tier 3 at the first press")
      local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
      H.assertEq(H.readByte(RIG), want, "spin3: rig forced benevolent")
    end,
    afterStop1 = function()
      H.log(string.format("spin3: reel 1 stopped on icon %d (pos $%02x)",
        icon(1), H.readByte(POS[1])))
    end,
    afterPress2 = function()
      -- the chosen icon is reel 1's real stop.  In a joker-forbidden battle a
      -- timed 7 is the documented exception: no help and no bought triple.
      local chosen = icon(1)
      local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
      if gated then
        H.assertEq(H.readByte(HELP1), 0xFF, "spin3: 7s stay gated ($2f49.2)")
      else
        H.assertEq(H.readByte(HELP1), chosen, "spin3: reel 2 seeks the chosen icon")
      end
    end,
    afterCommit = function()
      local chosen = icon(1)
      local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
      if gated then
        H.log("spin3: joker-gated 7 -- triple not bought (documented exception)")
      else
        H.assertEq(icon(2), chosen, "spin3: reel 2 landed the chosen icon")
        H.assertEq(icon(3), chosen, "spin3: reel 3 landed the chosen icon")
        H.assertEq(results[#results].v, chosen + 1,
          string.format("spin3: THE CHOSEN TRIPLE queued (icon %d -> index %d)",
            chosen, chosen + 1))
      end
      H.assertEq(pend(), 3, "spin3: the commit banked the stored tier")
      H.screenshot("slotsboot_chosen")
    end,
  }, 3, function() spin3Done, spin3Resolved = true, true end)

H.run({ maxFrames = 400000 }, {
  -- every action that ends, by entity (Ot6ActionEnd's X), with its
  -- command ($b5); and every battle's key ($be at InitBattle's seed store
  -- with the battle's $11e0 and the counters, H.firstBattleKey's form), so
  -- a sweep counts the slot fights by distinct key
  H.call(function()
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
      H.log(string.format("[slotsboot] battle f%d key %s", H.frame,
        H.firstBattleKey(seed, H.readWord(0x11e0))))
    end, emu.callbackType.exec, addr, addr)
  end),
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3), using the
  -- probe_mp_universal boot unchanged
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

  -- ---- the battle: drawn, its spins played; a fresh one when it is lost --
  H.driveUntil(function() return done end, 380000, {
    H.call(function()
      lost, bankShort = false, false
      battles = battles + 1
      H.assertEq(battles <= MAX_BATTLES, true, string.format("%d battles drawn for the "
        .. "spins (the bound is %d): the formation keeps falling before spin 3 resolves",
        battles, MAX_BATTLES))
    end),
    H.repeatN(1, draw.steps()),
    H.call(function()
      for s = 0, 3 do
        local id = H.readByte(0x3ED8 + s * 2)
        if id ~= 0xFF then slotOf[id] = s end
      end
      H.assertEq(slotOf[SETZER] ~= nil, true, "SETZER present")
      actor = slotOf[SETZER]
      actEnd0 = actEnd[actor * 2] or 0
      -- the opening bank, before any turn of his: Ot6InitBP's 1.  Read here,
      -- not at his first window: a turn the engine takes for him first (a
      -- Muddle) spends or banks under OT6's retaliation rule (Ot6Retaliate)
      H.assertEq(bp(), 1, "battle opens at 1 bp (Ot6InitBP), read before any turn of his")
      H.log(string.format("setzer slot %d monsters={%s} joker=$%02x (battle #%d) | party %s",
        actor, table.concat(draw.msPresent, ","), H.readByte(JOKER), battles, partyLine()))
      if armedOnce then return end
      armedOnce = true
      -- the C1 commit write of the result index
      emu.addMemoryCallback(function(a, v)
        pcall(function()
          local s = emu.getState()
          if s["cpu.k"] == 0xC1 then results[#results + 1] = { addr = a, v = v } end
        end)
      end, emu.callbackType.write, 0x7E2BB0, 0x7E2BC9)
      -- the exemption watch: Ot6BoostDmg's multiplier parks its counter in
      -- OT6_SCR_BIT ($3ece) before multiplying, so a write from inside the proc
      -- under cmd $0f means the multiplier ran, which the exemption forbids
      -- ($3ece is shared OT6 scratch, so the pc range is load-bearing)
      local BOOSTDMG = H.sym("Ot6BoostDmg")
      emu.addMemoryCallback(function(_, v)
        -- cheap guards first (battle_slots' measurement: emu.getState()
        -- serialises the machine, and $3ece is written tens of thousands of
        -- times a run)
        if not (v > 0 and H.readByte(0xB5) == 0x0F) then return end
        pcall(function()
          local s = emu.getState()
          local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
          if pc >= BOOSTDMG and pc < BOOSTDMG + 0xA0 then
            mulHits[#mulHits + 1] = v
          end
        end)
      end, emu.callbackType.write, 0x7E3ECE, 0x7E3ECE)
    end),
    H.cond(function() return not lost end, {
      -- ------------------------------- spin 1: 0 bp, no boost bytes written ----
      menuFor("setzer menu (spin 1)"),
      stillOn("spin 1"),
      H.call(function() if not lost then H.assertEq(pend(), 0, "nothing pending") end end),
      resolvedSpin("spin1", {
        afterPress1 = function()
          H.assertEq(H.readByte(SLOTTIER), 0, "spin1: stored tier 0")
          H.log(string.format("spin1: rig=$%02x (vanilla draw, untouched)", H.readByte(RIG)))
        end,
        afterCommit = function()
          local i1, i2, i3 = icon(1), icon(2), icon(3)
          local want = (i1 == i2 and i2 == i3) and i1 + 1
            or ((i1 == 0 and i2 == 0 and i3 == 2) and 0 or 7)
          H.assertEq(results[#results].v, want,
            string.format("spin1: result matches the landed icons (%d,%d,%d)", i1, i2, i3))
          H.assertEq(pend(), 0, "spin1: still nothing pending at commit")
        end,
      }, 0),
      H.call(function()
        if lost then return end
        H.assertEq(bp(), math.min(resolvedB0 + 1, 5), string.format(
          "spin1: the unboosted turn regens %d -> %d", resolvedB0, math.min(resolvedB0 + 1, 5)))
      end),

      -- --------------------- bank spins (0 bp) until the bank holds 3, then spin 3
      -- A turn the engine takes for him (a Muddle) can dump the bank
      -- (Ot6Retaliate), so spin 3 finding it short banks again; the unboosted
      -- spins are bounded by MAX_BANK.
      (function()
        local banks = 0
        local bankSpin = H.repeatN(1, {
          H.call(function()
            banks = banks + 1
            H.assertEq(banks <= MAX_BANK, true, string.format("%d unboosted bank spins "
              .. "(the bound is %d) and the bank still short of 3", banks, MAX_BANK))
          end),
          resolvedSpin("bank", {}, 0),
          H.call(function()
            if lost then return end
            H.assertEq(bp(), math.min(resolvedB0 + 1, 5), string.format(
              "bank #%d: the unboosted spin regens %d -> %d", banks, resolvedB0,
              math.min(resolvedB0 + 1, 5)))
          end),
        })
        return H.repeatN(1, {
          H.call(function() banks, spin3Done = 0, false end),
          H.driveUntil(function()
            return spin3Done or (lost and not spin3Resolved and not spinInFlight)
          end, 200000, {
            H.cond(function() return bp() < 3 end, { bankSpin }, {
              H.call(function() bankShort = false end),
              SPIN3,
              H.call(function() bankShort = false end),
            }),
          }, "the bank holds 3 and spin 3 is played"),
        })
      end)(),
    }, {}),
    H.cond(function() return lost and not spin3Resolved end, {
      -- the party Fights out the battle the spins could not finish
      -- (care.fightOut: every member with control Fights the first
      -- monster standing), and cares
      care.fightOut("slotsboot"),
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl()
      end, 1200, "back on the plain after the lost battle", 10),
      H.release(),
      H.waitFrames(30),
      H.careStop("care after lost battle"),
    }, { H.call(function() done = true end) }),
  }, "the spins played in a battle that stands through them"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(), resolvedB0 - 3, string.format("spin3: %d bp - 3 charged in full = "
      .. "%d, no regen on a boosted turn", resolvedB0, resolvedB0 - 3))
    H.assertEq(#mulHits, 0,
      "EXEMPTION: the damage multiplier never ran under cmd $0f (natural run)")
    H.log(string.format("battle_slotsboot complete: encounters %d, control taken %d "
      .. "time(s), cures confirmed %d hit / %d item / %d raise, spins replayed %d lost "
      .. "/ %d dropped / %d cancelled / %d fell, battles lost to the test %d",
      draw.n, taken.n, cared.hit, cared.cure, cared.raise, replays.lost, replays.dropped,
      replays.cancelled, replays.fell, battles - 1))
  end),
})

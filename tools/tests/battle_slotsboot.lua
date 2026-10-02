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

-- Setzer's control.  The fight the draw reaches can take his turn: the
-- Iron Fist casts Stone (Muddle) once it stands alone (ai_script.asm
-- `if_num_monsters 1 / attack BATTLE, STONE, STONE`), which a spin that
-- kills the Vulture first leaves it.  Before each of his windows, and
-- whenever the reels go, the drive reads what takes his command
-- (H.controlTaken: Death, Petrify, Zombie, Imp, Sleep, Muddle, Berserk,
-- Stop, Frozen) and the party gives it back the way a person would: an
-- ally's plain Fight on him for Sleep and Muddle, or the item the ROM's
-- records say cures it (Fenix Down, Soft, Revivify, Green Cherry,
-- Remedy).  A status with no cure in reach fails at once, naming it.

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
-- The other members' windows (battle_slots' care, with the cures added):
--   * Setzer's control taken: Fenix Down on him for Death; an ally's plain
--     Fight on him for Sleep or Muddle (healed first when the hit could
--     drop him: under HIT_FLOOR of his max HP, the fight driver's
--     unmeasured unmuddle floor, a quarter); the cure item the ROM's
--     records name for Petrify, Zombie or Imp; then an ally asleep or
--     muddled gets the same hit;
--   * else a dead member raised with a Fenix Down, one raise in flight;
--   * else a living member under CARE_PCT gets a Potion (a Tonic without);
--   * else Defend.  Nobody but Setzer attacks: the formation has to stand
--     through the spins.
local CARE_PCT, HIT_FLOOR = 50, 25
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local CMD_FIGHT, CMD_ITEM = 0x00, 0x01
local ST_CMD, ST_ITEM, ST_TGT, ST_DEF = 0x05, 0x0A, 0x38, 0x27
local BATTINV, ITEMSCR, ITEMROW = 0x2686, 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local DENY_MAX = 6000            -- frames his control may stay taken with a cure in reach
local function chid(s) return H.readByte(0x3ED8 + s * 2) end
local function php(s) return H.readWord(0x3BF4 + s * 2) end
local function pmax(s) return H.readWord(0x3C1C + s * 2) end
local function seated(s) return chid(s) ~= 0xFF and pmax(s) > 0 end
local function partyLine()
  local t = {}
  for s = 0, 3 do
    if seated(s) then
      local c = H.controlTaken(s)
      t[#t + 1] = string.format("%02X:%d/%d bp%d%s", chid(s), php(s), pmax(s),
        H.readByte(0x3E9C + s * 2), c and (" " .. c.name) or "")
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
local function cmdCell(a, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + a * 12 + r * 3) == cmd then return r end
  end
end
local function setzerTaken() return actor ~= nil and H.controlTaken(actor) or nil end
-- the cure in reach for a control-taking status: "hit", an item id, or nil
local function cureOf(c)
  if c.cure == "hit" then return "hit" end
  if c.items == nil then return nil end
  return H.statusCure({ byte = c.byte, bit = c.bit, items = c.items,
    has = function(item) return invIdx(item) ~= nil end })
end

local inFlight = {}                       -- e -> { f, kind, hp }: a care action confirmed
local cared = { heal = 0, raise = 0, cure = 0, hit = 0 }
local W = { actor = nil, n = 0, plan = nil }
local function carePlan(a)
  -- a confirmed action is in flight until it lands, 900 frames pass, or
  -- what it answered is gone or has become something else (a Fight on a
  -- muddled member who then falls leaves him needing a Fenix Down)
  for e, h in pairs(inFlight) do
    local now = H.controlTaken(e)
    if H.frame - h.f > 900 or (h.kind == "heal" and php(e) > h.hp)
       or (h.kind ~= "heal" and (now == nil or now.name ~= h.st)) then
      inFlight[e] = nil
    end
  end
  local itemCell, fightCell = cmdCell(a, CMD_ITEM), cmdCell(a, CMD_FIGHT)
  -- Setzer's control first, then a muddled or sleeping ally's (a muddled
  -- ally's own turns are the engine's to aim, at the formation or the
  -- party, so a person hits them out of it too)
  local order = { actor }
  for s = 0, 3 do if s ~= actor then order[#order + 1] = s end end
  for _, e in ipairs(order) do
    local c = seated(e) and H.controlTaken(e) or nil
    if c and e ~= a and inFlight[e] == nil and (e == actor or c.cure == "hit") then
      local cure = cureOf(c)
      if c.name == "Death" and cure and itemCell then
        return { plan = "raise", tgt = e, idx = invIdx(cure), cell = itemCell, item = cure, why = c.name }
      elseif cure == "hit" and fightCell then
        if php(e) * 100 < pmax(e) * HIT_FLOOR and itemCell then
          local item = invIdx(POTION) and POTION or (invIdx(TONIC) and TONIC or nil)
          if item then
            return { plan = "heal", tgt = e, idx = invIdx(item), cell = itemCell, item = item,
                     why = c.name .. " (healed before the hit that cures it)" }
          end
        end
        return { plan = "hit", tgt = e, cell = fightCell, why = c.name }
      elseif cure and itemCell then
        return { plan = "cure", tgt = e, idx = invIdx(cure), cell = itemCell, item = cure, why = c.name }
      end
    end
  end
  if itemCell == nil then return { plan = "defend" } end
  if invIdx(FENIX) then
    for s = 0, 3 do
      if seated(s) and php(s) == 0 and inFlight[s] == nil and s ~= a then
        return { plan = "raise", tgt = s, idx = invIdx(FENIX), cell = itemCell, item = FENIX, why = "Death" }
      end
    end
  end
  local item = invIdx(POTION) and POTION or (invIdx(TONIC) and TONIC or nil)
  if item == nil then return { plan = "defend" } end
  local pick, pickPct = nil, nil
  for s = 0, 3 do
    local pct = seated(s) and php(s) * 100 // math.max(pmax(s), 1) or 100
    if seated(s) and php(s) > 0 and pct < CARE_PCT and inFlight[s] == nil then
      if pick == nil or (s == actor) or (pick ~= actor and pct < pickPct) then
        pick, pickPct = s, pct
      end
    end
  end
  if pick then
    return { plan = "heal", tgt = pick, idx = invIdx(item), cell = itemCell, item = item, why = "HP" }
  end
  return { plan = "defend" }
end
-- One frame of a window that is not a Slot spin (MENU open): another
-- member's, or his own while his control is taken (an Imp's, a Stopped
-- one's), which Defends.
local function otherWindow()
  local a = H.readByte(ACTOR) & 3
  if W.actor ~= a then
    W.actor, W.via, W.n = a, nil, 0
    W.p = carePlan(a)
    if W.p.plan ~= "defend" then
      H.log(string.format("[care] f%d actor %d (%02X): %s slot %d (%02X)%s for %s | party %s",
        H.frame, a, chid(a), W.p.plan, W.p.tgt, chid(W.p.tgt),
        W.p.item and string.format(" with $%02X (%d in the bag)", W.p.item, invCount(W.p.item)) or "",
        W.p.why, partyLine()))
    end
  end
  W.n = W.n + 1
  local ph = W.n % 10
  local st = H.readByte(MSTATE)
  local p = W.p
  local function tap(b) H.setPad(ph < 5 and { [b] = true } or {}) end
  -- a window open for a member whose control is taken (a Muddle that
  -- landed as it opened) is passed on with X, as the fight driver's
  -- muddled actor defers (#170): a command confirmed there is the
  -- engine's to re-aim
  local own = H.controlTaken(a)
  if own then
    if W.n == 1 then
      H.log(string.format("[care] f%d actor %d (%02X)'s window is open under %s: passed on (X)",
        H.frame, a, chid(a), own.name))
    end
    if st == ST_CMD then tap("x") else tap("b") end
    return
  end
  if p.plan == "defend" then
    if st == ST_CMD then
      if H.readByte(0x3E9D + a * 2) > 0 then tap("l") else tap("right") end
    elseif st == ST_DEF then tap("a")
    elseif st == 0x0A or st == 0x30 or st == 0x16 or st == 0x24 or st == 0x0E
        or st == ST_TGT or st == 0x08 then tap("b")
    else H.setPad({}) end
    return
  end
  if st == ST_CMD then
    local cur = H.readByte(0x890F + a)
    if cur ~= p.cell then tap(cur < p.cell and "down" or "up"); return end
    if H.readByte(0x3E9D + a * 2) > 0 then tap("l"); return end   -- care goes unboosted
    W.via = p.plan == "hit" and "fight" or "cmd"
    tap("a")
  elseif st == ST_ITEM and p.idx then
    local cur = H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
    if cur ~= p.idx then tap(cur < p.idx and "down" or "up"); return end
    W.via = "item"
    tap("a")
  elseif st == ST_TGT then
    if W.via ~= "item" and W.via ~= "fight" and W.via ~= "confirmed" then tap("b"); return end
    local chars = H.readByte(TGTCHARS)
    if H.readByte(TGTMONS) ~= 0 or chars == 0 then
      tap(H.battleLayout().toChars[1])
      return
    end
    if chars ~= (1 << p.tgt) then
      local cur = 0
      for s = 3, 0, -1 do if chars & (1 << s) ~= 0 then cur = s end end
      tap(cur < p.tgt and "down" or "up")
      return
    end
    if ph < 5 and (W.via == "item" or W.via == "fight") then
      W.via = "confirmed"
      local now = H.controlTaken(p.tgt)
      inFlight[p.tgt] = { f = H.frame, kind = p.plan, hp = php(p.tgt), st = now and now.name }
      cared[p.plan] = (cared[p.plan] or 0) + 1
      H.log(string.format("[care] f%d actor %d confirms the %s on slot %d (%s; #%d)",
        H.frame, a, p.plan == "hit" and "Fight" or p.plan, p.tgt, p.why, cared[p.plan]))
    end
    tap("a")
  elseif st == 0x30 or st == 0x16 or st == 0x24 or st == 0x27 or st == 0x0E or st == 0x08 then
    tap("b")                                  -- a window care never means to be in
  else
    H.setPad({})
  end
end
local function otherWindowsReset() W.actor, W.p = nil, nil end

-- What takes his command, said when it lands and when it lifts, and the
-- fail-fast: a status no cure in reach answers (Berserk, Stop, Frozen; an
-- empty bag), or one still on him DENY_MAX frames after it landed.
local taken = { since = nil, name = nil, n = 0 }
local function watchControl(what)
  local c = setzerTaken()
  if c then
    if taken.since == nil then
      taken.since, taken.name, taken.n = H.frame, c.name, taken.n + 1
      H.log(string.format("[control] f%d %s: SETZER cannot take a command: %s (#%d) | party %s",
        H.frame, what, c.name, taken.n, partyLine()))
    end
    local cure = cureOf(c)
    if cure == nil then
      error(string.format("%s: SETZER cannot take a command: %s, and nothing in reach "
        .. "cures it (%s)", what, c.name, c.items and "none of its cure items in the bag"
        or "only time clears it"), 0)
    end
    if H.frame - taken.since > DENY_MAX then
      error(string.format("%s: SETZER cannot take a command: %s, still %d frames after it "
        .. "landed (cures confirmed: %d hit, %d item, %d raise)", what, c.name,
        H.frame - taken.since, cared.hit, cared.cure, cared.raise), 0)
    end
  elseif taken.since ~= nil then
    H.log(string.format("[control] f%d %s: SETZER's %s is gone after %d frames; resuming | party %s",
      H.frame, what, taken.name, H.frame - taken.since, partyLine()))
    taken.since, taken.name = nil, nil
  end
end

local function setzerWindow()
  return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
end
local function reelsLive()
  return setzerWindow() and H.readByte(MSTATE) == 0x08
end

-- One frame of the party while Setzer waits: messages paged with A, the
-- other windows played, his own left alone unless his control is taken.
local function partyTurn(what)
  watchControl(what)
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
-- care, a cure or a Defend; a formation that falls first ends the wait,
-- and the battle is lost to the test (see `lost` below)
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
-- resolves: the spins and the party's cures (a muddled member's own
-- turns, a retaliation dump: Ot6Retaliate) can end a 745-HP fight early,
-- most of all once the Iron Fist stands alone.  The party then wins it,
-- cares, and the draw deals a fresh battle (Ot6InitBP's 1 again) for the
-- spins to be played over, at most MAX_BATTLES in the run -- as
-- battle_slots plays a fresh battle after Setzer falls.
local lost, battles, MAX_BATTLES = false, 0, 3
local done, armedOnce = false, false
local function menuFor(what)
  local hb = nil
  return H.withReset(H.driveUntil(function()
    return (setzerWindow() and setzerTaken() == nil) or fallen()
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
local function markLost(what)
  if not lost then
    lost = true
    H.log(string.format("[slotsboot] f%d %s: the formation fell before spin 3 resolved "
      .. "(battle #%d) -- this battle is lost to the test | party %s", H.frame, what,
      battles, partyLine()))
  end
end
local function stillOn(what)
  return H.call(function() if fallen() then markLost(what) end end)
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
local replays, MAX_REPLAYS = { lost = 0, dropped = 0, cancelled = 0, fell = 0 }, 3
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
        if #results > 0 then committed = true end
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
      if not committed then markLost(tag); return end
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
  end, 15000, {
    H.call(function() partyTurn(tag) end),
    H.waitFrames(1),
  }, tag), function()
    p0, b0, r0, away, hb = nil, nil, nil, false, -600
    otherWindowsReset()
  end)
end
local function resolvedSpin(tag, checks, want)
  local body = {}
  for _, s in ipairs(playedSpin(tag, checks, want)) do body[#body + 1] = s end
  body[#body + 1] = H.cond(function() return not bankShort and not lost end,
    { resolveLoop(tag .. " resolve") }, {})
  body[#body + 1] = H.call(function()
    if spinVoid then spinVoid = false end
  end)
  return H.repeatN(1, {
    H.call(function() spinVoid, spinDone = false, false end),
    H.driveUntil(function()
      return spinDone or bankShort or lost or not H.battleLoadStarted()
    end, 60000, body, tag .. ": the spin resolves"),
    H.call(function()
      if bankShort then return end
      if not spinDone then markLost(tag) end
    end),
  })
end

-- ------------------------------- spin 3: real R presses, the icon chosen
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
  }, 3)

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
        local banks, spin3Done = 0, false
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
          H.driveUntil(function() return spin3Done or lost end, 200000, {
            H.cond(function() return bp() < 3 end, { bankSpin }, {
              H.call(function() bankShort = false end),
              SPIN3,
              H.call(function()
                if bankShort then bankShort = false elseif not lost then spin3Done = true end
              end),
            }),
          }, "the bank holds 3 and spin 3 is played"),
        })
      end)(),
    }, {}),
    H.cond(function() return lost end, {
      -- the party wins the battle the spins could not finish, and cares
      H.driveUntil(function()
        return H.worldMode() and H.worldHasControl()
      end, 30000, {
        H.call(function()
          if H.battleLoadStarted() and not monstersDown() then partyTurn("lost battle")
          else H.setPad(H.frame % 8 < 4 and { a = true } or {}) end
        end),
        H.waitFrames(1),
      }, "the lost battle ends"),
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
      .. "/ %d dropped / %d cancelled / %d fell", draw.n, taken.n, cared.hit, cared.cure,
      cared.raise, replays.lost, replays.dropped, replays.cancelled, replays.fell))
  end),
})

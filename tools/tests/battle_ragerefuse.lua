-- @suite slow savestate=gau_joined
-- battle_ragerefuse.lua -- the Rage window greys every beast when GAU cannot
-- pay the flat 8, and the confirm REFUSES the pick (#225): the rage arm of
-- battle_kitrefuse's mechanism, on the third priced window with a confirm of
-- its own.
--
-- Rage is a chance verb, so its price never moves with the boost (Rage 8 /
-- 8 / 8 / 8, docs/design/mp-economy.md).  Until #225 that left Rage as the
-- one priced verb with no surface: the window drew every beast white at any
-- pool, the confirm let the pick through, the action was queued at 8 and
-- CalcAttackEffect's universal insufficient-MP fizzle ate the turn -- pool
-- untouched, no trance (Ot6RageStartGate), nothing said.  Now
-- DrawRageListText greys both columns through Ot6RageRowDecorate (the flat
-- Ot6RageCost against the pool, Ot6AbilityGrey's verdict) and the confirm
-- (btlgfx UpdateMenuState_1e @852a) asks Ot6RageConfirmMP the same question
-- and lands on vanilla's own @8548 buzz, BEFORE the confirm sound: magic's
-- shape, and the dance window's (Ot6DanceConfirmMP).  Because the price is
-- flat there is no number to draw: the whole verb is out of reach at once,
-- so every row greys together, the presentation a 0-BP SwdTech window gets.
--
-- One fixture, one Veldt battle, in battle_kitrefuse's shape:
--   1. GAU's real pool (95 at gau_joined) is pinned one MP under the flat
--      price with his own command window already up -- the file's one state
--      write, declared in tools/state_write_waivers.txt, battle_kitrefuse's
--      Steal arm verbatim: a flat price cannot be priced out by a boost, so
--      the only unaffordable Rage is a drained pool, and eleven real trances
--      is what draining 95 MP by play would cost.  The window, the grey, the
--      confirm, the queue and the buzz are all the ROM's.
--   2. the rage window: both columns read GREY off VRAM; the A press reaches
--      the window and is BUZZED ($95) with no confirm sound ($96); the window
--      is still open on the same caster and cell; $7b80 has not moved; no
--      cmd $10 reached the $3620 cost queue; bank, pending boost and pool are
--      unmoved; no trance.  A build that lets the pick through is not merely
--      asserted against: the arm rides the committed turn out and writes
--      down what it bought (a fizzle), then fails on the refusal it did not
--      see.
--   3. the real pool restored, the same window re-opened: both columns
--      WHITE, the same beast commits, cmd $10 is queued at the drawn 8, the
--      RAGE status is set and the start pays exactly 8 -- so the refusal is
--      a gate, not a wall, and Rage still works (battle_rage owns the trance
--      itself).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_TRANS, ST_CMD, ST_RAGE, ST_TGT = 0x01, 0x05, 0x1E, 0x38
local CMDTBL = 0x202E
local CMD_RAGE = 0x10
local RAGELIST, RAGECOUNT = 0x257E, 0x3A9A     -- InitSkills' flat list, its length
local RSCROLL, RCOL, RROW = 0x892B, 0x892F, 0x8933  -- the rage cursor, by slot
local QCOUNT, CLOSEFLAG = 0x7B80, 0x7BCB       -- commit counter / "close the menu"
local QCMD = 0x3A7A                            -- the command CreateAction is queuing
local GAU = 0x0B
local WHITE, GREY = 0x21, 0x25

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function raging(s) return (H.readByte(0x3EF9 + s * 2) & 0x01) ~= 0 end

-- The price, read off the ROM the way battle_kitrefuse reads Steal's:
-- Ot6RageCost is `jmp Ot6DanceCost` and Ot6DanceCost is `lda #imm / rtl`, so
-- the immediate is the one number the drawer, the confirm and the charge use.
local RAGE_COST
do
  local rage = H.sym("Ot6RageCost") & 0x3FFFFF
  local dance = H.sym("Ot6DanceCost")
  H.assertEq(H.readRomByte(rage), 0x4c, "Ot6RageCost still opens with JMP")
  H.assertEq(H.readRomWord(rage + 1), dance & 0xFFFF,
    "...to Ot6DanceCost: one price for both possess-verbs")
  H.assertEq(H.readRomByte(dance & 0x3FFFFF), 0xa9,
    "Ot6DanceCost still opens with LDA #imm -- the +1 read is the price")
  RAGE_COST = H.readRomByte((dance & 0x3FFFFF) + 1)
end

-- MonsterName glyph runs (10-byte records, $ff padded), for the VRAM
-- font-attribute read: battle_kitrefuse's attrOf idiom on the beast's name.
local MONNAME = H.sym("MonsterName") & 0x3FFFFF
local NAME_SIZE = 10
local function nameSeq(id)
  local t = {}
  for i = 0, NAME_SIZE - 1 do t[#t + 1] = H.readRomByte(MONNAME + id * NAME_SIZE + i) end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameSeq(id)) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    elseif b >= 0xb4 and b <= 0xbd then s = s .. string.char(48 + b - 0xb4)
    else s = s .. "?" end
  end
  return s
end
-- every place the run is drawn, with its attribute byte: the beast may also
-- be standing in the formation, whose name list draws the same glyphs in the
-- HUD, so the hit inside the list window ($7c00 map, where the dance and
-- rage windows stage) is the one that answers for the row.
local function attrHits(seq)
  local vr = emu.memType.snesVideoRam
  local hits = {}
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then hits[#hits + 1] = { addr = w, attr = emu.read(w * 2 + 1, vr) } end
  end
  return hits
end
local function rowAttr(id)
  local hits, inWindow, desc = attrHits(nameSeq(id)), nil, {}
  for _, h in ipairs(hits) do
    desc[#desc + 1] = string.format("$%04x:$%02x", h.addr, h.attr)
    if h.addr >= 0x7C00 and h.addr < 0x7E00 then inWindow = inWindow or h.attr end
  end
  return inWindow, table.concat(desc, " ")
end
local function fmt(a) return a and string.format("$%02x", a) or "nil" end

-- --------------------------------------------------------------- watches --
-- battle_kitrefuse's three, read at the source: the mp-cost queue
-- CreateAction writes ($3620,y, counted per command out of $3a7a), the error
-- sound ($95) and the confirm sound ($96).  Direct-page stores land in bank
-- $00, so both views of $95/$96 are watched.  A fourth watch names the
-- defect when it fires: CalcAttackEffect's entry for GAU's own action, with
-- the staged cost ($3a4c) and the pool it is about to be held against.
local seen = { [CMD_RAGE] = 0 }
local lastQ = nil
local buzzes, confirms = 0, 0
local gau = nil
local resolved = {}
-- ...and GAU's pool cell itself, every 16-bit store to it: the start's
-- charge is read off the store that makes it, not off the cell later,
-- because the bench can finish the fight in the frames between the trance
-- storing and a later read, and $3c08 reads garbage once the battle tears
-- down (measured: build/sweeps/battle_ragerefuse/attempt1/shift35.log,
-- "mp=17732 raging=true" on the world map).
local poolWrites = {}
local function armWatches()
  local poolBase = 0x7E3C08 + gau * 2
  local lo = nil
  emu.addMemoryCallback(function(addr, v)
    if (addr & 0xFFFF) == (poolBase & 0xFFFF) then lo = v
    elseif lo ~= nil then
      poolWrites[#poolWrites + 1] = { value = lo | (v << 8), frame = H.frame }
      lo = nil
    end
  end, emu.callbackType.write, poolBase, poolBase + 1)
  emu.addMemoryCallback(function(_, v)
    local c = H.readByte(QCMD)
    if seen[c] ~= nil then
      seen[c] = seen[c] + 1
      lastQ = { cmd = c, cost = v, mp = mp(gau) }
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  for _, base in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
      emu.callbackType.write, base + 0x95, base + 0x95)
    emu.addMemoryCallback(function() confirms = confirms + 1 end,
      emu.callbackType.write, base + 0x96, base + 0x96)
  end
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x == gau * 2 then
      resolved[#resolved + 1] = { cmd = H.readByte(QCMD),
        cost = H.readByte(0x3A4C), mp = mp(gau), frame = H.frame }
    end
  end, emu.callbackType.exec, H.sym("CalcAttackEffect"), H.sym("CalcAttackEffect"))
end

-- ---------------------------------------------------------------- driver --
-- battle_kitrefuse's per-frame driver on the rage window, with
-- battle_gaufight's bench: SABIN and CYAN X-cycle every window they are
-- handed and never act.  A Veldt Brawler has 27 HP and dies to one swing,
-- and arm 3 needs the fight alive until GAU's start resolves, because a
-- start whose targets are already dead stores the trance and never reaches
-- the charge.  Measured with battle_kitrefuse's right-then-A Defend bench
-- instead: on seed shift 35 that sequence queued Fights ("[queue f624] cmd
-- $00 cost 0 actor=0", build/attempts/ragerefuse/shift35_benchdefend_queue
-- .log), both Brawlers were dead at GAU's pick ("monster hp 0 0"), and the
-- first store to his pool cell was the teardown's ("MP 95 -> 7968 ... battle
-- live=false", build/sweeps/battle_ragerefuse/attempt3/shift35.log).
-- GAU follows `want.mode`:
--   idle    hold his command window open (the pin is taken there)
--   park    walk onto RAGE, open the window, steer the cursor to entry 0, hold
--   press   ...and press A there (and again in target select, which the pick
--           falls into on a build that lets it through)
--   back    B out of the window to the command window
--   defer   nothing: the trance has him
local ph, hb = 0, -900
local want = { mode = "idle" }

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local function parked()
  return H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gau
     and H.readByte(MSTATE) == ST_RAGE
     and H.readByte(RSCROLL + gau) + H.readByte(RROW + gau) == 0
     and H.readByte(RCOL + gau) == 0
end

-- who is still standing, both sides: the arm-3 timeline depends on it
local function field()
  local party, mons = {}, {}
  for s = 0, 3 do
    local m = H.readWord(0x3C1C + s * 2)
    if m > 0 and m < 9999 then
      party[#party + 1] = string.format("%d/%d", H.readWord(0x3BF4 + s * 2), m)
    end
  end
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
      mons[#mons + 1] = tostring(H.readWord(0x3BFC + m * 2))
    end
  end
  return string.format("party hp %s, monster hp %s", table.concat(party, " "),
    table.concat(mons, " "))
end

local function heartbeat()
  if H.frame - hb < 900 then return end
  hb = H.frame
  H.log(string.format("[hb f%d] mode=%s batt=%s menu=%02x actor=%s st=%02x "
    .. "mp=%s raging=%s; %s", H.frame, want.mode, tostring(H.battleLoadStarted()),
    H.readByte(MENU), tostring(H.readByte(ACTOR)), H.readByte(MSTATE),
    gau and mp(gau) or "?", gau and tostring(raging(gau)) or "?", field()))
end

local function pulse()
  ph = ph + 1
  heartbeat()
  local edge = ph % 10 < 5
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if a ~= gau then
    H.setPad((ph % 8 < 4) and { [(st == ST_CMD) and "x" or "b"] = true } or {})
    return
  end
  local btn
  if want.mode == "idle" or want.mode == "defer" then
    H.setPad({})
    return
  elseif want.mode == "back" then
    btn = (st ~= ST_CMD) and "b" or nil
  elseif st == ST_CMD then
    local cell = cmdCellOf(a, CMD_RAGE)
    assert(cell, "GAU's command list carries RAGE")
    local cur = H.readByte(CMDROW + a) & 3
    btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
  elseif st == ST_RAGE then
    if H.readByte(RCOL + gau) > 0 then btn = "left"
    elseif H.readByte(RSCROLL + gau) + H.readByte(RROW + gau) > 0 then btn = "up"
    elseif want.mode == "press" then btn = "a"
    else btn = nil end
  elseif st == ST_TGT then
    btn = (want.mode == "press") and "a" or "b"
  else
    btn = "b"
  end
  H.setPad((edge and btn) and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 20000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

local function gauCommandWindow(what)
  return step(what, function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and (H.readByte(ACTOR) & 3) == gau and H.readByte(MSTATE) == ST_CMD
  end)
end

-- ------------------------------------------------- the refusal assertion --
-- `before` is taken with the cursor parked, and carries the two columns'
-- font attributes as drawn; the confirm is then pressed, and only after the
-- press has been followed to wherever it led are the grey and the refusal
-- asserted together, so a build with neither (the pre-#225 ROM) still logs
-- the whole defect -- white rows, the pick committed, the turn spent on a
-- fizzle -- before its first failed assertion.
local before = {}
local entry0, entry1 = nil, nil
local function snapshot(label)
  local a0, d0 = rowAttr(entry0)
  local a1, d1 = nil, nil
  if entry1 ~= 0xFF then a1, d1 = rowAttr(entry1) end
  before = {
    label = label, mp = mp(gau), bp = bp(gau), pend = pend(gau),
    qcount = H.readByte(QCOUNT), seen = seen[CMD_RAGE],
    buzzes = buzzes, confirms = confirms, resolved = #resolved,
    pool = #poolWrites, attr0 = a0, attr1 = a1,
  }
  H.log(string.format("[%s] entry 0 = rage %d '%s' drawn at %s -> attr %s",
    label, entry0, nameText(entry0), d0, fmt(a0)))
  if entry1 ~= 0xFF then
    H.log(string.format("[%s] entry 1 = rage %d '%s' drawn at %s -> attr %s",
      label, entry1, nameText(entry1), d1, fmt(a1)))
  end
  H.log(string.format("[%s] parked on entry 0 (%s): mp=%d bank=%d pend=%d "
    .. "qcount=%d", label, nameText(entry0), before.mp, before.bp,
    before.pend, before.qcount))
end

local function assertGreyedAndRefused()
  local label = before.label
  H.assertEq(before.attr0, GREY, string.format(
    "%s: '%s' rendered GREY at %d MP against the flat %d -- the grey and the "
    .. "refusal below are the same Ot6AbilityGrey answer about the same "
    .. "price", label, nameText(entry0), before.mp, RAGE_COST))
  if entry1 ~= 0xFF then
    H.assertEq(before.attr1, GREY, string.format(
      "%s: '%s' (column 2) greyed too: the price is flat, so every beast is "
      .. "out of reach at once", label, nameText(entry1)))
  end
  H.log(string.format("[%s] after the confirm: mp=%d bank=%d pend=%d "
    .. "qcount=%d state=%02x actor=%02x close=%d cursor=(%d+%d,%d) "
    .. "queued(+%d) buzz(+%d) confirm(+%d) raging=%s",
    label, mp(gau), bp(gau), pend(gau), H.readByte(QCOUNT),
    H.readByte(MSTATE), H.readByte(ACTOR), H.readByte(CLOSEFLAG),
    H.readByte(RSCROLL + gau), H.readByte(RROW + gau), H.readByte(RCOL + gau),
    seen[CMD_RAGE] - before.seen, buzzes - before.buzzes,
    confirms - before.confirms, tostring(raging(gau))))
  H.assertEq(buzzes + confirms > before.buzzes + before.confirms, true,
    string.format("%s: the A press reached the rage window (one of its two "
    .. "sounds fired) -- the refusal below is a rejection and not a press "
    .. "that never arrived", label))
  H.assertEq(buzzes > before.buzzes, true, string.format(
    "%s: ...and the confirm BUZZED ($95, magic's own error sound).  The "
    .. "greyed beast was refused, as an unaffordable Blitz is", label))
  H.assertEq(confirms, before.confirms, string.format(
    "%s: ...and the confirm sound did NOT play: the rage window refuses "
    .. "BEFORE `inc $96`, vanilla magic's own shape", label))
  H.assertEq(H.readByte(MSTATE), ST_RAGE, string.format(
    "%s: the rage window is still open (menu state $1e) -- the player is "
    .. "still choosing", label))
  H.assertEq(H.readByte(ACTOR) & 3, gau, string.format(
    "%s: ...and it is still GAU's window", label))
  H.assertEq(parked(), true, string.format(
    "%s: the cursor is still on the refused cell", label))
  H.assertEq(H.readByte(CLOSEFLAG), 0, string.format(
    "%s: the window was never told to close ($7bcb)", label))
  H.assertEq(H.readByte(QCOUNT), before.qcount, string.format(
    "%s: no action was committed -- the queue counter $7b80 has not moved, "
    .. "so the TURN was not consumed", label))
  H.assertEq(seen[CMD_RAGE], before.seen, string.format(
    "%s: CreateAction never queued a cmd $10 -- nothing reached the mp-cost "
    .. "store at $3620, which is where a commit would have shown up", label))
  H.assertEq(bp(gau), before.bp, string.format(
    "%s: the BP bank is untouched", label))
  H.assertEq(pend(gau), before.pend, string.format(
    "%s: the pending boost is untouched -- refusing costs no BP", label))
  H.assertEq(mp(gau), before.mp, string.format(
    "%s: the pool is unmoved", label))
  H.assertEq(raging(gau), false, string.format(
    "%s: no trance started", label))
end

local mp0 = nil

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the Veldt"),
  -- battle_gaufight's walk: alternate left/right at tile boundaries until
  -- the world's own encounter roll wins
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}) return end
      if not H.worldAligned() then return end
      ph = ph + 1
      H.setPad({ [(ph % 2 == 0) and "left" or "right"] = true })
    end),
  }, "a Veldt encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  H.waitFrames(90),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == GAU then gau = s end
    end
    H.assertEq(gau ~= nil, true, "GAU is in this party")
    H.assertEq(cmdCellOf(gau, CMD_RAGE) ~= nil, true, "...with a RAGE row")
    H.assertEq(H.readByte(RAGECOUNT) >= 1, true, "...and a learned rage to pick")
    H.assertEq(mp(gau) >= RAGE_COST, true, string.format(
      "GAU's real pool (%d) can pay the flat %d: the control", mp(gau), RAGE_COST))
    local mons = {}
    for _, id in ipairs(H.monsterIds()) do
      if id ~= 0xFFFF then mons[#mons + 1] = string.format("%03x", id) end
    end
    H.log(string.format("GAU slot %d, mp %d, %d rages listed; formation %s",
      gau, mp(gau), H.readByte(RAGECOUNT), table.concat(mons, ",")))
    armWatches()
  end),

  -- ---- 1. the pin, with GAU's own command window up ----------------------
  gauCommandWindow("GAU's command window"),
  H.call(function()
    mp0 = mp(gau)
    H.writeWord(0x3C08 + gau * 2, RAGE_COST - 1)
    H.log(string.format("[pin] GAU's pool pinned %d -> %d, one under the flat "
      .. "price %d, with his command window up", mp0, RAGE_COST - 1, RAGE_COST))
    want.mode = "park"
  end),
  step("the rage window, cursor on entry 0", parked),
  H.waitFrames(30),

  -- ---- 2. greyed, and refused --------------------------------------------
  H.call(function()
    H.setPad({})
    entry0, entry1 = H.readByte(RAGELIST), H.readByte(RAGELIST + 1)
    snapshot("rage-7mp")
    H.screenshot("ragerefuse_grey")
    want.mode = "press"
  end),
  step("the greyed beast is confirmed: refused, or (the defect) queued",
    function() return buzzes > before.buzzes or seen[CMD_RAGE] > before.seen end,
    1800),
  H.release(),
  -- The defect's own path, so a build that lets the pick through says so in
  -- play rather than by an absence: ride the committed turn out and write
  -- down what it bought.
  H.cond(function() return seen[CMD_RAGE] > before.seen end, {
    H.call(function()
      H.log(string.format("[rage-7mp] COMMITTED: the greyed beast went through "
        .. "-- cmd $%02x queued at cost %d against pool %d, qcount %d -> %d",
        lastQ.cmd, lastQ.cost, lastQ.mp, before.qcount, H.readByte(QCOUNT)))
      want.mode = "defer"
    end),
    step("the committed rage resolves (CalcAttackEffect runs GAU's action)",
      function() return #resolved > before.resolved end, 3000),
    H.waitFrames(180),
    H.call(function()
      local r = resolved[#resolved]
      H.log(string.format("[rage-7mp] the turn bought: CalcAttackEffect ran "
        .. "GAU's action (resolved as cmd $%02x) with %d staged against a pool "
        .. "of %d -> mp %d -> %d, raging=%s, qcount %d -> %d -- the turn spent "
        .. "on a fizzle, nothing said", r.cmd, r.cost, r.mp, before.mp, mp(gau),
        tostring(raging(gau)), before.qcount, H.readByte(QCOUNT)))
    end),
  }, {}),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    want.mode = "park"
    assertGreyedAndRefused()
    H.screenshot("ragerefuse_refused")
    H.log("PASSED 2: at " .. (RAGE_COST - 1) .. " MP every beast is grey and "
      .. "the pick is refused at the confirm")
    -- restore the real pool; the arm's second and last write
    H.writeWord(0x3C08 + gau * 2, mp0)
    H.log("[pin] GAU's pool restored to the real " .. mp0)
    want.mode = "back"
  end),
  step("back out to the command window", function()
    return (H.readByte(ACTOR) & 3) == gau and H.readByte(MSTATE) == ST_CMD
  end, 1800),

  -- ---- 3. the real pool: white, and the same beast commits ---------------
  H.call(function() want.mode = "park" end),
  step("the rage window again, cursor on entry 0", parked),
  H.waitFrames(30),
  H.call(function()
    H.setPad({})
    snapshot("rage-paid")
    H.assertEq(before.attr0, WHITE, "affordable at the real pool: white")
    if entry1 ~= 0xFF then
      H.assertEq(before.attr1, WHITE, "...both columns")
    end
    H.screenshot("ragerefuse_white")
    want.mode = "press"
  end),
  step("the same beast is confirmed and queued", function()
    return seen[CMD_RAGE] > before.seen
  end, 3000),
  H.call(function()
    H.log(string.format("[rage-paid] queued: cmd $%02x cost %d at pool %d, "
      .. "qcount %d -> %d, buzz(+%d) confirm(+%d); %s", lastQ.cmd, lastQ.cost,
      lastQ.mp, before.qcount, H.readByte(QCOUNT), buzzes - before.buzzes,
      confirms - before.confirms, field()))
    H.assertEq(lastQ.cost, RAGE_COST, string.format(
      "the affordable pick DID reach CreateAction, priced %d -- arm 2's "
      .. "refusal was about the price and not about the window", RAGE_COST))
    H.assertEq(buzzes, before.buzzes, "...and no buzz this time")
    want.mode = "defer"
  end),
  step("the RAGE status is set (Cmd_10 ran the start)",
    function() return raging(gau) end, 4000),
  step("the start pays (a store to GAU's pool cell)",
    function() return #poolWrites > before.pool end, 600),
  H.call(function()
    local w = poolWrites[before.pool + 1]
    H.log(string.format("[rage-paid] MP %d -> %d at f%d, the first store to the "
      .. "pool after the pick (raging=%s, battle live=%s); %s", mp0, w.value,
      w.frame, tostring(raging(gau)), tostring(H.battleLoadStarted()), field()))
    H.assertEq(w.value, mp0 - RAGE_COST, string.format(
      "the start deducted exactly the flat %d -- the grey, the refusal and the "
      .. "charge are one number", RAGE_COST))
    H.screenshot("ragerefuse_paid")
    H.log("PASSED 3: the beast that was refused commits at the real pool and "
      .. "the trance starts -- a gate, not a wall")
  end),
})

-- @suite savestate=vargas_won slow
-- battle_walletmp.lua -- the costed submenus carry a wallet: the actor's
-- current MP painted at the top of the open list window, beside the
-- per-row costs those windows already show.
--
-- Asserts: SABIN's open Blitz list paints his current MP; after his real
-- Pummel resolves, his reopened Blitz window in the same battle shows the
-- charge deducted; EDGAR's Tools window paints his own pool, at a moment
-- when it differs from SABIN's; the vanilla Magic list carries no wallet
-- cells.
--
-- The fight is whatever the ledge deals.  The Pummel's charge is found by
-- what made it -- the write to SABIN's MP cell under his own Blitz command
-- ($b5 = $0A, X = his slot: CalcAttackEffect's universal charge, `sta
-- $3c08,x`, indexes the attacker) -- and measured from the pool that write
-- found, not from a pool read earlier.  The reopened window must be in the
-- battle the Pummel was paid in: a battle that ends first takes the drop
-- with it (a victory's level-up refills the pool, Ot6LevelUpHeal), so that
-- attempt is void and the next encounter pays again.  The bench Defends, so
-- nothing but SABIN's own Pummel hurts the pack while the arms need it up.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_MAGIC, ST_TGT = 0x05, 0x30, 0x0E, 0x38
local ST_ROW, ST_DEF = 0x24, 0x27        -- the command window's Row / Def. side windows
local CMD_MAGIC, CMD_TOOLS, CMD_BLITZ = 0x02, 0x09, 0x0A
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local SABIN, EDGAR = 0x05, 0x04
local PUMMEL, PUMMEL_COST = 0x5D, 4     -- Ot6AbilityCostTbl
local AUTOCROSSBOW = H.AUTOCROSSBOW
local WALLET = 0x7C16                    -- vram word: $7c00 map, row 0, col 22
local GLYPH_M, GLYPH_P, BLANK = 0x8C, 0x8F, 0xFF
local ZERO = 0xB4

local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

local function map() return H.mapId() & 0x1ff end
local function mpOf(slot) return H.readWord(0x3C08 + slot * 2) end
local function levelOf(charId) return H.readByte(0x1600 + 37 * charId + 8) end

-- Every write to one slot's MP cell, with what the engine had loaded when
-- it made it: the command and attack ($b5/$b6), the action's own
-- command/attack pair ($3a7c/$3a7d, what SaveForMimic records), X, and the
-- slot's STATUS2.  The callback runs before the store, so `old` is the pool
-- as the write found it; the high byte's store (a 16-bit sta) completes
-- `new`.  CalcAttackEffect's universal charge (`sta $3c08,x` @32e0) indexes
-- the attacker, so a charge is a write to the actor's own cell with X =
-- its own offset and $b5 = its command.  Measured on this fixture: SABIN's
-- Pummel is charged under $b5=$0A with $b6=$00, not the Blitz id, so the
-- command, not $b6, is what names a kit's charge ($3a7c/$3a7d = $0A/$5D
-- names which Blitz); the battle's teardown writes $FFFF under X=$23F2.
local function watchPool(slot, list)
  local lo = 0x7E3C08 + slot * 2
  emu.addMemoryCallback(function(_, v)
    local old = mpOf(slot)
    list[#list + 1] = { frame = H.frame, old = old, new = (old & 0xFF00) | v,
      cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      act = H.readWord(0x3A7C), x = emu.getState()["cpu.x"] & 0xFFFF,
      st2 = H.readByte(0x3EE5 + slot * 2) }
  end, emu.callbackType.write, lo, lo)
  emu.addMemoryCallback(function(_, v)
    local w = list[#list]
    if w and w.frame == H.frame and w.hi == nil then
      w.hi = v
      w.new = (v << 8) | (w.new & 0xFF)
    end
  end, emu.callbackType.write, lo + 1, lo + 1)
end
local function writeStr(w)
  return string.format("f%d %d->%d ($b5=%02X $b6=%02X $3a7c=%04X X=%02X STATUS2=$%02X)",
    w.frame, w.old, w.new, w.cmd, w.atk, w.act, w.x, w.st2)
end
-- the first write after index `from` that is `slot`'s own `cmd` charging
-- its own cell
local function chargeOf(list, from, slot, cmd)
  for i = from + 1, #list do
    local w = list[i]
    if w.cmd == cmd and w.x == slot * 2 then return i end
  end
  return nil
end

local function walletWords()
  local t = {}
  for i = 0, 4 do
    t[i + 1] = emu.readWord((WALLET + i) * 2, emu.memType.snesVideoRam)
  end
  return t
end

-- expected wallet glyphs for a value (leading zeros blank, ones always)
local function expect(v)
  local h, t = math.floor(v / 100) % 10, math.floor(v / 10) % 10
  local gh = (h == 0) and BLANK or (ZERO + h)
  local gt = (t == 0 and h == 0) and BLANK or (ZERO + t)
  return { GLYPH_M, GLYPH_P, gh, gt, ZERO + v % 10 }
end

local function assertWallet(tag, v)
  local w, e = walletWords(), expect(v)
  local got = {}
  for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
  H.log(string.format("%s: wallet vram = %s (MP=%d)", tag, table.concat(got, " "), v))
  for i = 1, 5 do
    H.assertEq(w[i] & 0xFF, e[i], string.format("%s: wallet cell %d glyph", tag, i))
    H.assertEq(w[i] >> 8, 0x21, string.format("%s: wallet cell %d white", tag, i))
  end
end

-- ------------------------------------------------------------------------
-- driven by a mode table: reach `char`'s window for command `cmd`, then
-- either hold the target state open or pick `entry` and confirm.
-- Bystanders Defend (RIGHT opens the Def. window, A commits it): a turn
-- spent and no monster hurt, so the battle outlasts the arms that need it.
-- Dialogs are paged.
-- ------------------------------------------------------------------------
local slotOf = {}
local mode = nil          -- { char=, cmd=, state=, hold=true } or { cast=id }
local ph, hb, lane = 0, -600, nil
-- battles entered so far (a rising edge of battleLoadStarted), so an arm
-- can tell "the same battle" from "the next one"
local battleNo, wasLive = 0, false
local function tickBattle()
  local live = H.battleLoadStarted()
  if live and not wasLive then
    battleNo = battleNo + 1
    H.log(string.format("[battle %d f%d] a battle loads", battleNo, H.frame))
  end
  wasLive = live
end
local sabinWrites, edgarWrites = {}, {}
local holdBlank = 0        -- frames a held costed window has shown a blank wallet
local WALLET_SETTLE = 90   -- frames the wallet needs to settle after a reopen
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  tickBattle()
  if H.frame - hb >= 600 then
    hb = H.frame
    H.log(string.format("[hb f%d] batt=%s menu=%02x actor=%d mstate=%02x wallet=%04x",
      H.frame, tostring(H.battleLoadStarted()), H.readByte(MENU),
      H.readByte(ACTOR), H.readByte(MSTATE), walletWords()[1]))
  end
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil          -- re-anchor the lane at wherever the next field return
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})     -- page battle dialogs
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= slotOf[mode.char] then
    local st = H.readByte(MSTATE)
    if st == ST_CMD then
      H.setPad(edge and { right = true } or {})       -- open the Def. window
    elseif st == ST_DEF then
      H.setPad(edge and { a = true } or {})           -- commit the Defend
    elseif st == ST_ROW or st == ST_TGT or st == ST_TOOLS or st == ST_MAGIC then
      H.setPad(edge and { b = true } or {})           -- not a bystander's window
    else
      H.setPad({})                                    -- the engine between windows
    end
    return
  end
  local st = H.readByte(MSTATE)
  if st ~= mode.state then holdBlank = 0 end
  if st == mode.state and mode.hold then
    local w = walletWords()
    if (w[1] & 0xFF) == GLYPH_M and (w[2] & 0xFF) == GLYPH_P then
      holdBlank = 0
      H.setPad({})
      return
    end
    holdBlank = holdBlank + 1
    if holdBlank < WALLET_SETTLE then H.setPad({}) return end
    H.setPad(ph % 10 < 5 and { b = true } or {})   -- reopen fresh to re-stage
    return
  end
  if st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == mode.cmd then wantCell = i end
    end
    assert(wantCell, string.format("char %d's real command list carries $%02x",
      mode.char, mode.cmd))
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  elseif st == ST_TOOLS and mode.cast then
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == mode.cast then entry = i end
    end
    if entry == nil then H.setPad({}) return end
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else H.setPad(edge and { a = true } or {}) end
  elseif st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == 0x01 then
    H.setPad({})
  else
    H.setPad(edge and { b = true } or {})
  end
end

local function reachWindow(m, what)
  return H.repeatN(1, {
    H.call(function() mode = m end),
    H.driveUntil(function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == slotOf[m.char]
         and H.readByte(MSTATE) == m.state
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),                   -- let the wallet stage + flush
  })
end

local function settleWallet(tag)
  return H.driveUntil(function()
    if not (H.battleLoadStarted() and H.readByte(MENU) ~= 0
            and H.readByte(ACTOR) == slotOf[mode.char]
            and H.readByte(MSTATE) == mode.state) then return false end
    local w = walletWords()
    return (w[1] & 0xFF) == GLYPH_M and (w[2] & 0xFF) == GLYPH_P
  end, 30000, { H.call(pulse), H.waitFrames(1) },
    tag .. ": the wallet header paints")
end

local sabinPre = nil

-- 2. the drop, one attempt: a real Pummel from SABIN's window, found by its
-- own charge write, then his next Blitz window IN THE SAME BATTLE.  The
-- attempt is void (not failed) when that battle ends before his window
-- comes back -- the Pummel or the bench's luck finished the pack -- and
-- the next attempt pays again in the next encounter.
local DROP_TRIES = 4
local drop = { done = false }
local function dropAttempt(k)
  local tag = string.format("attempt %d/%d", k, DROP_TRIES)
  return H.cond(function() return drop.done end, {}, {
    H.call(function() drop.charge, drop.battle = nil, nil end),
    reachWindow({ char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, cast = PUMMEL },
      "sabin's blitz window (casting, " .. tag .. ")"),
    H.call(function()
      drop.battle, drop.level, drop.from = battleNo, levelOf(SABIN), #sabinWrites
    end),
    H.driveUntil(function()
      drop.charge = chargeOf(sabinWrites, drop.from, slotOf[SABIN], CMD_BLITZ)
      return drop.charge ~= nil or battleNo ~= drop.battle
        or not H.battleLoadStarted()
    end, 20000, { H.call(pulse), H.waitFrames(1) },
      "the Pummel charge lands (" .. tag .. ")"),
    H.call(function()
      -- whatever came of it, SABIN's next window is held, not spent again
      mode = { char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, hold = true }
      local c = drop.charge and sabinWrites[drop.charge]
      if c == nil then
        local all = {}
        for i = drop.from + 1, #sabinWrites do all[#all + 1] = writeStr(sabinWrites[i]) end
        H.log(string.format("[drop %s] no charge under $b5=%02X X=%02X; SABIN's pool "
          .. "writes since the window: %s", tag, CMD_BLITZ, slotOf[SABIN] * 2,
          #all > 0 and table.concat(all, ", ") or "none"))
      end
      H.assertEq(c ~= nil, true, "[drop " .. tag .. "] the queued Pummel was "
        .. "charged in the battle it was chosen in")
      local moves = {}
      for i = drop.from + 1, drop.charge - 1 do moves[#moves + 1] = writeStr(sabinWrites[i]) end
      H.log(string.format("[drop %s] battle %d: the charge %s; %d earlier write(s) "
        .. "since the window%s", tag, drop.battle, writeStr(c), #moves,
        #moves > 0 and (": " .. table.concat(moves, ", ")) or ""))
      H.assertEq(c.act, CMD_BLITZ | (PUMMEL << 8),
        "[drop] the charged action is his Blitz Pummel ($3a7c/$3a7d = $0A/$5D)")
      H.assertEq(c.old - c.new, PUMMEL_COST,
        "Pummel charged exactly its table price from the pool the charge found")
    end),
    H.driveUntil(function()
      if battleNo ~= drop.battle or not H.battleLoadStarted() then return true end
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[SABIN]
         and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, { H.call(pulse), H.waitFrames(1) },
      "the payer's blitz window reopens, or the battle ends (" .. tag .. ")"),
    H.cond(function() return battleNo == drop.battle and H.battleLoadStarted() end, {
      H.waitFrames(20),                   -- let the wallet stage + flush
      settleWallet("post-charge reopen"),
      H.call(function()
        local c = sabinWrites[drop.charge]
        local after = {}
        for i = drop.charge + 1, #sabinWrites do after[#after + 1] = writeStr(sabinWrites[i]) end
        local now = mpOf(slotOf[SABIN])
        H.log(string.format("[drop %s] reopened in battle %d at pool %d (level %d, "
          .. "was %d at the charge); %d write(s) since the charge%s", tag,
          battleNo, now, levelOf(SABIN), drop.level, #after,
          #after > 0 and (": " .. table.concat(after, ", ")) or ""))
        H.assertEq(H.readByte(ACTOR), slotOf[SABIN],
          "the reopened list belongs to the character who paid")
        H.assertEq(levelOf(SABIN), drop.level,
          "[drop] no level-up between the charge and the reopen (same battle)")
        assertWallet("post-charge reopen", now)
        -- the pool the wallet shows is the one the charge left, unless the
        -- engine moved it since (listed above), in which case it is the
        -- one that last write left: the wallet follows the live pool
        local last = sabinWrites[#sabinWrites]
        H.assertEq(now, last.new, "the reopened pool is the engine's last write to it")
        if #after == 0 then
          H.assertEq(now, c.old - PUMMEL_COST,
            "the reopened wallet shows the drop -- the real cast's price, in "
            .. "the payer's own window")
        end
        drop.done = true
      end),
    }, {
      H.call(function()
        H.log(string.format("[drop %s] void: battle %d ended before SABIN's next "
          .. "window (now battle %d, live=%s, level %d, was %d); the next "
          .. "encounter pays again", tag, drop.battle, battleNo,
          tostring(H.battleLoadStarted()), levelOf(SABIN), drop.level))
      end),
    }),
  })
end

-- 3. the second caster, one attempt: EDGAR's own Tools window paints HIS
-- pool.  The per-actor claim needs two different numbers on screen, and
-- which two the fight leaves is the fight's business, so when his window
-- opens on a pool equal to SABIN's he spends a priced tool first (his
-- AutoCrossbow, found by its own charge write) and the next window is the
-- one read.
local EDGAR_TRIES = 3
local ed = { done = false }
local function edgarAttempt(k)
  local tag = string.format("attempt %d/%d", k, EDGAR_TRIES)
  return H.cond(function() return ed.done end, {}, {
    reachWindow({ char = EDGAR, cmd = CMD_TOOLS, state = ST_TOOLS, hold = true },
      "edgar's tools window (" .. tag .. ")"),
    settleWallet("edgar"),
    H.call(function()
      local e, s = mpOf(slotOf[EDGAR]), mpOf(slotOf[SABIN])
      assertWallet("edgar", e)
      if e ~= s then
        local w, other = walletWords(), expect(s)
        local same = true
        for i = 3, 5 do if (w[i] & 0xFF) ~= other[i] then same = false end end
        H.log(string.format("[edgar %s] EDGAR %d, SABIN %d", tag, e, s))
        H.assertEq(same, false,
          "and it is not Sabin's number -- the wallet is per-actor")
        H.screenshot("walletmp_tools")
        ed.done = true
      else
        H.log(string.format("[edgar %s] both pools read %d: EDGAR spends an "
          .. "AutoCrossbow so the two differ", tag, e))
        local has = false
        for i = 0, 7 do
          if H.readByte(ITEMLIST + i * 3) == AUTOCROSSBOW then has = true end
        end
        H.assertEq(has, true, "EDGAR's real Tools list carries the AutoCrossbow")
        ed.from = #edgarWrites
        mode = { char = EDGAR, cmd = CMD_TOOLS, state = ST_TOOLS, cast = AUTOCROSSBOW }
      end
    end),
    H.cond(function() return not ed.done end, {
      H.driveUntil(function()
        return chargeOf(edgarWrites, ed.from, slotOf[EDGAR], CMD_TOOLS) ~= nil
      end, 20000, { H.call(pulse), H.waitFrames(1) },
        "EDGAR's AutoCrossbow is charged (" .. tag .. ")"),
      H.call(function()
        local c = edgarWrites[chargeOf(edgarWrites, ed.from, slotOf[EDGAR], CMD_TOOLS)]
        H.log(string.format("[edgar %s] the charge %s", tag, writeStr(c)))
      end),
    }, {}),
  })
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    H.assertEq(costOf(PUMMEL), PUMMEL_COST,
      "Pummel's charge-table price is the 4 this file's drop arm counts on")
  end),

  -- natural encounter: walk a lane until a random battle fires
  (function()
    local lane = nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 12600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a ledge encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[SABIN], "SABIN present (vargas_won party)")
    assert(slotOf[EDGAR], "EDGAR present (vargas_won party)")
    assert(slotOf[0x00], "TERRA present (the innate mage for the magic arm)")
    H.log(string.format("SABIN slot %d pool %d, EDGAR slot %d pool %d",
      slotOf[SABIN], mpOf(slotOf[SABIN]), slotOf[EDGAR], mpOf(slotOf[EDGAR])))
    watchPool(slotOf[SABIN], sabinWrites)
    watchPool(slotOf[EDGAR], edgarWrites)
  end),

  -- 1. the wallet on SABIN's real Blitz window ------------------------------
  reachWindow({ char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, hold = true },
    "sabin's blitz window"),
  settleWallet("sabin"),
  H.call(function()
    sabinPre = mpOf(slotOf[SABIN])
    assertWallet("sabin", sabinPre)
    H.screenshot("walletmp_blitz")
  end),

  -- 2. the drop: a real Pummel, then the payer's own reopened window --------
  (function()
    local steps = {}
    for k = 1, DROP_TRIES do steps[#steps + 1] = dropAttempt(k) end
    steps[#steps + 1] = H.call(function()
      H.assertEq(drop.done, true, string.format("the Pummel's drop was read in "
        .. "the payer's reopened window within %d encounters", DROP_TRIES))
    end)
    return H.repeatN(1, steps)
  end)(),

  -- 3. the second caster: EDGAR's Tools window paints EDGAR's pool ----------
  (function()
    local steps = {}
    for k = 1, EDGAR_TRIES do steps[#steps + 1] = edgarAttempt(k) end
    steps[#steps + 1] = H.call(function()
      H.assertEq(ed.done, true, string.format("EDGAR's window was read on a pool "
        .. "different from SABIN's within %d windows", EDGAR_TRIES))
    end)
    return H.repeatN(1, steps)
  end)(),

  reachWindow({ char = 0x00, cmd = CMD_MAGIC, state = ST_MAGIC, hold = true },
    "terra's magic list (browse $0e)"),
  H.call(function()
    local w = walletWords()
    local got = {}
    for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
    H.log("magic window wallet cells: " .. table.concat(got, " "))
    for i = 1, 5 do
      -- the magic window fills this area itself; the wallet glyph must not survive
      H.assertEq(w[i] & 0xFF, 0xFF, string.format(
        "magic list cell %d carries no wallet glyph -- blanked on switch", i))
    end
    H.screenshot("walletmp_magic_clean")
  end),
  H.logStep(function() return "battle_walletmp complete -- the wallet paints "
    .. "each caster's own SPENT pool and leaves the magic list clean" end),
})

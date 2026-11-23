-- @suite slow
-- battle_relmwor.lua -- RELM's whole list in the World of Ruin (#538):
-- Masterpiece, Varnish, Gesture and its loop limit, Underpainting and Still
-- Life, and GOGO's Sketch opening her list (#547).
--
-- docs/design/kit-relm.md.  At wor-gogo-v1 (TERRA, STRAGO, RELM, GOGO on the
-- world map past the Zone Eater) RELM is past level 42 and Strago's return,
-- so every row is learned.  Played: Continue, lap two world tiles into
-- random battles; the plan's turns go through the real menus (H.kitBattle),
-- the others Defend (care from the bag as needed).  Stages, one battle each:
--   1. the list: all eight rows packed in the table's order at their prices;
--      Masterpiece at two points pending greyed and refused at the list;
--   2. Masterpiece at three points: every other ally standing holds the gift
--      (OT6_GIFT), 99 MP, three points from the bank;
--   3. Varnish on an ally: the first enemy hit that would land on her is
--      turned (it reaches Ot6VarnishGate a hit and leaves a miss), the coat
--      is spent, and her HP did not drop to that action;
--   4. Gesture on TERRA after her turn: her gauge, low, is full within a few
--      frames, she holds the Gesture mark, and her granted turn's end
--      clears it;
--   5. RELM Gestures GOGO after his turn; on the turn it gives him, his
--      Sketch (one declared command byte, below) opens RELM's list (mode 5,
--      her eight rows), and its Gesture row is greyed and refused (no
--      Gesture off a Gestured turn);
--   6. Underpainting on a body, Tint on TERRA in a colour it is weak to,
--      TERRA's Fight: the first weakness chip on it took two shields, and
--      the mark is spent;
--   7. Still Life on a body, TERRA's Break spell until it breaks, Still
--      Life again once the break is held: the break lasted 32 ticks (its 16
--      and Still Life's 16, OT6_BROKEN_TICKS), and the second mark, laid
--      while the break is held, waits for the next break (a draw that keeps
--      RELM's second cast in the queue until the hold has ended lays no
--      mark during it: that battle is not counted);
--   8. Tint on RELM herself: once her casting action has ended she holds
--      all four turns (OT6_TINT_TURNS), as an ally would (#538 review: the
--      casting action's own end counted one down; the replay read 3 on a
--      ROM without the fix).  Read 60 frames after her action's end: an
--      action's end can straddle a frame, and reads at its entry frame saw
--      the count before the decrement (4 without the fix, 5 with it,
--      build/attempts/wt/v047-noretarget/suites/b5, b6);
--   9. Varnish on TERRA by a RELM who cannot pay: her MP is written one
--      under the price as her action begins (a declared write: the drop an
--      enemy's Rasp or Osmose makes between her confirm and her turn), and
--      the row lands nothing -- no coat -- and the MP check refuses it,
--      charging nothing (#538 review: the row landed first, unpaid);
--  10. a coat spent by a counter leaves its "this action spent the coat"
--      mask (OT6_VARNISHING) standing, since a counter reaches no action
--      end: staged as a declared write of that mask as a monster's action
--      begins, which must clear it before the action runs (#538 review: the
--      next enemy action missed too).
-- The one write: GOGO's Lore command slot becomes Sketch in his record
-- before the first battle (state_write_waivers.txt; the battle_mimic
-- expedient: the line never gives him Sketch, and the field menu that would
-- is not what this suite tests).  Everything after is the engine's own.
-- A battle where a stage cannot be played is fought out and the next taken.
-- Old-ROM red and mutants: build/attempts/wt/v047-relm/suites/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, RELM, GOGO = 0x00, 0x08, 0x0C
local CMD, FIGHT, MAGIC, LORE = 0x0D, 0x00, 0x02, 0x0C
local SKETCH, PORTRAIT, TINT, VARNISH, STILL, UNDER, GESTURE, MASTER = 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF
local COLOUR, BREAK = 0xF0, 0x0C
local ORDER = { SKETCH, PORTRAIT, TINT, VARNISH, STILL, UNDER, GESTURE, MASTER }
local PRICE = { [SKETCH] = 0, [PORTRAIT] = 12, [TINT] = 10, [VARNISH] = 14, [STILL] = 24, [UNDER] = 28,
  [GESTURE] = 30, [MASTER] = 99 }
local GIFT, VARN, GEST, SMARK, SHELD, UPAINT = 0xEF0E, 0xEF0F, 0xEF11, 0xEF12, 0xEF13, 0xEF14
local VARNING, TINTN, TINT_TURNS, LAST = 0xEF10, 0xEEFE, 4, 10
local BUDGET = 40

local function seatOf(ch) for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == ch then return s end end end
local function up(s)
  return s ~= nil and (H.readByte(0x3AA0 + s * 2) & 1) == 1 and H.readWord(0x3BF4 + s * 2) > 0
    and (H.readByte(0x3EE4 + s * 2) & 0xC2) == 0 and (H.readByte(0x3EE5 + s * 2) & 0xB0) == 0
end
local function monUp(s) return (H.readByte(0x3A75) >> s) & 1 == 1 end
local function recCmd(c, r) return 0x1600 + 37 * c + 0x16 + r end
local function shields(s) return H.readByte(0x3E38 + 8 + s * 2) end
local function ticks(s) return H.readByte(0x3E88 + 8 + s * 2) end

local stage, battles, mode, plan = 1, 0, nil, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local rec, seen = {}, nil
local relm, terra, gogo, ally, target, colour = nil, nil, nil, nil, nil, nil

-- the screenshots of each effect's mark, one each: name -> the frame to take it
local shotAt, shotDone = {}, {}
local function shoot(name, delay) if not shotDone[name] then shotAt[name] = H.frame + delay end end
local function arm()
  emu.addEventCallback(function()
    for name, f in pairs(shotAt) do
      if H.frame >= f then shotAt[name], shotDone[name] = nil, true; H.screenshot(name) end
    end
  end, emu.eventType.endFrame)
  emu.addMemoryCallback(function(_, v)
    if v & 0xFF ~= 0 and stage == 6 then shoot("relmwor_underpaint", 20) end
  end, emu.callbackType.write, 0x7E0000 + UPAINT, 0x7E0000 + UPAINT)
  emu.addMemoryCallback(function(_, v)
    if v ~= 0 and stage == 7 then shoot("relmwor_stilllife_mark", 20) end
    -- stage 7: each mark laid on the body, and whether its break was held as it landed
    if stage == 7 and target ~= nil and (v >> target) & 1 == 1 and (rec.smark or 0) & (1 << target) == 0 then
      rec.marks = rec.marks or {}
      rec.marks[#rec.marks + 1] = { f = H.frame, held = (H.readByte(SHELD) >> target) & 1 == 1 }
    end
    if stage == 7 then rec.smark = v end
  end, emu.callbackType.write, 0x7E0000 + SMARK, 0x7E0000 + SMARK)
  emu.addMemoryCallback(function(_, v)
    if v ~= 0 and stage == 7 then shoot("relmwor_stilllife_held", 20) end
    if stage == 7 and target ~= nil and (v >> target) & 1 == 1 and rec.heldAt == nil then rec.heldAt = H.frame end
  end, emu.callbackType.write, 0x7E0000 + SHELD, 0x7E0000 + SHELD)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if stage == 2 and H.readByte(0xB6) == MASTER then shoot("relmwor_masterpiece", 90) end
    if stage == 4 and H.readByte(0xB6) == GESTURE then shoot("relmwor_gesture", 30) end
    if stage == 9 and relm ~= nil and x == relm * 2 and H.readByte(0xB6) == VARNISH and rec.starved == nil then
      -- the declared write (stage 9): her MP one under the row's price, the
      -- cost already staged in $3A4C
      rec.starved = { f = H.frame, mp = PRICE[VARNISH] - 1, cost = H.readWord(0x3A4C), coat0 = H.readByte(VARN) }
      H.writeWord(0x3C08 + x, PRICE[VARNISH] - 1)
    end
    -- RELM's Gesture is executing: the $FF its apply writes to the ally's
    -- gauge byte is told from the engine's own (the turn's reset as an
    -- action starts) by this, up to her action's end
    if relm ~= nil and x == relm * 2 and H.readByte(0xB6) == GESTURE then rec.gestLive = H.frame end
    rec.execs = rec.execs or {}
    rec.execs[#rec.execs + 1] = { x = x, id = H.readByte(0xB6), b8 = H.readByte(0xB8), b9 = H.readByte(0xB9),
      mp0 = H.readWord(0x3C08 + x), bank0 = H.readByte(0x3E9C + x), pend0 = H.readByte(0x3E9D + x), f = H.frame }
  end, emu.callbackType.exec, H.sym("Ot6PaintExec"), H.sym("Ot6PaintExec"))
  -- stage 10: a monster's action begins with the leaked mask (the declared
  -- write), and ExecCmd's next instruction after Ot6BpBegin reads it
  local bb, after = H.sym("Ot6BpBegin"), H.sym("ExecCmd@battle_code") + 4
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if stage == 10 and x >= 8 and rec.leakArmed == nil and H.battleActive() then
      rec.leakArmed = { f = H.frame, x = x }
      H.writeByte(VARNING, 0x0F)
    end
  end, emu.callbackType.exec, bb, bb)
  emu.addMemoryCallback(function()
    if stage == 10 and rec.leakArmed ~= nil and rec.leak == nil then
      rec.leak = { f = H.frame, v = H.readByte(VARNING) }
    end
  end, emu.callbackType.exec, after, after)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    rec.ends = rec.ends or {}
    rec.ends[#rec.ends + 1] = { x = x, f = H.frame, gest = H.readByte(GEST) }
    -- stage 4: TERRA's gauge as RELM's Gesture ends (full: $00, or $FF the
    -- tick before it carries); a Gesture that fills nothing leaves it where
    -- her own fill had it
    if stage == 4 and relm ~= nil and terra ~= nil and x == relm * 2 and rec.gestLive ~= nil
       and rec.gaugeAtEnd == nil then
      rec.gaugeAtEnd = H.readByte(0x3219 + terra * 2)
    end
    if relm ~= nil and x == relm * 2 then rec.gestLive = nil end
    if stage == 5 and gogo ~= nil and relm ~= nil and x == relm * 2 and rec.giveUp == nil then
      local ex = rec.execs and rec.execs[#rec.execs]
      if ex ~= nil and ex.x == x and ex.id == GESTURE and not ex.ended then
        ex.ended = true
        H.log(string.format("[relmwor] RELM's Gesture ended f%d: marks $%02X, GOGO's gauge $%02X, queue $%02X",
          H.frame, H.readByte(GEST), H.readByte(0x3219 + gogo * 2), H.readByte(0x32CC + gogo * 2)))
        if (H.readByte(GEST) >> gogo) & 1 == 0 then
          H.log("[relmwor] the Gesture found GOGO's turn already full or queued: not counted")
          rec.giveUp = true
        end
      end
    end
  end, emu.callbackType.exec, ae, ae)
  -- every hit judged against the varnished ally: the stack at the gate's
  -- entry holds CheckHit's P (sp+4, carry = a miss) and the attacker (sp+5)
  local vg = H.sym("Ot6VarnishGate")
  emu.addMemoryCallback(function()
    if ally == nil or stage ~= 3 or rec.varnishedAt == nil then return end
    local st = emu.getState()
    local sp = st["cpu.sp"]
    local p, att, y = emu.read(sp + 4, emu.memType.snesMemory), emu.read(sp + 5, emu.memType.snesMemory),
      st["cpu.y"] & 0xFF
    if y ~= ally * 2 or att < 8 or (p & 1) == 1 or rec.turned ~= nil then return end
    rec.turned = { f = H.frame, att = att, coat = H.readByte(VARN) & (1 << ally), hp0 = H.readWord(0x3BF4 + y) }
    shoot("relmwor_varnish_miss", 25)
  end, emu.callbackType.exec, vg, vg)
  emu.addMemoryCallback(function(_, v)
    if stage == 3 and ally ~= nil and (v >> ally) & 1 == 1 and rec.varnishedAt == nil then rec.varnishedAt = H.frame end
  end, emu.callbackType.write, 0x7E0000 + VARN, 0x7E0000 + VARN)
  emu.addMemoryCallback(function(addr, v)
    if stage ~= 4 or terra == nil or addr ~= 0x7E3219 + terra * 2 then return end
    -- only while RELM's Gesture runs: TERRA's own turn also writes $FF here
    -- (the gauge reset as her action starts), which on the v0.47 replay's
    -- draw came first and was read as the Gesture (build/attempts/
    -- wt/v047-noretarget/suites/b4: "mark $00 then ... mark $00 at its end")
    -- and before her Gesture mark: Ot6PaintApply writes the gauge, then the
    -- mark (a write after the mark is the engine's; the gesture_fill mutant
    -- passed on one: build/attempts/wt/v047-noretarget/relmmut2/)
    if v == 0xFF and rec.gestured == nil and rec.gestLive ~= nil and (H.readByte(GEST) >> terra) & 1 == 0 then
      rec.gestured = { f = H.frame, gest = H.readByte(GEST), was = rec.gauge }
    elseif v == 0 and rec.gestured ~= nil and rec.full == nil then
      rec.full = H.frame      -- actioncounter's carry: the gauge is full
    end
    rec.gauge = v
  end, emu.callbackType.write, 0x7E3219, 0x7E3219 + 6)
  emu.addMemoryCallback(function(addr, v)
    if target == nil or addr ~= 0x7E3E38 + 8 + target * 2 then return end
    rec.sh = rec.sh or {}
    rec.sh[#rec.sh + 1] = { v = v, f = H.frame, under = H.readByte(UPAINT) }
  end, emu.callbackType.write, 0x7E3E40, 0x7E3E40 + 10)
  emu.addMemoryCallback(function(addr, v)
    if target == nil or addr ~= 0x7E3E88 + 8 + target * 2 then return end
    rec.tk = rec.tk or {}
    rec.tk[#rec.tk + 1] = { v = v, f = H.frame, held = H.readByte(SHELD), mark = H.readByte(SMARK) }
  end, emu.callbackType.write, 0x7E3E90, 0x7E3E90 + 10)
  local fb = H.sym("Ot6FightBoost")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if terra ~= nil and x == terra * 2 and target ~= nil and rec.fight == nil then
      rec.fight = { f = H.frame, sh = shields(target), under = H.readByte(UPAINT) }
    end
  end, emu.callbackType.exec, fb, fb)
end

local function onList(p, a)
  if seen ~= nil or (stage == 5 and H.readByte(0x3ED8 + a * 2) ~= GOGO) then return end
  seen = { mode = H.readByte(0x6168), who = H.readByte(0x3ED8 + a * 2), cells = {} }
  for i = 0, 7 do seen.cells[i] = { id = H.readByte(0x4005 + i * 3), qty = H.readByte(0x4006 + i * 3) } end
  H.screenshot("relmwor_list_" .. stage)
end

local function lastExec(x, id)
  for i = #(rec.execs or {}), 1, -1 do
    local e = rec.execs[i]
    if e.x == x and (id == nil or e.id == id) then return e end
  end
end
-- (an end counts 10 frames after its hook: Ot6ActionEnd's BP consume can land a frame or more after its entry,
-- and a judge reading the bank at once saw it unpaid: the v0.48 line's stage 2, '[lab] f13493 ActionEnd x=2
-- ... pend=3 bank=3' then 'Masterpiece at 3 pending: ... bank 3 -> 3' at f13494)
local function endsOf(x, after)
  local n = {}
  for _, e in ipairs(rec.ends or {}) do
    if e.x == x and e.f > (after or 0) and e.f + 10 <= H.frame then n[#n + 1] = e end
  end
  return n
end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= BUDGET, true, string.format("the ten stages within %d battles", BUDGET))
  plan, mode, rec, seen, ally, target, colour = {}, "fightout", {}, nil, nil, nil, nil
  relm, terra, gogo = seatOf(RELM), seatOf(TERRA), seatOf(GOGO)
  if not up(relm) or H.readWord(0x3C08 + relm * 2) < 120 or not up(terra) then
    H.log("[relmwor] RELM or TERRA cannot act here (down, or RELM short of MP): fought out")
    return
  end
  local alive = 0
  for s = 0, 5 do if monUp(s) then alive = alive + 1 end end
  if stage == 1 then
    plan = { { who = RELM, cmd = CMD, row = GESTURE, peek = true },
             { who = RELM, cmd = CMD, row = MASTER, boost = 2, refused = "list" } }
  elseif stage == 2 then
    plan = { { who = RELM, cmd = CMD, row = MASTER, boost = 3, self = true } }
  elseif stage == 3 then
    ally = terra
    plan = { { who = RELM, cmd = CMD, row = VARNISH, allySeat = ally } }
  elseif stage == 4 then
    plan = { { who = TERRA, defend = true }, { who = RELM, cmd = CMD, row = GESTURE, allySeat = terra } }
  elseif stage == 5 then
    if not up(gogo) then H.log("[relmwor] GOGO cannot act: fought out"); return end
    -- RELM holds her window until GOGO's Defend has resolved and his gauge
    -- is filling again (a full or queued turn is one a Gesture passes
    -- over); his granted turn then opens her list through his Sketch
    plan = { { who = GOGO, defend = true },
             { who = RELM, cmd = CMD, row = GESTURE, allySeat = gogo, hold = true, when = function()
                 return #endsOf(gogo * 2, 0) > 0 and H.readByte(0x32CC + gogo * 2) == 0xFF
                   and H.readByte(0x3219 + gogo * 2) ~= 0
               end },
             { who = GOGO, cmd = CMD, row = GESTURE, refused = "list",
               when = function() return (H.readByte(GEST) >> gogo) & 1 == 1 end,
               skip = function() return rec.giveUp == true end } }
  elseif stage == 6 then
    local wpn = H.readByte(0x3B90 + terra * 2) | H.readByte(0x3B91 + terra * 2)
    for s = 0, 5 do
      local e = 8 + s * 2
      local ok = H.readByte(0x3BE0 + e) & ~H.readByte(0x3BCC + e) & ~H.readByte(0x3BCD + e) & ~wpn & 0xFF
      if monUp(s) and ok ~= 0 and ticks(s) == 0 and shields(s) >= 3 then
        for b = 0, 7 do if (ok >> b) & 1 == 1 then colour = b; break end end
        target = s
        break
      end
    end
    if target == nil then H.log("[relmwor] no body with three shields weak to a colour TERRA lacks: fought out"); return end
    plan = { { who = RELM, cmd = CMD, row = UNDER, slot = target },
             { who = RELM, cmd = CMD, row = TINT, row2 = COLOUR + colour, allySeat = terra },
             { who = TERRA, cmd = FIGHT, boost = 0, slot = target } }
  elseif stage == 8 then
    plan = { { who = RELM, cmd = CMD, row = TINT, row2 = COLOUR, allySeat = relm } }
  elseif stage == 9 then
    if (H.readByte(VARN) >> terra) & 1 == 1 then H.log("[relmwor] TERRA holds a coat already: fought out"); return end
    plan = { { who = RELM, cmd = CMD, row = VARNISH, allySeat = terra } }
  elseif stage == 10 then
    plan = {}
  else
    local best
    for s = 0, 5 do
      if monUp(s) and ticks(s) == 0 and shields(s) >= 1 and shields(s) <= 8
         and (best == nil or H.readWord(0x3BF4 + 8 + s * 2) > H.readWord(0x3BF4 + 8 + best * 2)) then best = s end
    end
    if best == nil then H.log("[relmwor] no shielded body: fought out"); return end
    target = best
    plan = { { who = RELM, cmd = CMD, row = STILL, slot = target } }
    for _ = 1, math.ceil(shields(target) / 4) do
      plan[#plan + 1] = { who = TERRA, cmd = MAGIC, spell = BREAK, boost = 3, slot = target }
    end
  end
  mode = "play"
  H.log(string.format("[relmwor] battle %d stage %d: seats RELM %d TERRA %d GOGO %s; body %s (%s shields), colour %s, "
    .. "%d bodies", battles, stage, relm, terra, tostring(gogo), tostring(target),
    target and tostring(shields(target)) or "-", tostring(colour), alive))
end

local function broken() return target ~= nil and ticks(target) > 0 end
local function closed()
  if rec.giveUp then return true end
  if stage == 1 then
    local k = H.vars.kit
    return k[2] ~= nil and k[2].refusedSeen
  elseif stage == 2 then
    return lastExec(relm * 2, MASTER) ~= nil and #endsOf(relm * 2, lastExec(relm * 2, MASTER).f) > 0
  elseif stage == 3 then
    if rec.turned == nil and rec.varnishedAt ~= nil and H.frame > rec.varnishedAt + 6000 then
      H.log("[relmwor] no enemy hit came at the varnished ally in 6000 frames: not counted")
      rec.giveUp = true
      return true
    end
    return rec.turned ~= nil and #endsOf(rec.turned.att, rec.turned.f) > 0
  elseif stage == 4 then
    local ex = lastExec(relm * 2, GESTURE)
    if rec.gestured == nil and ex ~= nil and #endsOf(relm * 2, ex.f) > 0 then
      -- the Gesture marked her (it took the row) yet wrote no gauge: the
      -- judge says so; with no mark it found her turn full or queued
      if (endsOf(relm * 2, ex.f)[1].gest >> terra) & 1 == 1 then return true end
      H.log("[relmwor] the Gesture found TERRA's turn already full or queued: not counted")
      rec.giveUp = true
      return true
    end
    return rec.gestured ~= nil and #endsOf(terra * 2, rec.gestured.f) > 0
  elseif stage == 5 then
    local ex = lastExec(gogo * 2, GESTURE)
    local ge = ex and endsOf(gogo * 2, ex.f)[1]
    local k = H.vars.kit
    return rec.giveUp or k[3] ~= nil
  elseif stage == 6 then
    return rec.fight ~= nil and #endsOf(terra * 2, rec.fight.f) > 0
  elseif stage == 8 then
    local ex = lastExec(relm * 2, nil)
    local e = ex and endsOf(relm * 2, ex.f)[1]
    return e ~= nil and H.frame >= e.f + 60
  elseif stage == 9 then
    return rec.starved ~= nil and #endsOf(relm * 2, rec.starved.f) > 0
  elseif stage == 10 then
    return rec.leak ~= nil
  end
  return rec.recovered ~= nil
end

local function judge()
  local k = H.vars.kit
  if rec.giveUp then return false end
  if stage == 1 then
    H.assertEq(seen ~= nil and seen.mode == 5, true, "Sketch opened the painter's list")
    for i, id in ipairs(ORDER) do
      local cell = ((i - 1) % 4) * 2 + (i - 1) // 4
      local c = seen.cells[cell]
      H.log(string.format("[relmwor] cell %d: $%02X at %d MP", cell, c.id, c.qty))
      H.assertEq(c.id, id, string.format("cell %d holds row $%02X", cell, id))
      H.assertEq(c.qty, PRICE[id], string.format("row $%02X is priced %d", id, PRICE[id]))
    end
    H.assertEq(k[2].refusedSeen, true, "Masterpiece at two points was refused at the list")
    return true
  elseif stage == 2 then
    local ex = lastExec(relm * 2, MASTER)
    local mp1, bank1 = H.readWord(0x3C08 + relm * 2), H.readByte(0x3E9C + relm * 2)
    local want = 0
    for s = 0, 3 do if s ~= relm and up(s) and H.readByte(0x3ED8 + s * 2) ~= 0x0D then want = want | (1 << s) end end
    H.log(string.format("[relmwor] Masterpiece at %d pending: MP %d -> %d, bank %d -> %d, gifts $%02X (want $%02X), "
      .. "targets $%02X", ex.pend0, ex.mp0, mp1, ex.bank0, bank1, H.readByte(GIFT), want, H.readByte(0xB8)))
    H.assertEq(ex.pend0, 3, "Masterpiece ran at three points")
    H.assertEq(ex.mp0 - mp1, 99, "Masterpiece cost 99 MP")
    H.assertEq(ex.bank0 - bank1, 3, "the bank paid three points")
    H.assertEq(H.readByte(GIFT) & want, want, "every other ally standing holds the gift")
    H.assertEq(H.readByte(GIFT) & (1 << relm), 0, "RELM holds none")
    return true
  elseif stage == 3 then
    local t = rec.turned
    local hp1 = H.readWord(0x3BF4 + ally * 2)
    H.log(string.format("[relmwor] Varnish on seat %d (f%d); the first enemy hit to land on her: f%d, attacker $%02X, "
      .. "coat $%02X at the gate; coat now $%02X; HP %d -> %d", ally, rec.varnishedAt, t.f, t.att, t.coat,
      H.readByte(VARN), t.hp0, hp1))
    H.assertEq(t.coat ~= 0, true, "she held the coat when the hit came")
    H.assertEq(H.readByte(VARN) & (1 << ally), 0, "the coat is spent")
    H.assertEq(hp1 >= t.hp0, true, "the turned action did not hurt her")
    return true
  elseif stage == 4 then
    H.assertEq(rec.gestured ~= nil, true, "RELM's Gesture, which marked TERRA, filled her gauge ($FF before the mark)")
    local g = rec.gestured
    local e = endsOf(terra * 2, g.f)[1]
    H.log(string.format("[relmwor] Gesture on TERRA at f%d: gauge byte $%02X now, mark $%02X then; her next action "
      .. "ended f%d (mark $%02X at its end, $%02X now)", g.f, H.readByte(0x3219 + terra * 2), g.gest, e.f, e.gest,
      H.readByte(GEST)))
    H.assertEq(rec.gaugeAtEnd == 0 or rec.gaugeAtEnd == 0xFF, true, string.format("TERRA's gauge was full as "
      .. "RELM's Gesture ended ($%02X)", rec.gaugeAtEnd or -1))
    H.assertEq(rec.full ~= nil and rec.full - g.f <= 4, true, string.format("her gauge was full within four frames "
      .. "of the Gesture (f%s)", tostring(rec.full)))
    H.assertEq(e.gest & (1 << terra) ~= 0, true, "her granted turn held the Gesture mark")
    H.assertEq(H.readByte(GEST) & (1 << terra), 0, "its end cleared the mark")
    H.assertEq(e.f - g.f < 2400, true, string.format("her turn came within %d frames", e.f - g.f))
    return true
  elseif stage == 5 then
    H.assertEq(seen ~= nil and seen.who == GOGO and seen.mode == 5, true, "GOGO's Sketch opened RELM's list")
    local same = true
    for i, id in ipairs(ORDER) do
      if seen.cells[((i - 1) % 4) * 2 + (i - 1) // 4].id ~= id then same = false end
    end
    H.assertEq(same, true, "GOGO's list holds RELM's eight rows")
    local ex = lastExec(relm * 2, GESTURE)
    H.assertEq(ex ~= nil and ex.b8 == (1 << gogo), true, "RELM's Gesture named GOGO")
    H.assertEq(k[3].refusedSeen, true, "the Gesture row was refused on the turn a Gesture gave GOGO")
    return true
  elseif stage == 6 then
    local f = rec.fight
    local first
    for _, s in ipairs(rec.sh or {}) do if s.f >= f.f then first = s; break end end
    H.log(string.format("[relmwor] Underpainting on slot %d, Tint bit $%02X on TERRA: %d shields at her Fight, the "
      .. "first take left %s; mark $%02X -> $%02X", target, 1 << colour, f.sh, first and tostring(first.v) or "-",
      f.under, H.readByte(UPAINT)))
    if first == nil then H.log("[relmwor] no chip landed: not counted"); return false end
    H.assertEq(f.under & (1 << target) ~= 0, true, "the body was painted when TERRA swung")
    H.assertEq(first.v, f.sh - 2, "the first weakness chip took two shields")
    H.assertEq(H.readByte(UPAINT) & (1 << target), 0, "the mark is spent")
    return true
  end
  if stage == 8 then
    local ex = lastExec(relm * 2, nil)
    local t = H.readByte(TINTN + relm * 2)
    H.log(string.format("[relmwor] Tint on RELM herself ($%02X, f%d): %d turn(s) held once her action ended",
      ex.id, ex.f, t))
    H.assertEq(t, TINT_TURNS, "RELM's own Tint holds all its turns once her casting action has ended")
    return true
  elseif stage == 9 then
    local r = rec.starved
    local mp1 = H.readWord(0x3C08 + relm * 2)
    H.log(string.format("[relmwor] Varnish by a RELM at %d MP for a %d-MP row (staged $3A4C %d): coat $%02X -> $%02X, "
      .. "MP now %d", r.mp, PRICE[VARNISH], r.cost, r.coat0, H.readByte(VARN), mp1))
    H.assertEq(r.cost, PRICE[VARNISH], "the row's price was staged before her turn")
    H.assertEq(H.readByte(VARN) & (1 << terra), 0, "a row she cannot pay lands nothing: no coat")
    H.assertEq(mp1, r.mp, "and charges nothing (the MP check refused it)")
    return true
  elseif stage == 10 then
    H.log(string.format("[relmwor] a monster's action (x=$%02X, f%d) began with the leaked mask $0F: $%02X after "
      .. "Ot6BpBegin", rec.leakArmed.x, rec.leakArmed.f, rec.leak.v))
    H.assertEq(rec.leak.v, 0, "each action that begins clears the coat-spent mask")
    return true
  end
  -- stage 7: the body's break count, every write from the break on: 16 down
  -- to 0, Still Life's reload to 16, down to 0 again, and the recovery
  local seq, dec, reload = {}, 0, false
  for _, t in ipairs(rec.tk or {}) do seq[#seq + 1] = t.v end
  for i = 2, #seq do
    if seq[i] == seq[i - 1] - 1 then dec = dec + 1 end
    if seq[i] == 0x10 and seq[i - 1] == 0 then reload = true end
  end
  local s = {}
  for _, v in ipairs(seq) do s[#s + 1] = tostring(v) end
  H.log(string.format("[relmwor] Still Life on slot %d: the break's count %s; held $%02X, mark $%02X now",
    target, table.concat(s, ","), H.readByte(SHELD), H.readByte(SMARK)))
  H.assertEq(reload, true, "Still Life reloaded the break at its end")
  H.assertEq(dec, 32, "the break lasted 32 ticks: its 16 and Still Life's 16")
  H.assertEq(H.readByte(SHELD) & (1 << target), 0, "the hold ended with the break")
  -- the second Still Life is RELM's queued action, and a draw can hold it in the queue past the hold's end (the
  -- v0.48 line at shift 13: confirmed at f56399, the hold f55825-f58031, still queued at the judge,
  -- build/attempts/wt/v048-shadow-fu/relmwor/): then no mark was laid during the hold and the property is not
  -- staged, so the battle is not counted and the next one is taken
  local second
  for _, m in ipairs(rec.marks or {}) do
    if rec.heldAt ~= nil and m.f >= rec.heldAt then second = m; break end
  end
  if second == nil or not second.held then
    H.log(string.format("[relmwor] the hold ran f%s-f%s and RELM's second Still Life %s: no mark laid during the "
      .. "hold, not counted", tostring(rec.heldAt), tostring(rec.recovered),
      second and string.format("landed at f%d, after it", second.f) or "had not landed"))
    return false
  end
  H.log(string.format("[relmwor] the second mark landed at f%d, during the hold (f%d-f%d)", second.f, rec.heldAt,
    rec.recovered))
  H.assertEq(H.readByte(SMARK) & (1 << target) ~= 0, true, "the mark laid during the hold waits for the next break")
  return true
end

-- stage 7's own steps: break it (the plan), then wait for the hold, mark it
-- again, and wait out the break
local function stillTail()
  return H.cond(function() return stage == 7 and mode == "play" end, {
    -- the hold, or the break's end without one (a ROM that holds nothing:
    -- the judge's own asserts then say so, rather than a timeout here)
    H.kitBattle({}, { untilPlanDone = true, idle = "defend", maxFrames = 12000,
      planDone = function()
        if target == nil then return false end
        if (H.readByte(SHELD) >> target) & 1 == 1 then return true end
        if ticks(target) == 0 then rec.recovered = rec.recovered or H.frame; return true end
        return false
      end }),
    H.call(function()
      plan = { { who = RELM, cmd = CMD, row = STILL, slot = target } }
    end),
    H.cond(function() return rec.recovered == nil end, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 8000,
        planDone = function()
          if target ~= nil and ticks(target) == 0 then rec.recovered = rec.recovered or H.frame; return true end
          return target ~= nil and (H.readByte(SMARK) >> target) & 1 == 1
        end }),
    }, {}),
    H.kitBattle({}, { untilPlanDone = true, idle = "defend", maxFrames = 12000,
      planDone = function()
        if target ~= nil and ticks(target) == 0 and (H.readByte(SHELD) >> target) & 1 == 0 then
          rec.recovered = rec.recovered or H.frame
        end
        return rec.recovered ~= nil
      end }),
  }, {})
end

local home, away = nil, nil
local function lap()
  local goal, wplan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then wplan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if wplan == nil or idx > #wplan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        wplan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not wplan or #wplan == 0 then wplan = nil; H.setPad({}) return end
      end
      local dir = wplan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

H.run({ maxFrames = 2500000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    for _, ch in ipairs({ TERRA, RELM, GOGO }) do
      H.assertEq((H.readByte(0x1850 + ch) & 7) ~= 0, true, string.format("char %d is in the party", ch))
    end
    H.assertEq(H.readByte(0x1600 + 37 * RELM + 8) >= 42, true, "RELM is level 42 or more (Gesture)")
    for _, n in ipairs({ 0x02E8, 0x0240, 0x00BA }) do
      H.assertEq((H.readByte(0x1E80 + (n >> 3)) >> (n & 7)) & 1, 1, string.format("switch $%04X is set", n))
    end
    -- the declared write (the header): GOGO's Lore slot becomes Sketch
    local r
    for i = 0, 3 do if H.readByte(recCmd(GOGO, i)) == LORE then r = i end end
    H.assertEq(r ~= nil, true, "GOGO carries Lore (the slot Sketch takes)")
    H.writeByte(recCmd(GOGO, r), CMD)
    local x, y = H.worldX(), H.worldY()
    home = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if away == nil and H.worldBfs(x + d[1], y + d[2]) then away = { x + d[1], y + d[2] } end
    end
    H.assertEq(away ~= nil, true, "a walkable world tile beside the save")
    arm()
  end),
  H.driveUntil(function() return stage > LAST end, 2400000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fieldCare({ tag = "relmwor" }), lap(), H.release() },
      {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "play" end, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
        planDone = function() return stage == 7 and broken() or closed() end,
        -- stage 5's RELM holds her window until GOGO's Defend has ended and
        -- his gauge is filling again.  v0.50's replay on the wor-gogo-v1
        -- capture: his Defend ran and ended ('f34373 ExecCmd x=04 b5=15',
        -- 'f34380 ActionEnd x=04'), her window opened at f34896 with his
        -- gauge nearly full ('f34800 gogo ... gauge3219=EB'), and from
        -- f35100 his turn sat full behind her held window ('gauge3219=00
        -- 3aa0=8F 7bca=01 62ca=01 7bc2=05') until he fell at f48396 and the
        -- kit ran out its 60000 frames (build/attempts/wt/v050-multihit-anim/
        -- qual2_battle_relmwor_red.log, ab/relmwor_dbg.log).  A GOGO who has
        -- fallen gives no turn to Gesture: not counted.  (Giving up on his
        -- full gauge instead fired in every stage-5 battle, 40 of 40:
        -- ab/relmwor_fullarm_v2_red.log.)
        giveUp = function()
          if stage ~= 5 or rec.giveUp or gogo == nil or up(gogo) then return false end
          H.log("[relmwor] GOGO fell while RELM held her window: not counted")
          rec.giveUp = true
          return true
        end }),
      stillTail(),
      H.call(function()
        if not closed() then
          H.log("[relmwor] the battle ended before the stage resolved: not counted")
          return
        end
        if judge() then
          H.log(string.format("[relmwor] PASSED stage %d", stage))
          stage = stage + 1
        end
      end),
    }, {}),
    H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the world map",
      5),
  }, "the ten stages"),
  H.logStep("[relmwor] done: Masterpiece, Varnish, Gesture and its limit, GOGO's list, Underpainting, Still Life, "
    .. "RELM's own Tint, the unpaid row, the leaked coat mask"),
})

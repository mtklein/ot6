-- @suite slow
-- battle_shadowpin_edges.lua -- the arms of Shadow's trap (#546) that play does not reach on its own (#553).
--
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-kt-factory-v1 tools/tests/run.sh tools/tests/battle_shadowpin_edges.lua
--
-- Continues wor-kt-factory-v1 (party 3: CYAN, SHADOW, SABIN, GOGO beside Inferno), as battle_shadowpin does,
-- puts magicite that teaches Slow on SHADOW and Rflect on SABIN through the Skills menu, and walks
-- onto Inferno's trigger (event battle 114: Inferno, Rough, Striker).  In the battle, through the real menu
-- (H.kitBattle; the others Defend, with care), from a snapshot at the battle's open, retried from it a little
-- later each time until it is seen:
--   R. a reflected Slow holds the mark for its script, as a direct one does.  SABIN casts Rflect on himself and
--      SHADOW casts Slow at SABIN: it bounces off him onto a monster.  Ot6Pin runs on the bounce (CalcReflectDmg),
--      so the monster's line is held (OT6_HOLD) when its Slow lands and the dagger shows once the script ends
--      (Ot6ShowFlush), not when the status is computed.  Then a direct Slow at a free monster is judged the same
--      way.  (A throw is never reflected: CalcItemEffect and the item-spell path set $11a3's "ignore reflect",
--      so the bounce's hook carries only the hold, never the throw rule.)
--   E. the mark cell's edge rule.  A line anchored in column 0 or 1 has no mark cell: the cell two before the
--      anchor would be the row above's last columns.  No formation the game deals puts a line there
--      (tools/check_hud_columns.py), so the line is put there: the declared writes move a marked monster's x
--      (w7e80c3, the screen x the HUD anchors to) so its line anchors in column 1 and then column 0, and the
--      row above's last two cells must never show the mark.
-- Mutants (build/attempts/wt/v048-shadow-fu/suites/mut.py): reflect_nopin (the jsl Ot6Pin in CalcReflectDmg
-- gone) is red at R; mark_no_edge (@mark's column test gone) is red at E.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN, GOGO = 2, 3, 5, 12
local INFERNO, ROUGH, STRIKER = 0x10C, 0x141, 0x142
local SLOW, STOP, REFLECT = 0x04, 0x10, 0x80
local SPELL_SLOW, SPELL_RFLECT = 0x19, 0x24
local DAGGER, KNIFE = 0x21D8, 0x2174
local HOLD, SHADOWL = 0x7EEE4D, 0x7EECF1
local PIN, FLUSH, REFLDMG = H.sym("Ot6Pin"), H.sym("Ot6ShowFlush"), H.sym("CalcReflectDmg")
local INFERNO_TILE = { 31, 18 }

local watching = false
local seat, slotOf = {}, {}
local function ent2slot(e) return (e - 8) // 2 end
local function wordMark(w) if w == DAGGER then return 1 elseif w == KNIFE then return 2 end return 0 end
local function vramWord(addr) return emu.readWord(addr * 2, emu.memType.snesVideoRam) end
local function anchorOf(l) return H.readWord(SHADOWL + l * 14) end
local function vramMark(l)
  local cur = anchorOf(l)
  if cur == 0 or (cur & 0x1F) < 2 then return nil end
  return wordMark(vramWord(cur - 2))
end
local function seatOf(ch) for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == ch then return s end end end

-- R: every Slow Ot6Pin sees land on a monster, direct or bounced
local slows = {}           -- { f, y, bounce, pre, landed, held, release, shown }
emu.addMemoryCallback(function()
  if not watching then return end
  local s = emu.getState()
  local x, y = s["cpu.x"] & 0xFF, s["cpu.y"] & 0xFF
  if y < 8 or H.readByte(0xB5) ~= 0x02 or H.readByte(0xB6) ~= SPELL_SLOW then return end
  -- on a bounce x is the body it bounced off (CalcReflectDmg's loop), a Reflected ally
  local bounce = x < 8 and (H.readByte(0x3EF8 + x) & REFLECT) ~= 0 and seat[x] ~= SHADOW
  slows[#slows + 1] = { f = H.frame, y = y, bounce = bounce, pre = H.readByte(0x3EF8 + y) }
  H.log(string.format("[edges] f%d Slow by entity %d at monster %d%s: status3 $%02X", H.frame, x, y,
    bounce and " (bounced)" or "", H.readByte(0x3EF8 + y)))
end, emu.callbackType.exec, PIN, PIN)
-- the moment a monster's Slow lands: is its line held?
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  local y = addr - 0x7E3EF8
  if y < 8 or y > 0x12 or (y & 1) == 1 then return end
  local found = false
  for _, ev in ipairs(slows) do
    if ev.y == y and ev.landed == nil and ev.pre & SLOW == 0 and v & SLOW ~= 0 then
      ev.landed, ev.held = H.frame, (H.readByte(HOLD) >> ent2slot(y)) & 1 == 1
      found = true
      H.log(string.format("[edges] f%d monster %d's Slow lands; its line %s", H.frame, y,
        ev.held and "is held" or "is NOT held"))
    end
  end
  -- a Slow spell's landing Ot6Pin never saw: the direct loop always calls it, so this is a bounce whose hook
  -- did not run (CalcReflectDmg), judged like the rest
  local seen = false
  for _, ev in ipairs(slows) do if ev.y == y and ev.landed ~= nil then seen = true end end
  if not found and not seen and v & SLOW ~= 0 and H.readByte(0xB5) == 0x02 and H.readByte(0xB6) == SPELL_SLOW then
    local ev = { f = H.frame, y = y, bounce = true, pre = 0, landed = H.frame,
      held = (H.readByte(HOLD) >> ent2slot(y)) & 1 == 1 }
    slows[#slows + 1] = ev
    H.log(string.format("[edges] f%d monster %d's Slow lands with no Ot6Pin call for it; its line %s", H.frame, y,
      ev.held and "is held" or "is NOT held"))
  end
end, emu.callbackType.write, 0x7E3F00, 0x7E3F0B)
emu.addMemoryCallback(function()
  if not watching then return end
  local h = H.readByte(HOLD)
  for _, ev in ipairs(slows) do
    if ev.landed ~= nil and ev.release == nil and (h >> ent2slot(ev.y)) & 1 == 1 then ev.release = H.frame end
  end
end, emu.callbackType.exec, FLUSH, FLUSH)

-- the marks in VRAM, per line, every frame
local marks = {}           -- l -> { { f, m } } transitions
emu.addEventCallback(function()
  if not watching then return end
  for l = 0, 5 do
    local m = vramMark(l)
    local t = marks[l] or {}
    marks[l] = t
    if m ~= nil and (#t == 0 or t[#t].m ~= m) then t[#t + 1] = { f = H.frame, m = m } end
  end
end, emu.eventType.endFrame)

local function bounced() for _, ev in ipairs(slows) do if ev.bounce and ev.landed then return ev end end end
local function direct() for _, ev in ipairs(slows) do if not ev.bounce and ev.landed then return ev end end end
local function reflectSeen()
  local b, d = bounced(), direct()
  -- both landed, and a while for their scripts to end (the judge then reads whether their lines were held)
  return b ~= nil and d ~= nil and H.frame > math.max(b.landed, d.landed) + 900
end
local function freeMonster()
  for _, sp in ipairs({ INFERNO, ROUGH, STRIKER }) do
    local s = slotOf[sp]
    if s and (H.readByte(0x3A75) >> s) & 1 == 1 and H.readByte(0x3EF8 + 8 + 2 * s) & (SLOW | STOP) == 0 then return s end
  end
end
local function patient(fn, what, budget)
  local t0, told
  return function()
    if fn() then return true end
    t0 = t0 or H.frame
    if H.frame - t0 > budget then
      if not told then told = true; H.log(string.format("[edges] f%d %s: waited %d frames, played anyway", H.frame,
        what, budget)) end
      return true
    end
    return false
  end
end
local function plan()
  local sab = seatOf(SABIN)
  local p = {
    { who = SABIN, cmd = 0x02, spell = SPELL_RFLECT, boost = 0, allySeat = sab },
    { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, allySeat = sab, hold = true,
      when = patient(function() return H.readByte(0x3EF8 + 2 * sab) & REFLECT ~= 0 end, "SABIN's Reflect", 3000) },
    { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, slotFn = freeMonster, hold = true,
      when = patient(function() return bounced() ~= nil and freeMonster() ~= nil end, "the bounce", 3000) },
  }
  return p
end

local function writeX(l, x)
  -- the declared write (E): the monster's screen x, low byte (the HUD reads it 8-bit)
  H.writeByte(0x80C3 + 2 * l, x & 0xFF)
end
local edge = {}
-- the line's x is held where E puts it, every frame (an animation's position restore would put it back)
emu.addEventCallback(function()
  if edge.x ~= nil then writeX(edge.l, edge.x) end
end, emu.eventType.endFrame)

H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
local shots = {}
local snapBattle, reqBattle
local TRIES = 6
H.run({ maxFrames = 900000, retries = 4 }, {
  H.bootCheckpoint("wor-kt-factory-v1"),
  H.call(function()
    H.assertEq(H.activeParty(), 3, "party 3 walks (gen_wor_kt_factory left it on the factory's save point)")
    for _, c in ipairs({ CYAN, SHADOW, SABIN, GOGO }) do
      H.assertEq(H.readByte(0x1850 + c) & 7, 3, string.format("%s is in party 3", H.SPLIT_NAMES[c]))
    end
    local g = H.sym("GenjuProp") & 0x3FFFFF
    local function teaches(e, sp)
      for _, o in ipairs({ 1, 3, 5, 7, 9 }) do if H.readRomByte(g + 11 * e + o) == sp then return true end end
    end
    local function usable(e)
      if (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 0 then return false end
      for c = 0, 13 do
        if H.readByte(0x1600 + 37 * c + 0x1E) == e and (H.readByte(0x1850 + c) & 7) ~= 3 then return false end
      end
      return true
    end
    for e = 0, 26 do
      if shots.slowEsper == nil and teaches(e, SPELL_SLOW) and usable(e) then shots.slowEsper = e end
      if shots.rflectEsper == nil and teaches(e, SPELL_RFLECT) and usable(e) and e ~= shots.slowEsper then
        shots.rflectEsper = e
      end
    end
    H.log(string.format("[edges] magicite for Slow %s, Rflect %s", tostring(shots.slowEsper),
      tostring(shots.rflectEsper)))
    H.assertEq(shots.slowEsper ~= nil and shots.rflectEsper ~= nil, true,
      "the party owns magicite teaching Slow and Rflect that party 3 may wear")
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + SHADOW) >> 3) & 3 end, shots.slowEsper,
      { tag = "the Slow magicite -> SHADOW" })
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + SABIN) >> 3) & 3 end, shots.rflectEsper,
      { tag = "the Rflect magicite -> SABIN" })
  end),
  H.call(function()
    H.assertEq(H.knowsSpell(SHADOW, SPELL_SLOW), true, "SHADOW can cast Slow")
    H.assertEq(H.knowsSpell(SABIN, SPELL_RFLECT), true, "SABIN can cast Rflect")
  end),
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 2 } }),
  H.absorbSafeArms(nil, { INFERNO, STRIKER, ROUGH }, { tag = "arms for Inferno" }),
  H.fieldCare({ threshold = 1.0, tag = "before Inferno" }),
  H.navTo(INFERNO_TILE[1], INFERNO_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = {},
    spare = { INFERNO },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }))
        or (H.fieldX() == INFERNO_TILE[1] and H.fieldY() == INFERNO_TILE[2])
    end }),
  H.waitUntil(function() return H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }) end, 3000,
    "Inferno's battle"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    local ids = H.monsterIds()
    for s = 1, 6 do if ids[s] ~= 0xFFFF then slotOf[ids[s]] = s - 1 end end
    for s = 0, 3 do seat[2 * s] = H.readByte(0x3ED8 + 2 * s) end
    H.assertEq(slotOf[INFERNO] ~= nil and slotOf[ROUGH] ~= nil and slotOf[STRIKER] ~= nil, true,
      "Inferno and both arms are on the field")
    watching = true
    snapBattle = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snapBattle, "the snapshot at the battle's open") end),
  H.lazy(function()
    local steps = {}
    for i = 1, TRIES do
      steps[#steps + 1] = H.cond(function() return not (reflectSeen()) end, {
        H.call(function()
          if i == 1 then return end
          slows, marks = {}, {}
          H.setPad({})
          reqBattle = H.requestLoadState(snapBattle.blob)
        end),
        H.waitFrames(2),
        H.call(function()
          if i > 1 then H.checkReq(reqBattle, "the battle's open"); H.rearmInputInjection() end
          H.log(string.format("[edges] try %d of %d, from the battle's open", i, TRIES))
        end),
        H.lazy(function() H.setPad({}); return H.waitFrames(1 + (i - 1) * 97) end),
        H.lazy(function()
          local t0 = H.frame
          return H.kitBattle(plan(), { maxFrames = 22000, untilPlanDone = true, idle = "defend", cureAllies = true,
            planDone = function() return reflectSeen() end,
            giveUp = function()
              if H.frame - t0 <= 20000 then return false end
              H.log(string.format("[edges] try %d: 20000 frames without the reflect case; dropped", i))
              return true
            end })
        end),
        H.call(function()
          H.log(string.format("[edges] try %d: reflect %s", i, tostring(reflectSeen())))
        end),
      }, {})
    end
    return H.seqStep(steps)
  end),
  H.call(function()
    -- R: the bounce and the direct Slow, judged alike
    for _, ev in ipairs({ bounced(), direct() }) do
      H.assertEq(ev ~= nil, true, "a Slow landed on a monster, bounced off SABIN's Reflect and direct")
    end
    for _, ev in ipairs({ bounced(), direct() }) do
      local what = ev.bounce and "the bounced Slow" or "the direct Slow"
      local l = ent2slot(ev.y)
      local shown
      for _, t in ipairs(marks[l] or {}) do if t.f >= ev.f and t.m == 1 and shown == nil then shown = t.f end end
      H.log(string.format("[edges] %s on slot %d: computed f%d, landed f%d (held %s), the script's end f%s, the "
        .. "dagger f%s", what, l, ev.f, ev.landed, tostring(ev.held), tostring(ev.release), tostring(shown)))
      H.assertEq(ev.held, true, what .. ": the monster's line is held when its Slow lands (Ot6Pin -> Ot6Hold)")
      H.assertEq(ev.release ~= nil and shown ~= nil, true, what .. ": the hold's release and the dagger are seen")
      H.assertEq(shown >= ev.release and shown <= ev.release + 6, true,
        string.format("%s: the dagger shows at the script's end (f%d, the release f%d), not with the status (f%d)",
          what, shown, ev.release, ev.landed))
      if ev.bounce and not shots.bounce then shots.bounce = true end
    end
  end),
  -- E: a marked line moved to column 1, then column 0
  H.kitBattle({ { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, slotFn = freeMonster } },
    { maxFrames = 8000, untilPlanDone = true, idle = "defend", cureAllies = true,
      planDone = function()
        for l = 0, 5 do if vramMark(l) ~= nil and vramMark(l) ~= 0 then return true end end
        return false
      end }),
  H.call(function()
    for l = 0, 5 do
      if edge.l == nil and (H.readByte(0x3A75) >> l) & 1 == 1 and vramMark(l) ~= nil and vramMark(l) ~= 0 then
        edge.l, edge.m = l, vramMark(l)
      end
    end
    H.assertEq(edge.l ~= nil, true, "a monster's line shows a mark (the control: its cell is two before the anchor)")
    edge.w = H.readByte(0x812F + 2 * edge.l)
    H.log(string.format("[edges] slot %d shows mark %d at column %d; width %d", edge.l, edge.m, anchorOf(edge.l) & 0x1F,
      edge.w))
    H.screenshot("shadowpin_edges_mark")
    edge.x = 20 - edge.w * 4              -- the centre at x 20: the anchor in column 1
  end),
  H.waitUntil(function() return anchorOf(edge.l) & 0x1F == 1 end, 3000, "the line anchored in column 1", 1),
  H.waitFrames(10),
  H.call(function()
    local a = anchorOf(edge.l)
    H.assertEq(a & 0x1F, 1, "the line anchors in column 1")
    H.screenshot("shadowpin_edges_col1")
    edge.a1 = a
  end),
  H.lazy(function()
    -- every frame for a second: the row above's last cell (anchor - 2) never shows a mark, and the lead cell
    -- (column 0) is the line's own
    local n = 0
    return H.driveUntil(function() n = n + 1; return n > 60 end, 120, {
      H.call(function()
        local w = vramWord(edge.a1 - 2)
        if wordMark(w) ~= 0 then
          error(string.format("f%d: the row above's last cell ($%04X) shows the mark ($%04X) of a line anchored in "
            .. "column 1", H.frame, edge.a1 - 2, w))
        end
      end),
    }, "column 1 watched")
  end),
  H.call(function()
    edge.x = 12 - edge.w * 4              -- the centre at x 12: the anchor in column 0
  end),
  H.waitUntil(function() return anchorOf(edge.l) & 0x1F == 0 end, 3000, "the line anchored in column 0", 1),
  H.waitFrames(10),
  H.call(function()
    local a = anchorOf(edge.l)
    H.assertEq(a & 0x1F, 0, "the line anchors in column 0")
    H.screenshot("shadowpin_edges_col0")
    edge.a0 = a
  end),
  H.lazy(function()
    local n = 0
    return H.driveUntil(function() n = n + 1; return n > 60 end, 120, {
      H.call(function()
        for _, c in ipairs({ edge.a0 - 1, edge.a0 - 2 }) do
          local w = vramWord(c)
          if wordMark(w) ~= 0 then
            error(string.format("f%d: the row above's cell $%04X shows the mark ($%04X) of a line anchored in "
              .. "column 0", H.frame, c, w))
          end
        end
      end),
    }, "column 0 watched")
  end),
  H.call(function()
    edge.x = nil
    H.log("[edges] PASS: a reflected Slow holds its mark as a direct one does; a line at column 0 or 1 draws no "
      .. "mark into the row above")
  end),
})

-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_sketchboost.lua -- a Sketch whose attack has no number keeps its boost (#469)
--
-- Boots wor-locke-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-locke-v1 \
--     tools/tests/run.sh tools/tests/battle_sketchboost.lua <log>
--
-- A sketched attack runs under its own command (_c21554: GetCmdForAI), and a
-- boost raised for the Sketch buys Ot6BoostDmg's multiplier on it, or Fight's
-- swings when the brush draws the monster's Battle or Special ($EE, $EF).  An
-- attack with no number (MagicProp power 0, or a fraction of HP/MP) buys
-- nothing, and before #469 the boost was spent on it anyway.  Which of the
-- monster's two sketches the brush draws is a roll (one in four the first), so
-- the menu cannot refuse R; Ot6SketchNoBoost drops the boost once the attack
-- is drawn, before Ot6ActionEnd charges it.  So, for a boosted (1 BP) Sketch:
--   * the drawn attack has no number: the bank ends where an unboosted turn
--     leaves it (the regen pip earned, nothing spent);
--   * it has one (or is Battle/Special), or the brush misses: one pip spent,
--     no regen.
-- The run: Continue wor-locke-v1 (TERRA LOCKE CELES RELM outside Kohlingen),
-- pace to an encounter holding a monster one of whose sketches has no number
-- (MonsterSketch and MagicProp read off the ROM: Muus and Deep Eye here draw
-- one three times in four), Defend until RELM's window opens with a pip
-- banked (snapshot S).  The natural tries are RELM's later windows, each a
-- fresh point in the battle: from each window with a pip banked RELM
-- Sketches a body with a numberless sketch at 1 BP, the others Defending,
-- and the battle goes on to his next such window (a new encounter if the
-- battle ends or no such body stands).  A wait at the target select does not
-- move the brush's roll: eight tries from one snapshot drew $EF eight times
-- on the replay at 35473b32 (#469 landing).  How many windows: the odds of a
-- numberless draw are decoded from the ROM (CheckSketchHit's level ratio
-- against RNGTbl, then the pick, `Rand / cmp #$40`: the first sketch below
-- $40, the second at or above), and the windows are as many as bring the
-- chance that none draws one under 1 in 10,000.  Every try is judged by the
-- attack it drew (read where Cmd_0d hands the attack on, _c21554), and at
-- least one natural try must draw an attack with no number.
--
-- A reach spell drawn by the brush buys nothing either (#469 review): reach
-- serves Magic and X-Magic only (Ot6SpellReach), and a sketch keeps command
-- $0D, so Ot6SketchNoBoost drops the boost for it too.  No monster within
-- reach of a RELM checkpoint sketches one (MonsterSketch read off the ROM:
-- the Lizard's Imp and Remedy, the Drop's Muddle, NeckHunter's Imp, live
-- elsewhere), so two more tries are a DECLARED EXPEDIENT
-- (tools/state_write_waivers.txt): at Cmd_0d's `lda $3400` (Cmd_0d + 39, the
-- brush's drawn attack, byte-identical on the old ROM) the drawn attack is
-- replaced by Imp ($23), Slow ($19), Slow 2 ($28), Break ($0C) or Scan
-- ($18): each payoff of the first four is Magic-gated (reach, the tier
-- fold, OT6's Break chips), so the boost is dropped; Ot6Analyze serves a
-- boosted Scan whatever its command, so Scan's is spent.  Each is tried up to
-- three times (the brush can miss), and one of each must land.  Everything
-- after the write is the engine's own.  A
-- mechanism test of the drop, not a claim about play.  Nothing else is
-- written.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local BANK, PEND = 0x3E9C, 0x3E9D
local CMD_SKETCH = 0x0D
local RELM = 8
local WMAX = 12        -- the most natural windows the odds may ask for
local MISS_ODDS = 1e-4 -- the chance, at most, that no natural window draws a numberless attack
-- the injected draws (see the header): Imp (reach), Slow and Slow 2 (tier
-- folds), Break (OT6's chips) -- every payoff Magic-gated, so none buys -- and
-- Scan, which Ot6Analyze serves for any command, so it spends.  Each up to
-- INJECT_TRIES times, until one lands (a sketch can miss: CheckSketchHit)
local INJECT = { 0x23, 0x19, 0x28, 0x0C, 0x18 }
local INJECT_TRIES = 3
local SCAN = 0x18

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
-- a monster standing: present ($3AA8.0), in the battle's live mask ($3A75: a
-- body the sketches took down leaves it, its HP word need not reach 0) and HP up
local function live(m)
  return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and ((H.readByte(0x3A75) >> m) & 1) == 1
    and H.readWord(0x3BFC + m * 2) > 0
end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local MPB, MSK
local function noNumber(a)
  if a >= 0xEE then return false end           -- Battle, Special: Fight
  if a == SCAN then return false end           -- Scan: Ot6Analyze reads every enemy, whatever the command
  -- a power of 0 or a fraction: reach, folds and OT6's Break chips are
  -- Magic's, and a sketch keeps command $0D (#469 review)
  local r = MPB + a * 14
  return (H.readRomByte(r + 4) & 0x80) ~= 0 or H.readRomByte(r + 6) == 0
end
local function sketches(m)
  local id = H.monsterIds()[m + 1]
  return H.readRomByte(MSK + id * 2), H.readRomByte(MSK + id * 2 + 1), id
end

local relmS, tgtMon
local armed
local Tm = H.targetCursor()
local mf, tapNo, tapAt = 0, -1, 0
local function aim(T, want)
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  if T.mask == nil then return {} end
  local btn = T.steer(want, mf)
  if btn == "a" then
    if not edge then btn = nil end
  else
    if btn ~= nil and T.press ~= tapNo then tapNo, tapAt = T.press, mf end
    btn = (tapNo >= 0 and mf - tapAt < 4) and T.dir or nil
  end
  return btn and { [btn] = true } or {}
end
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT then return "b" end
  return nil
end

local snap
local tries = {}
local function runTry(t)
  local req
  local tick, held, waited = 0, nil, 0
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState((t.snap or snap).blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      mf, tapNo = 0, -1
      t.sent, t.endF, t.drawn, t.after = false, nil, nil, false
      armed = t
    end),
    H.driveUntil(function() return t.endF ~= nil and H.frame >= t.endF + 120 end, 14000, {
      H.call(function()
        Tm.observe()
        if t.endF and not t.after and H.frame >= t.endF + 6 then
          t.after, t.bankEnd = true, bank(relmS)
        end
        if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_TGT and (H.readByte(ACTOR) & 3) == relmS
           and not t.sent then
          if waited < t.delay then waited = waited + 1; H.setPad({}); return end
          local btn = aim(Tm, tgtMon)
          if next(btn) == "a" then t.sent, t.pendAtConfirm = true, pend(relmS) end
          H.setPad(btn)
          return
        end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then
          held = nil
          if H.readByte(MENU) ~= 0 then
            local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
            if a == relmS and not t.sent then
              if st == ST_CMD then
                if pend(relmS) < 1 then held = "r"
                else
                  local want, cur = cmdRow(relmS, CMD_SKETCH), H.readByte(CMDROW + relmS) & 3
                  if cur ~= want then held = cur < want and "down" or "up"
                  else t.bank0 = bank(relmS); held = "a" end
                end
              else held = "b" end
            else held = defendPress(st) end
          end
        end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "try " .. t.n .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      H.log(string.format("[sketch] try %d (%s%s): pending at the confirm %s; drew %s%s; bank %s -> %s", t.n,
        t.window and ("window " .. t.window .. ", m" .. tostring(t.tgt)) or ("delay " .. t.delay), t.inject and string.format(", $%02X injected", t.inject) or "", tostring(t.pendAtConfirm), t.drawn and string.format("$%02X", t.drawn) or "nothing (missed)",
        t.drawn and (noNumber(t.drawn) and " (buys nothing)" or (t.drawn == SCAN and " (Scan: breadth)"
          or " (a number)")) or "", tostring(t.bank0),
        tostring(t.bankEnd)))
    end),
  }
end

local function findEncounter()
    local P = H.newPacer({ tag = "sketchboost pace" })
    local sx, sy
    local steps = {
      H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end,
        1500, "the world map settled", 5),
      H.call(function() sx, sy = P.findStart(8) end),
      H.worldNavTo(function() return sx end, function() return sy end,
        { maxFrames = 4000, playBattles = "mustflee", care = false }),
      H.waitUntil(function() return H.worldSettled() end, 1500, "settled on the stretch", 5),
      H.call(function() P.plan() end),
    }
    local found = false
    for try = 1, 16 do
      steps[#steps + 1] = H.cond(function() return found end, {}, {
        H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
          H.call(function() H.setPad(P.pad()) end),
        }, "a random encounter (draw " .. try .. ")"),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900, "battle up (draw " .. try .. ")", 5),
        H.waitFrames(60),
        H.call(function()
          relmS = nil
          for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == RELM then relmS = s end end
          local t = {}
          tgtMon = nil
          for m = 0, 5 do
            if live(m) then
              local a, b, id = sketches(m)
              t[#t + 1] = string.format("m%d $%03X sketches $%02X%s $%02X%s", m, id, a, noNumber(a) and "-" or "+",
                b, noNumber(b) and "-" or "+")
              if tgtMon == nil and (noNumber(b) or noNumber(a)) then tgtMon = m end
            end
          end
          found = tgtMon ~= nil and relmS ~= nil
          H.log(string.format("[sketch] draw %d: formation $%03X: %s -> %s", try, H.readWord(0x11E0),
            table.concat(t, "; "), found and ("target m" .. tgtMon) or "no body with a numberless sketch (run)"))
        end),
        H.cond(function() return found end, {}, {
          H.fleeBattle(9000, { onCantRun = "fight" }),
          H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 1200,
            "back on the world map after running from draw " .. try, 10),
          H.waitFrames(30),
        }),
      })
    end
    steps[#steps + 1] = H.call(function()
      assert(found, "an encounter holding a body one of whose sketches has no number")
      assert(cmdRow(relmS, CMD_SKETCH), "RELM's list has Sketch")
    end)
    return H.repeatN(1, steps)
end

-- a live body one of whose sketches has no number: the current target while
-- it stands, else the first such body
local function pickTarget()
  local function quiet(m)
    if not live(m) then return false end
    local a, b = sketches(m)
    return noNumber(a) or noNumber(b)
  end
  if tgtMon and quiet(tgtMon) then return true end
  tgtMon = nil
  for m = 0, 5 do if quiet(m) then tgtMon = m; return true end end
  return false
end
-- the chance that one of RELM's windows draws a numberless attack from
-- tgtMon, decoded from the ROM (see the header), and the windows it asks for
local nWin
local function windowsNeeded()
  local rng = H.sym("RNGTbl") & 0x3FFFFF
  local function below(q)
    local n = 0
    for i = 0, 255 do if H.readRomByte(rng + i) < q then n = n + 1 end end
    return n / 256
  end
  local att, tgt = H.readByte(0x3B18 + relmS * 2), H.readByte(0x3B18 + 8 + tgtMon * 2)
  if (H.readByte(0x3C45 + relmS * 2) & 0x04) ~= 0 then tgt = (tgt * 0xAA) >> 8 end   -- the Beret
  local q = tgt > 0 and (att * 256) // tgt or 256
  local pHit = q >= 256 and 1 or below(q)
  local pFirst = below(0x40)
  local a, b = sketches(tgtMon)
  local pNum = pHit * ((noNumber(a) and pFirst or 0) + (noNumber(b) and (1 - pFirst) or 0))
  assert(pNum > 0, "the target has a numberless sketch RELM can land")
  nWin = pNum >= 1 and 1 or math.ceil(math.log(MISS_ODDS) / math.log(1 - pNum))
  H.log(string.format("[sketch] odds: RELM L%d vs m%d L%d -> hit %.3f; first sketch $%02X %.3f, second $%02X %.3f; "
    .. "a numberless draw %.3f a window -> %d window(s) for under %g that none draws one", att, tgtMon, tgt, pHit,
    a, pFirst, b, 1 - pFirst, pNum, nWin, MISS_ODDS))
  assert(nWin <= WMAX, string.format("the odds ask for %d windows, more than WMAX (%d)", nWin, WMAX))
end
local function anyLive()
  for m = 0, 5 do if live(m) then return true end end
  return false
end
-- a battle RELM can take a natural try in: up, a monster standing, one with a numberless sketch,
-- and RELM standing (HP $3BF4: a Defending party can lose him)
local function usable()
  return H.battleLoadStarted() and anyLive() and pickTarget() and H.readWord(0x3BF4 + relmS * 2) > 0
end
-- leave a battle that has no body left to sketch (or has ended) for the world map
local function leaveBattle()
  local ph = 0
  return H.repeatN(1, {
    H.cond(function() return H.battleLoadStarted() and anyLive() end,
      { H.fleeBattle(9000, { onCantRun = "fight" }) }, {}),
    H.driveUntil(function() return H.worldMode() and H.worldHasControl() end, 6000, {
      H.call(function() ph = (ph + 1) % 24; H.setPad(ph < 4 and { "a" } or {}) end),
    }, "back on the world map for another encounter"),
    H.release(),
    H.waitFrames(30),
  })
end
-- drive to RELM's next window with a pip banked and nothing pending, and
-- snapshot it into t.snap; a battle that ends (or keeps no body to sketch)
-- before the window opens gives way to the next encounter, up to three
local function windowSnap(t)
  local out = { H.call(function() t.snap = nil end) }
  for round = 1, 3 do
    local tick = 0
    out[#out + 1] = H.cond(function() return t.snap == nil end, {
      H.cond(function() return not usable() end, {
        H.call(function()
          H.log(string.format("[sketch] window %d: no body to sketch in this battle; another encounter (%d of 3)",
            t.window, round))
        end),
        leaveBattle(), H.fieldCare({ tag = "care before window " .. t.window, threshold = 0.9 }), findEncounter() }, {}),
      H.driveUntil(function() return t.snap ~= nil or not usable() end, 30000, {
        H.call(function()
          tick = tick + 1
          if tick % 12 == 6 then H.setPad({}) return end
          if tick % 12 ~= 0 or H.readByte(MENU) == 0 then return end
          local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
          if a == relmS and st == ST_CMD and pend(relmS) == 0 and bank(relmS) >= 1 then
            H.setPad({}); t.snap = H.requestSaveState(); t.tgt = tgtMon
            H.log(string.format("[sketch] window %d f%d: RELM bank %d, target m%d", t.window, H.frame, bank(relmS),
              tgtMon))
            return
          end
          if a == relmS and st == ST_CMD then
            H.log(string.format("[sketch] window %d f%d: RELM's window passed (bank %d, pending %d): Defend",
              t.window, H.frame, bank(relmS), pend(relmS)))
          end
          local b = defendPress(st)
          H.setPad(b and { [b] = true } or {})
        end),
      }, "RELM's window " .. t.window),
      H.call(function()
        if t.snap == nil then
          local hp = {}
          for s2 = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + s2 * 2)) end
          H.log(string.format("[sketch] window %d f%d: the battle gave no window (up %s, live mask $%02X, "
            .. "target %s; party HP %s)", t.window, H.frame, tostring(H.battleLoadStarted()), H.readByte(0x3A75),
            tostring(pickTarget() and tgtMon), table.concat(hp, "/")))
        end
      end),
      H.waitFrames(2),
    }, {})
  end
  out[#out + 1] = H.call(function()
    assert(t.snap, "RELM's window " .. t.window .. " opened within three encounters")
    H.checkReq(t.snap, "window " .. t.window)
  end)
  return out
end

local steps = {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and bright() >= 15 and H.worldHasControl() end,
      6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("wor-locke-v1")
    MPB = H.sym("MagicProp") & 0x3FFFFF
    MSK = H.sym("MonsterSketch") & 0x3FFFFF
    -- the declared injection (see the header): Cmd_0d + 39 is `lda $3400`
    local ld = H.sym("Cmd_0d") + 39
    H.assertEq(H.readRomByte(ld & 0x3FFFFF), 0xAD, "Cmd_0d + 39 is an lda abs")
    H.assertEq(H.readRomWord((ld & 0x3FFFFF) + 1), 0x3400, "...of $3400, the brush's drawn attack")
    emu.addMemoryCallback(function()
      local t = armed
      if t == nil or t.inject == nil or not t.sent or t.endF then return end
      H.writeByte(0x3400, t.inject)
    end, emu.callbackType.exec, ld, ld)
    local sk = H.sym("_c21554")
    emu.addMemoryCallback(function()
      local t = armed
      if t == nil or not t.sent or t.endF then return end
      if (emu.getState()["cpu.x"] & 0xFF) ~= relmS * 2 or H.readByte(0x3A7C) ~= CMD_SKETCH then return end
      t.drawn = H.readByte(0xB6)
    end, emu.callbackType.exec, sk, sk)
    local ae = H.sym("Ot6ActionEnd")
    emu.addMemoryCallback(function()
      local t = armed
      if t and t.sent and t.endF == nil and (emu.getState()["cpu.x"] & 0xFF) == relmS * 2 then t.endF = H.frame end
    end, emu.callbackType.exec, ae, ae)
  end),
  findEncounter(),
  -- snapshot S: RELM's window with a pip banked and nothing pending
  (function()
    local tick = 0
    return H.driveUntil(function() return snap ~= nil end, 30000, {
      H.call(function()
        tick = tick + 1
        if tick % 12 == 6 then H.setPad({}) return end
        if tick % 12 ~= 0 or H.readByte(MENU) == 0 then return end
        local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
        if a == relmS and st == ST_CMD and pend(relmS) == 0 and bank(relmS) >= 1 then
          H.setPad({}); snap = H.requestSaveState()
          H.log(string.format("[sketch] snapshot S f%d: RELM bank %d", H.frame, bank(relmS)))
          return
        end
        local b = defendPress(st)
        H.setPad(b and { [b] = true } or {})
      end),
    }, "snapshot S")
  end)(),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot S"); windowsNeeded() end),
}
-- the natural tries: window 1 is S itself, each later one RELM's next window
-- after the try before it, in this battle or the next encounter's
for k = 1, WMAX do
  local t = { n = k, delay = 0, window = k }
  tries[#tries + 1] = t
  local body = {}
  if k == 1 then
    body[#body + 1] = H.call(function() t.snap = snap; t.tgt = tgtMon end)
  else
    for _, st in ipairs(windowSnap(t)) do body[#body + 1] = st end
  end
  for _, st in ipairs(runTry(t)) do body[#body + 1] = st end
  steps[#steps + 1] = H.cond(function() return k <= nWin end, body, { H.call(function() t.skipped = true end) })
end
-- the injected tries reload S: its target again
steps[#steps + 1] = H.call(function() tgtMon = tries[1].tgt end)
local landed = {}
for j, id in ipairs(INJECT) do
  for r = 1, INJECT_TRIES do
    local t = { n = WMAX + (j - 1) * INJECT_TRIES + r, delay = (j * 3 + r) * 5, inject = id }
    tries[#tries + 1] = t
    steps[#steps + 1] = H.cond(function() return not landed[id] end, {
      table.unpack(runTry(t)),
    }, { H.call(function() t.skipped = true end) })
    steps[#steps + 1] = H.call(function() if t.drawn == id then landed[id] = true end end)
  end
end
steps[#steps + 1] = H.call(function()
  local bad, quiet = {}, 0
  local function check(ok, msg)
    H.log(string.format("[sketch] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  local injected = 0
  for _, t in ipairs(tries) do
    if t.skipped then goto continue end
    H.assertEq(t.pendAtConfirm, 1, "try " .. t.n .. ": the Sketch was confirmed at 1 BP")
    if t.inject then
      injected = injected + 1
      if t.drawn == nil then
        H.log(string.format("[sketch] try %d: the sketch missed ($%02X injected): spent, as any miss", t.n, t.inject))
      else
        H.assertEq(t.drawn, t.inject, "try " .. t.n .. ": the injected attack is the one the sketch runs")
      end
    end
    if t.drawn and noNumber(t.drawn) then
      quiet = quiet + 1
      check(t.bankEnd == math.min(5, t.bank0 + 1), string.format("try %d: drew $%02X (no number): the bank went "
        .. "%d -> %d (want %d: the boost dropped, the regen pip earned)", t.n, t.drawn, t.bank0, t.bankEnd,
        math.min(5, t.bank0 + 1)))
    else
      check(t.bankEnd == t.bank0 - 1, string.format("try %d: drew %s: the bank went %d -> %d (want %d: spent)", t.n,
        t.drawn and string.format("$%02X", t.drawn) or "nothing", t.bank0, t.bankEnd, t.bank0 - 1))
    end
    ::continue::
  end
  local nat = 0
  for i = 1, nWin do if tries[i].drawn and noNumber(tries[i].drawn) then nat = nat + 1 end end
  check(nat >= 1, string.format("%d of %d natural tries drew an attack with no number", nat, nWin))
  for _, id in ipairs(INJECT) do
    check(landed[id] == true, string.format("an injected $%02X landed within %d tries", id, INJECT_TRIES))
  end
  assert(#bad == 0, #bad .. " sketch-boost assertion(s) failed: " .. table.concat(bad, "; "))
  H.log("[sketch] VERDICT: a boosted Sketch that draws an attack with no number keeps its boost; one that draws a "
    .. "number spends it")
end)

H.run({ maxFrames = 400000 }, steps)

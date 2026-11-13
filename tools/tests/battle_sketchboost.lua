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
-- banked (snapshot S), then from S RELM Sketches that body at 1 BP, the
-- others Defending, waiting a different number of frames at the target
-- select each try so the roll varies.  Every try is judged by the attack it
-- drew (read where Cmd_0d hands the attack on, _c21554), and at least one
-- try must draw an attack with no number.  Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local BANK, PEND = 0x3E9C, 0x3E9D
local CMD_SKETCH = 0x0D
local RELM = 8
local TRIES = 8

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function live(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local MPB, MSK
local function noNumber(a)
  if a >= 0xEE then return false end           -- Battle, Special: Fight
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
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
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
      H.log(string.format("[sketch] try %d (delay %d): pending at the confirm %s; drew %s%s; bank %s -> %s", t.n,
        t.delay, tostring(t.pendAtConfirm), t.drawn and string.format("$%02X", t.drawn) or "nothing (missed)",
        t.drawn and (noNumber(t.drawn) and " (no number)" or " (a number)") or "", tostring(t.bank0),
        tostring(t.bankEnd)))
    end),
  }
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
  (function()
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
  end)(),
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
  H.call(function() H.checkReq(snap, "snapshot S") end),
}
for i = 1, TRIES do
  local t = { n = i, delay = (i - 1) * 7 }
  tries[i] = t
  for _, s in ipairs(runTry(t)) do steps[#steps + 1] = s end
end
steps[#steps + 1] = H.call(function()
  local bad, quiet = {}, 0
  local function check(ok, msg)
    H.log(string.format("[sketch] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  for _, t in ipairs(tries) do
    H.assertEq(t.pendAtConfirm, 1, "try " .. t.n .. ": the Sketch was confirmed at 1 BP")
    if t.drawn and noNumber(t.drawn) then
      quiet = quiet + 1
      check(t.bankEnd == math.min(5, t.bank0 + 1), string.format("try %d: drew $%02X (no number): the bank went "
        .. "%d -> %d (want %d: the boost dropped, the regen pip earned)", t.n, t.drawn, t.bank0, t.bankEnd,
        math.min(5, t.bank0 + 1)))
    else
      check(t.bankEnd == t.bank0 - 1, string.format("try %d: drew %s: the bank went %d -> %d (want %d: spent)", t.n,
        t.drawn and string.format("$%02X", t.drawn) or "nothing", t.bank0, t.bankEnd, t.bank0 - 1))
    end
  end
  check(quiet >= 1, string.format("%d of %d tries drew an attack with no number", quiet, TRIES))
  assert(#bad == 0, #bad .. " sketch-boost assertion(s) failed: " .. table.concat(bad, "; "))
  H.log("[sketch] VERDICT: a boosted Sketch that draws an attack with no number keeps its boost; one that draws a "
    .. "number spends it")
end)

H.run({ maxFrames = 400000 }, steps)

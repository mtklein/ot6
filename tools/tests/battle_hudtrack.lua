-- @suite savestate=rapids_start
-- battle_hudtrack: the under-monster HUD anchor must track the battlefield.
--
-- The debt this covers: Ot6BgHudLine's anchor word (OT6_SHADOW+0 per line)
-- was a one-shot latch, computed once per battle and never again, because
-- recomputing every frame made the line jitter on attack-animation coord
-- transients ($8057 priority shifts, $80/$82 x shoves, $e2/$e3 y bounces;
-- see the block comment at Ot6BgHudLine's @done for citations).  The latch
-- traded that jitter for permanent staleness: any real battlefield
-- change after arm time was kept for the rest of the battle.  The
-- recompute-and-compare design recomputes every frame, holds while a battle
-- animation script is executing (OT6_SCRIPTBUSY brackets BtlGfx_04), and
-- writes only on a real change.
--
-- Issue #75 conversion: the move now comes from the game itself.  The old
-- file showed adoption by writing a monster's position word ($80c3+slot*2)
-- and kept its setup in place with guard-HP pins and berserk bits.  All of
-- that is gone: this test now boots rapids_start and rides into the Lete
-- River's forced fight, whose entrance slides the shown monsters across the
-- field.  That is the class of change the latch left stale, delivered by the
-- engine itself (battle_hudtrail covers the abandoned-cell blanking of this
-- same slide; this file covers the anchors).  Measured on this fixture
-- (2026-08-10): battle load zero-inits all six lines' anchors once (2 byte
-- writes each), then the slide walks the live lines' anchors in 17 word-
-- store adoptions each across ~30 frames, then every line is silent.
--
-- Three phases, asserted as write-count deltas against a watch over all six
-- lines' anchor words:
--   1. entrance as the real move: the slide's adoptions happen (>= 8 word
--      stores per live line, half the measured 17, which is safe against
--      formation variance between the fight's two die rolls), the anchors
--      moved (the first adopted value need not differ from the settled
--      value, since the slide may return; what is required is that adoption
--      tracked change, which >= 8 distinct stores shows), and the writes
--      then stop (a settle point of 90 consecutive quiet frames is found).
--   2. static: 600 more idle frames with no anchor writes on any line, which
--      is the jitter non-regression on the live lines and the
--      compare-before-store discipline on the empty ones (an empty line must
--      not rewrite $0000 every frame; its whole-run budget is the one init
--      pair).
--   3. animation: a no-damage action, Banon's own Health command,
--      picked through the live $7BC2 menu (hud_stability's conversion
--      shape; no damage, so no monster dies and disables a line mid-watch),
--      resolves while the enemy side acts freely.  Positive controls:
--      Banon's bp regens +1 (Ot6ActionEnd, so the action resolved)
--      and OT6_SCRIPTBUSY was observed up, so animation scripts ran.
--      Still no anchor writes: transients are held rather than chased.
--
-- Whole-run accounting closes it: every byte-write the run saw belongs
-- to the init (12) or to the entrance adoptions counted at settle.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/rapids_start.mss.lua"
local CH_MAX = 0x056F

local SHADOW = 0xecf1           -- OT6_SHADOW, 6 lines x 14 bytes
local STRIDE = 14

local counts = { [0] = 0, 0, 0, 0, 0, 0 }
local armed = false
emu.addMemoryCallback(function(addr)
  if not armed then return end
  local off = addr - (0x7E0000 + SHADOW)
  local line = math.floor(off / STRIDE)
  if off % STRIDE < 2 then
    counts[line] = counts[line] + 1
  end
end, emu.callbackType.write, 0x7E0000 + SHADOW, 0x7E0000 + SHADOW + 0x53)

local function snap()
  local s = {}
  for i = 0, 5 do s[i] = counts[i] end
  return s
end
local function delta(s, lines)
  local n = 0
  for _, i in ipairs(lines) do n = n + (counts[i] - s[i]) end
  return n
end
local ALL = { 0, 1, 2, 3, 4, 5 }
local function liveLines()
  local t = {}
  for i = 0, 5 do
    if H.readWord(SHADOW + i * STRIDE) ~= 0 then t[#t + 1] = i end
  end
  return t
end

local live, settleSnap, liveMark
local busyFrames = 0

-- the ride into the forced fight: battle_hudtrail's dialog-paced drive
local function rideStep()
  local phase, dlgN = 0, 0
  return H.driveUntil(function()
    return H.battleLoadStarted()
  end, 25000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        error("unexpected multiple choice on the river", 0)
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}) return end
      H.setPad({})
    end),
  }, "the forced river fight loads")
end

-- phase 3's action driver: Banon (char $0e) picks Health (his own row-1
-- command $1a) through the live menu; everyone else defers with X.
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT = 0x05, 0x38
local banonSlot = nil
local mf = 0
local function healthPulse()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  if (mf - 1) % 8 >= 4 then H.setPad({}); return end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  local btn
  if act ~= banonSlot then
    btn = (st == ST_CMD) and "x" or "b"
  elseif st == ST_CMD then
    local want = nil
    for r = 0, 3 do
      if H.readByte(0x202E + banonSlot * 12 + r * 3) == 0x1A then want = r end
    end
    if want == nil then error("banon's menu lost Health", 0) end
    local cur = H.readByte(0x890F + banonSlot) & 3
    if cur == want then btn = "a"
    else btn = (cur < want) and "down" or "up" end
  elseif st == ST_TGT then
    btn = "a"
  else
    btn = "b"
  end
  H.setPad(btn and { [btn] = true } or {})
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 113, "rapids_start boots on the Lete River")
    armed = true                -- armed before battle load: the init pairs
  end),                         -- and every adoption are on the books
  rideStep(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),

  -- ---- phase 1: the entrance slide is the move under test ----
  -- wait for the writes to stop: 90 consecutive quiet frames means settled.
  H.waitUntil(function()
    local sig = delta({ [0] = 0, 0, 0, 0, 0, 0 }, ALL)
    local s = H.vars.settle
    if not s or s.sig ~= sig then
      H.vars.settle = { sig = sig, n = 1 }
      return false
    end
    s.n = s.n + 1
    return s.n >= 90
  end, 3000, "anchor writes settle after the entrance", 1),
  H.call(function()
    live = liveLines()
    settleSnap = snap()
    local parts = {}
    for i = 0, 5 do
      parts[#parts + 1] = string.format("L%d w=%d a=%04x", i, counts[i],
        H.readWord(SHADOW + i * STRIDE))
    end
    H.log("settled: " .. table.concat(parts, " "))
    H.assertEq(#live >= 2, true, "at least two live hud lines (both river "
      .. "formations seed >= 2 monsters)")
    for i = 0, 5 do
      local isLive = false
      for _, l in ipairs(live) do if l == i then isLive = true end end
      if isLive then
        H.assertEq(counts[i] >= 2 + 16, true, string.format(
          "line %d ADOPTED the entrance slide: %d byte writes >= init pair "
          .. "+ 8 word stores -- the genuine-move direction, on the game's "
          .. "own move (the latch design froze after the init and fails "
          .. "here)", i, counts[i]))
      else
        H.assertEq(counts[i], 2, string.format(
          "empty line %d wrote its $0000 init exactly once (2 byte writes) "
          .. "-- the disable path compares before storing", i))
      end
    end
    liveMark = snap()
  end),

  -- ---- phase 2: static, 600 idle frames with no writes anywhere ----
  H.waitFrames(600),
  H.call(function()
    local d = delta(liveMark, ALL)
    H.log(string.format("static: %d anchor writes in 600 frames", d))
    H.assertEq(d, 0, "static stretch writes no anchors -- no jitter on the "
      .. "live lines, no $0000 rewrite on the empty ones")
    H.screenshot("hudtrack_static")
  end),

  -- ---- phase 3: animation, a real action with transients held ----
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == 0x0E then banonSlot = s end
    end
    H.assertEq(banonSlot ~= nil, true, "BANON rides this raft (char $0e)")
    H.vars.bpBefore = H.readByte(0x3E9C + banonSlot * 2)
    liveMark = snap()
    busyFrames = 0
    mf = 0
  end),
  H.driveUntil(function()
    if H.readByte(0x57BF) ~= 0 then busyFrames = busyFrames + 1 end
    return H.readByte(0x3E9C + banonSlot * 2) ~= H.vars.bpBefore
  end, 12000, {
    H.call(healthPulse),
    H.waitFrames(1),
  }, "Banon's Health resolves (bp regen moved -- the action really landed)"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(300),
  H.call(function()
    local d = delta(liveMark, ALL)
    H.log(string.format("animation: %d anchor writes; busy frames observed "
      .. "%d; banon bp %d -> %d", d, busyFrames, H.vars.bpBefore,
      H.readByte(0x3E9C + banonSlot * 2)))
    H.assertEq(busyFrames >= 10, true,
      "positive control: animation scripts really ran while the watch was "
      .. "armed (OT6_SCRIPTBUSY up >= 10 observed frames)")
    H.assertEq(d, 0, "animation transients are held, never adopted -- and "
      .. "the enemy side acted freely through the whole window")
    -- whole-run accounting: nothing ever wrote outside init + entrance
    local total = delta(settleSnap, ALL)
    H.log(string.format("whole run since settle: %d writes", total))
    H.assertEq(total, 0,
      "every write the run saw belongs to the battle-load init or the "
      .. "entrance adoptions counted at settle")
    H.screenshot("hudtrack_postaction")
    H.log("ok: anchors adopted the game's own entrance slide, then stayed "
      .. "quiet through idle and a real action's animations")
  end),
}, "hud anchor tracking")

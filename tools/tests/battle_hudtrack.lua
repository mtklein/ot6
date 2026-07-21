-- @suite
-- battle_hudtrack: the under-monster HUD anchor must TRACK the battlefield.
--
-- THE DEBT THIS GATES.  Ot6BgHudLine's anchor word (OT6_SHADOW+0 per line)
-- was a one-shot latch: computed once per battle, never again, because
-- recomputing every frame made the line jitter on attack-animation coord
-- transients ($8057 priority shifts, $80/$82 x shoves, $e2/$e3 y bounces --
-- see the block comment at Ot6BgHudLine's @done for citations).  The latch
-- traded that jitter for permanent staleness: any genuine battlefield
-- change after arm time (a scripted move, a Cmd_20 reload swapping a
-- slot's monster, corruption of the anchor itself) was kept for the rest
-- of the battle.  The recompute-and-compare design recomputes every
-- frame, holds while a battle animation script is executing
-- (OT6_SCRIPTBUSY brackets BtlGfx_04 -- the container all transient-
-- imposing scripts run under), and writes only on real change.  An
-- earlier cut gated on tick provenance (BtlGfx_01 vs WaitFrame) and
-- this test's phase 3 caught it holding forever: probe_animtick
-- measured ~101 of 120 menu-idle frames ticking through WaitFrame
-- (the menu is modal inside a gfx command), so "WaitFrame = animating"
-- was false and the gate never opened during interactive battle.
--
-- THREE PHASES, both directions loudly, asserted as write-count DELTAS
-- against a watch over all six lines' anchor words:
--   1. STATIC: 600 idle frames, zero anchor writes on the live lines --
--      the jitter non-regression.  (Cell/VRAM stability across time is
--      hud_stability's job; this test watches the anchors themselves.)
--   2. ANIMATION: berserk-forced actions land while the watch stays
--      armed; still zero anchor writes -- transients are held, never
--      chased.  A bp change is the positive control that actions ran.
--   3. GENUINE MOVE: on a provably quiet stretch, move a live monster
--      16px right by writing its position word ($80c3+slot*2) -- the
--      same array the animation commands and Cmd_20 reloads write, so
--      this IS the class of change the latch left stale.  Vanilla's
--      cur_poi_set follows it (the sprite moves; $800f+16 is the
--      positive control), and the anchor must follow within a few
--      frames: exactly one word store (2 byte writes), value old+2
--      (16px = 2 tilemap words), VRAM cells re-hung at the new address,
--      then 300 more frames with zero further writes anywhere.
--
-- On the latch ROM this fails exactly at phase 3: the sprite moves, the
-- anchor stays frozen, and the hud line keeps pointing at where the
-- monster used to be.  That red run is recorded in this test's
-- introducing commit; the recompute commit flips it green.  The final
-- whole-run assert (every write across all six lines belongs to the one
-- phase-3 adoption) additionally pins the disable path's compare-before-
-- store: empty slots must not rewrite $0000 every frame.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local SHADOW = 0xecf1           -- OT6_SHADOW, 6 lines x 14 bytes
local STRIDE = 14

-- write watch over the whole shadow strip, filtered to the +0 anchor
-- bytes of each line.  counts[line] accumulates for the whole run;
-- phases assert deltas via mark()/delta().
local counts = { [0]=0, 0, 0, 0, 0, 0 }
local armed = false
emu.addMemoryCallback(function(addr, value)
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
local function vramWord(mapAddr)
  local vr = emu.memType.snesVideoRam
  return emu.read(mapAddr * 2, vr) + emu.read(mapAddr * 2 + 1, vr) * 256
end

local live, liveMark, runMark, mover, oldAnchor, oldCell, old800f
local actorSlot, bpBefore

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  -- settle: keep the guards alive through the whole test, find the lines
  H.call(function()
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
    live = liveLines()
    for _, i in ipairs(live) do
      H.log(string.format("line %d live, anchor $%04x",
        i, H.readWord(SHADOW + i * STRIDE)))
    end
    H.assertEq(#live >= 2, true, "both guards' hud lines are live")
    armed = true
    runMark = snap()
    liveMark = snap()
  end),

  -- phase 1: STATIC.  600 idle frames, zero anchor writes on live lines.
  H.waitFrames(600),
  H.call(function()
    local d = delta(liveMark, live)
    H.log(string.format("static: %d live-line anchor writes in 600 frames", d))
    H.assertEq(d, 0, "static stretch writes no live anchors")
  end),

  -- phase 2: ANIMATION.  berserk the party (menu-less forced actions,
  -- hud_stability's trick); the beam animations run their transient
  -- coord writes while the watch stays armed.
  H.call(function()
    liveMark = snap()
    actorSlot = H.readByte(0x62ca)
    bpBefore = H.readByte(0x3e9c + actorSlot * 2)
    for slot = 0, 3 do
      local a = 0x3ee5 + slot * 2
      H.writeByte(a, H.readByte(a) | 0x10)
    end
  end),
  H.waitUntil(function()
    return H.readByte(0x3e9c + actorSlot * 2) ~= bpBefore
  end, 8000, "a forced action lands (positive control: animations ran)", 10),
  H.waitFrames(120),
  H.call(function()
    -- un-berserk and let the action queue drain before the quiet phase
    for slot = 0, 3 do
      local a = 0x3ee5 + slot * 2
      H.writeByte(a, H.readByte(a) & 0xEF)
    end
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
  end),
  H.waitFrames(300),
  H.call(function()
    local d = delta(liveMark, live)
    H.log(string.format("animation: %d live-line anchor writes through "
      .. "the action window", d))
    H.assertEq(d, 0, "animation transients are held, never adopted")
    H.screenshot("hudtrack_premove")
  end),

  -- phase 3: GENUINE MOVE.  first, prove the field is quiet: an enemy
  -- ATB action mid-flight could PopObjPos-restore right over the
  -- injected move (captured-before-write coords), which would fail the
  -- positive control confusingly instead of testing what this phase
  -- tests.  90 consecutive frames of settled position words = quiet.
  H.call(function()
    live = liveLines()
    mover = live[1]
    H.vars.settle = nil
  end),
  H.waitUntil(function()
    local sig = H.readWord(0x800f + mover * 2) * 0x10000
              + H.readWord(0x804b + mover * 2)
    local s = H.vars.settle
    if not s or s.sig ~= sig then
      H.vars.settle = { sig = sig, n = 1 }
      return false
    end
    s.n = s.n + 1
    return s.n >= 90
  end, 3000, "slot position settled for 90 consecutive frames", 1),
  -- inject only while NO battle script is in flight (OT6_SCRIPTBUSY,
  -- $57bf, == 0): an action mid-flight has PushObjPos-saved the old
  -- coords and its PopObjPos would silently erase the injection
  -- (measured: probe_animtick watched $800f snap back to 48 when a
  -- guard action's restore fired over the moved value).  injecting at
  -- flag==0 is safe both ways: a script starting AFTER the injection
  -- pushes-and-pops the MOVED coords, so the move survives it.
  H.waitUntil(function()
    if H.readByte(0x57bf) ~= 0 then return false end
    oldAnchor = H.readWord(SHADOW + mover * STRIDE)
    oldCell = vramWord(oldAnchor)
    old800f = H.readWord(0x800f + mover * 2)
    liveMark = snap()
    local x = H.readWord(0x80c3 + mover * 2)
    H.writeWord(0x80c3 + mover * 2, (x + 16) % 0x10000)
    H.log(string.format(
      "moved slot %d: $80c3 %d -> %d, anchor was $%04x head cell $%04x",
      mover, x, x + 16, oldAnchor, oldCell))
    H.vars.movedAt = H.frame
    return true
  end, 1800, "a script-free frame to inject the move on", 1),
  -- adoption lands at the next script-free builder pass.  in this
  -- fixture the guards act nearly continuously (probe_animtick: the
  -- busy flag is up ~95% of interactive time), so the gap -- and with
  -- it the adoption -- can be seconds out.  that latency is the
  -- design's honest beat: adopt only what a settled frame shows.
  H.waitUntil(function()
    return H.readWord(SHADOW + mover * STRIDE) == (oldAnchor + 2) % 0x10000
  end, 900, "anchor adopts the moved monster (old + 2 words for 16px)", 1),
  H.call(function()
    H.log(string.format("adopted %d frames after injection",
      H.frame - H.vars.movedAt))
    -- positive control: vanilla itself still tracks the move (an
    -- in-flight restore would have snapped $800f back and the adopt
    -- wait above would have timed out instead)
    H.assertEq(H.readWord(0x800f + mover * 2), (old800f + 16) % 0x10000,
      "cur_poi_set followed the move (the battlefield really changed)")
    H.assertEq(delta(liveMark, { mover }), 2,
      "exactly one word store adopted it (2 byte writes)")
  end),
  -- give the NMI flush a few frames to execute the transition (its
  -- one-shot blank+rehang is v-counter admission-gated and may defer
  -- a frame when the NMI runs late)
  H.waitFrames(5),
  H.call(function()
    -- the flush re-hung the cells: blank-old covers A0..A0+4, write-new
    -- covers A0+2..A0+6, so the net is head word blanked and the old
    -- head glyph now sitting one cell pair to the right.  the blank word
    -- is vanilla's $01EE fill: an abandoned cell must be word-identical
    -- to one never touched, or an animation's bg3-16x16 window renders
    -- it as junk (the Lete entrance flash -- battle_hudtrail's bug; a
    -- $21FF here was that bug's fingerprint, not part of this test's
    -- contract, which only needs "no glyph left behind").
    H.assertEq(vramWord(oldAnchor), 0x01ee, "old head cell blanked")
    H.assertEq(vramWord(oldAnchor + 2), oldCell, "cells re-hung at +2")
    H.screenshot("hudtrack_postmove")
    liveMark = snap()
  end),
  H.waitFrames(300),
  H.call(function()
    local d = delta(liveMark, ALL)
    H.log(string.format("post-move: %d anchor writes in 300 frames", d))
    H.assertEq(d, 0, "no oscillation after adoption")
    -- whole-run accounting: the one adoption is the ONLY anchor write
    -- the entire test saw, on any of the six lines -- live ones (no
    -- jitter, no chased transients) and empty ones (the disable path
    -- compares before storing; it must not rewrite $0000 every frame).
    local total = delta(runMark, ALL)
    H.log(string.format("whole run: %d anchor writes across all six lines",
      total))
    H.assertEq(total, 2, "the phase-3 adoption is the run's only write")
    H.log("ok: anchors quiet when static, held through animations, "
      .. "adopted on genuine change")
  end),
}, "hud anchor tracking")

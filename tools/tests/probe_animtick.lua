-- probe_animtick: MEASUREMENT probe for the hud anchor's tick-provenance
-- gate.  battle_hudtrack's phase 3 shows the recompute not adopting a
-- genuine move; this instruments who ticks each frame and what the
-- builder's gate actually reads.
--
-- Exec callbacks on THIS BUILD's addresses (from ff6-en.dbg / rom bytes,
-- 2026-07-19 build acda1813; throwaway probe, not a suite member, so
-- hardcoded addresses are acceptable here):
--   $F00963  Ot6ScriptBegin_ext entry ($04 wrapper raise)
--   $F0096A  Ot6ScriptEnd_ext entry ($04 wrapper clear)
--   $F00AC6  Ot6BgHudLine @done gate: lda f:$7e57bf (per line, per frame)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local begin, done, gates, gate1 = 0, 0, 0, 0
local tracing = false
local perframe = {}
emu.addMemoryCallback(function()
  begin = begin + 1
end, emu.callbackType.exec, 0xF00963, 0xF00963)
emu.addMemoryCallback(function()
  done = done + 1
end, emu.callbackType.exec, 0xF0096A, 0xF0096A)
emu.addMemoryCallback(function()
  if not tracing then return end
  gates = gates + 1
  if H.readByte(0x57bf) ~= 0 then gate1 = gate1 + 1 end
end, emu.callbackType.exec, 0xF00AC6, 0xF00AC6)

-- what does C2 dispatch? ExecBtlGfx_ext entry = C10000 (btlgfx @0000);
-- log each command byte (A at entry) with its frame.
local cmds = {}
emu.addMemoryCallback(function()
  if not tracing then return end
  local a = emu.getState()["cpu.a"] % 256
  cmds[#cmds + 1] = string.format("%d:%02x", H.frame, a)
end, emu.callbackType.exec, 0xC10000, 0xC10000)

local function sample(tag, frames)
  return H.repeatN(1, {
    H.call(function()
      begin, done, gates, gate1 = 0, 0, 0, 0
      tracing = true
      H.vars.t0 = H.frame
    end),
    H.waitFrames(frames),
    H.call(function()
      tracing = false
      local n = H.frame - H.vars.t0
      H.log(string.format(
        "%s: %d frames | script begins %d | ends %d | gate reads %d "
        .. "(nonzero %d) | $57bf now %02x | anchors L2=%04x L3=%04x",
        tag, n, begin, done, gates, gate1, H.readByte(0x57bf),
        H.readWord(0xecf1 + 2*14), H.readWord(0xecf1 + 3*14)))
    end),
  })
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function() H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500) end),

  sample("idle-1", 120),
  sample("idle-2", 120),

  H.call(function()
    local x = H.readWord(0x80c3 + 2 * 2)
    H.writeWord(0x80c3 + 2 * 2, (x + 16) % 0x10000)
    H.log(string.format("MOVED slot 2: $80c3 %d -> %d, $800f=%d, $804b=%04x, "
      .. "$8057=%04x, species=%04x",
      x, x + 16, H.readWord(0x800f + 4), H.readWord(0x804b + 4),
      H.readWord(0x8057 + 4), H.readWord(0x57c0 + 4)))
  end),
  H.call(function() cmds = {} end),
  sample("post-move", 120),
  H.call(function()
    local nonwait = {}
    for _, c in ipairs(cmds) do
      if not c:match(":01$") then nonwait[#nonwait + 1] = c end
    end
    H.log("non-$01 dispatches in post-move: " .. (#nonwait > 0
      and table.concat(nonwait, " ") or "(none)"))
    H.log("total dispatches: " .. #cmds)
  end),
  sample("post-move-2", 480),
  H.call(function()
    H.log(string.format("final: $800f=%d anchor L2=%04x $57bf=%02x",
      H.readWord(0x800f + 4), H.readWord(0xecf1 + 2*14), H.readByte(0x57bf)))
  end),
}, "animtick probe")

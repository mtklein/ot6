-- @manual
-- probe_nerapalab_seeds.lua -- which idle counts draw which Nerapa seed.
--
-- The lab's seed knob is "stand IDLE frames at the doorstep, then talk",
-- but the talk gesture (face right, A on a 48-frame cadence) engages
-- Nerapa a variable number of frames after the idle ends -- the first
-- A lands or the next one does -- so the seed InitBattle draws is not
-- idle + constant: the 2026-09-07 batch drew $A0 for BOTH idle 37 and
-- idle 52 (frame-identical fights).  This probe loads nerapalab_doorstep
-- once, snapshots it, and for every candidate idle reloads, idles, talks
-- until the battle starts loading, and logs the seed off the `sta $be`
-- store, so a batch can be given idles that draw DISTINCT seeds.
-- Snapshot/restore, reads and pad presses only; no fight is played.
local H = dofile("tools/tests/lib/ot6.lua")

local IDLES = { 0, 3, 7, 10, 15, 18, 22, 26, 30, 33, 37, 41, 45, 48, 52, 56 }

local seed, seenAt = nil, nil
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    seed, seenAt = emu.getState()["cpu.a"] & 0xff, H.frame
  end, emu.callbackType.exec, addr, addr)
end

local blob
local function seq(steps) return H.cond(function() return true end, steps) end
local function reload()
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blob) end),
    H.waitFrames(2),
    H.call(function() H.checkReq(req, "doorstep reload") end),
    H.waitFrames(30),
  })
end

local function trial(idle)
  local t = 0
  return seq({
    reload(),
    H.call(function() seed, seenAt, t = nil, nil, 0 end),
    H.waitFrames(idle),
    H.driveUntil(function()
      t = t + 1
      return seed ~= nil or t >= 1200
    end, 1500, {
      H.call(function()
        local c = t % 48
        if c < 4 then H.setPad({ right = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, string.format("idle %d: Nerapa's InitBattle seeds", idle)),
    H.call(function()
      H.setPad({})
      H.log(string.format("[seed] idle=%d seed=%s engaged_after=%s phase=%d",
        idle, seed and string.format("$%02X", seed) or "none", tostring(t), H.readByte(0x021E)))
    end),
  })
end

local steps = {
  H.loadState("build/states/nerapalab_doorstep.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    armSeedWatch()
    local req = H.requestSaveState()
    H.vars = H.vars or {}
    H.vars.req = req
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(H.vars.req, "doorstep snapshot")
    blob = H.vars.req.blob
  end),
}
for _, idle in ipairs(IDLES) do steps[#steps + 1] = trial(idle) end
H.run({ maxFrames = 60000 }, steps)

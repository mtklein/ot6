-- probe_vargasstall.lua -- why does battle_vargas's phase 3a stop reaching
-- "both Ipoohs down + a plain weapon hit on VARGAS" on the wave ROM?
-- Boots the same fixture, clamps the Ipoohs to 1 HP exactly as the test
-- does, taps A the same way, and logs the fight's vitals every 600 frames.
-- MEASUREMENT ONLY -- no assertions.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local IPOOH, VARGAS = 0x014D, 0x0103
local SABIN_E = 3
local function MHP(s) return 0x3BFC + s * 2 end
local function SH(s)  return 0x3E40 + s * 2 end

local vSlot
local function monsterAlive(s) return H.readByte(0x3AA8 + s * 2) % 2 == 1 end
local function ipoohsDown()
  for s = 0, 5 do
    if H.readWord(0x57C0 + s * 2) == IPOOH and monsterAlive(s) then return false end
  end
  return true
end
local function clampIpoohs()
  for s = 0, 5 do
    if s ~= vSlot and H.readWord(0x57C0 + s * 2) == IPOOH and monsterAlive(s)
       and H.readWord(MHP(s)) > 1 then
      H.writeWord(MHP(s), 1)
    end
  end
end

local ticks = 0
H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleActive() end, 6000, {
    H.call(function() H.setPad({ "a" }) end), H.waitFrames(4),
    H.call(function() H.setPad({}) end), H.waitFrames(10),
  }, "the vargas battle comes up"),
  H.waitFrames(120),
  H.call(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == VARGAS then vSlot = s end
    end
    H.log("vargas slot " .. tostring(vSlot))
  end),
  H.driveUntil(function()
    ticks = ticks + 1
    if ticks % 60 == 0 then
      local ip = {}
      for s = 0, 5 do
        if H.readWord(0x57C0 + s * 2) == IPOOH then
          ip[#ip + 1] = string.format("s%d hp=%d alive=%s", s, H.readWord(MHP(s)),
            tostring(monsterAlive(s)))
        end
      end
      H.log(string.format("f%d menu=%02x mstate=%02x actor=%d vHP=%d sh=%d | %s",
        H.frame, H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR),
        H.readWord(MHP(vSlot)), H.readByte(SH(vSlot)),
        table.concat(ip, " ; ")))
    end
    return ipoohsDown()
  end, 24000, {
    H.call(function()
      clampIpoohs()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then
        H.setPad({})
      else
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "both ipoohs down"),
  H.call(function()
    H.log("ipoohs down at frame " .. H.frame)
    H.screenshot("vargasstall")
  end),
  H.logStep(function() return "probe_vargasstall complete" end),
})

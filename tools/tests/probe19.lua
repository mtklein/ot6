-- probe19.lua: battle-entry deep diagnostic from the doorstep savestate.
-- Loads battle_doorstep.mss, walks into the battle, then samples screenshots
-- and RAM at several points to see exactly what battle entry does.
-- Always exits 0 (pure diagnostic).

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function dumpRam(tag)
  local b = {}
  for a = 0x3F40, 0x3F57 do b[#b + 1] = string.format("%02X", H.readByte(a)) end
  H.log(tag .. " bytes $3F40-$3F57: " .. table.concat(b, " "))
  local g = {}
  for a = 0x3ECB, 0x3ED2 do g[#g + 1] = string.format("%02X", H.readByte(a)) end
  H.log(tag .. " glyphs $3ECB-$3ED2: " .. table.concat(g, " "))
  local s = {}
  for a = 0x3E38, 0x3E4B do s[#s + 1] = string.format("%02X", H.readByte(a)) end
  H.log(tag .. " shields $3E38-$3E4B: " .. table.concat(s, " "))
  local hp = H.partyHp()
  H.log(string.format("%s hp=%d,%d,%d,%d", tag, hp[1], hp[2], hp[3], hp[4]))
end

local function sample(d)
  return H.call(function()
    local ok, png = pcall(emu.takeScreenshot)
    local len = (ok and type(png) == "string") and #png or -1
    H.log(string.format("d%04d screenshot %d bytes", d, len))
    H.screenshot(string.format("diag%04d", d))
    dumpRam(string.format("d%04d", d))
  end)
end

H.run({ maxFrames = 10000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.logStep(function() return "battle load at frame " .. H.frame end),
  sample(0),
  H.waitFrames(60), sample(60),
  H.waitFrames(120), sample(180),
  H.waitFrames(240), sample(420),
  H.waitFrames(480), sample(900),
  H.waitFrames(600), sample(1500),
  H.waitFrames(900), sample(2400),
})

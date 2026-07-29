-- probe_breakvis.lua -- #48 scratch: does the break flash actually reach the
-- PPU?  Forces a flash on the doorstep guards and dumps, per live frame:
-- the wram palette slot, CGRAM obj-palette-3, and every OAM entry's palette
-- field.  Not a suite test.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local BRKTICK, SPRDATA = 0xED76, 0x80DB
local G = { 4, 6 }
local rows = {}
local shots = {}
local watching = false

local function oamPalHisto()
  local h = {}
  for i = 0, 127 do
    local a = emu.read(i * 4 + 3, emu.memType.snesSpriteRam)
    local p = (a >> 1) & 0x07
    h[p] = (h[p] or 0) + 1
  end
  local t = {}
  for p = 0, 7 do t[#t + 1] = string.format("p%d=%d", p, h[p] or 0) end
  return table.concat(t, " ")
end

local function sample()
  if not watching then return end
  local t1 = H.readByte(BRKTICK + G[1])
  local t2 = H.readByte(BRKTICK + G[2])
  if (t1 ~= 0 and t1 ~= 0xFF) or (t2 ~= 0 and t2 ~= 0xFF) then
    rows[#rows + 1] = string.format(
      "f%d tick=%02X/%02X db=%02X/%02X wram7f60=%04X cg160=%04X cg162=%04X | %s",
      H.frame, t1, t2,
      H.readByte(SPRDATA + G[1]), H.readByte(SPRDATA + G[2]),
      H.readWord(0x7F60), emu.readWord(0x160, emu.memType.snesCgRam),
      emu.readWord(0x162, emu.memType.snesCgRam), oamPalHisto())
    if #rows == 3 or #rows == 6 then
      local ok, png = pcall(emu.takeScreenshot)
      if ok and #png > 0 then shots[#shots + 1] = { n = #rows, png = png } end
    end
  end
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
  H.waitFrames(300),
  H.call(function()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    watching = true
    for _, g in ipairs(G) do
      H.writeByte(0x618B + (g >> 1), 1)          -- vanilla turn-flash spent
      H.writeByte(BRKTICK + g, 0xFF)             -- both pending
    end
    H.log("cgram before: " .. string.format("%04X %04X",
      emu.readWord(0x160, emu.memType.snesCgRam),
      emu.readWord(0x162, emu.memType.snesCgRam)))
    H.log("oam pal histogram before: " .. oamPalHisto())
  end),
  H.driveUntil(function() return #rows >= 10 end, 6000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(1),
  }, "ten live flash frames"),
  H.release(),
  H.call(function()
    watching = false
    for _, r in ipairs(rows) do H.log(r) end
    for _, s in ipairs(shots) do H.emitBlob("breakvis_" .. s.n .. ".png", s.png) end
  end),
  H.logStep(function() return "probe_breakvis complete" end),
})

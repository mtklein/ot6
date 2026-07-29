-- probe_dancerow.lua -- #34 diagnostic: does DrawDanceListText run when the
-- staged dance window opens, and what does the line buffer hold after the
-- decorator?  H.sym("DrawDanceListText") H.sym("Ot6DanceRowDecorate")
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local msPresent = {}
local danceId
local draws, decos = 0, 0
local bufdump = {}

local function pinField()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)
      H.writeByte(0x3ED8 + s * 2, 0x0A)
      H.writeByte(0x202E + s * 12 + 0 * 3, 0x13)
      H.writeByte(0x2031 + s * 12, 0xFF)
      H.writeByte(0x2034 + s * 12, 0xFF)
      H.writeByte(0x2037 + s * 12, 0xFF)
      H.writeWord(0x3BF4 + s * 2, 999)
    end
  end
  H.writeByte(0x1D4C, 1 << danceId)
  for i = 0, 7 do
    H.writeByte(0x267E + i, i == danceId and i or 0xFF)
  end
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)
    if H.readWord(0x3BFC + m * 2) < 0x6000 then H.writeWord(0x3BFC + m * 2, 0xF000) end
  end
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
    H.log("matching dance " .. danceId)
    pinField()
    local a = H.sym("DrawDanceListText")
    emu.addMemoryCallback(function()
      draws = draws + 1
      H.log(string.format("f%d DrawDanceListText (row arg pending)", H.frame))
    end, emu.callbackType.exec, a, a)
    local b = H.sym("Ot6DanceRowDecorate")
    emu.addMemoryCallback(function()
      decos = decos + 1
      local t = {}
      for i = 0, 14 do t[#t + 1] = string.format("%02x", H.readByte(0x5755 + i)) end
      bufdump[#bufdump + 1] = string.format("f%d deco-entry buf: %s", H.frame,
        table.concat(t, " "))
    end, emu.callbackType.exec, b, b)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),
  H.driveUntil(function() return H.readByte(MSTATE) == 0x21 end, 1500, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the dance list opens"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("draw calls=%d decorate calls=%d", draws, decos))
    for _, l in ipairs(bufdump) do H.log(l) end
    local t = {}
    for i = 0, 14 do t[#t + 1] = string.format("%02x", H.readByte(0x5755 + i)) end
    H.log("final buf: " .. table.concat(t, " "))
    -- where did the staged lines land?  scan all vram for the name run
    local seq = { 0x8B, 0xA8, 0xAF, 0x9E }   -- "Love"
    local vr = emu.memType.snesVideoRam
    local found = 0
    for w = 0x0000, 0x7FF0 do
      local hit = true
      for i = 1, #seq do
        if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
      end
      if hit then
        found = found + 1
        H.log(string.format("'Love' at vram word %04x (map $%04x row %d col %d)",
          w, w - (w % 0x400), (w % 0x400) >> 5, w & 0x1F))
      end
    end
    if found == 0 then H.log("'Love' NOT in vram anywhere") end
    -- and what does the line-transfer QUEUE say?
    H.log(string.format("7ba9=%02x 7ba5=%02x 7ba6=%02x", H.readByte(0x7BA9),
      H.readByte(0x7BA5), H.readByte(0x7BA6)))
  end),
  H.logStep(function() return "probe_dancerow complete" end),
})

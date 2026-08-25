local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 1000 }, {
  H.loadState("build/states/fc_shadow.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("1EDE=%02X 1EDF=%02X 1EB4=%02X 1EB5=%02X shadow-party=%02X",
      H.readByte(0x1EDE), H.readByte(0x1EDF), H.readByte(0x1EB4),
      H.readByte(0x1EB5), H.readByte(0x1850 + 3)))
    H.log(string.format("1ED7=%02X (bit5=%d)", H.readByte(0x1ED7), (H.readByte(0x1ED7) >> 5) & 1))
  end),
  H.logStep(function() return "done" end),
})

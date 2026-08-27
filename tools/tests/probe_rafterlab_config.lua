-- probe_rafterlab_config.lua -- rafter lab: read the config bytes the
-- catwalk fixture carries (battle speed, message speed, battle mode),
-- to decide whether a config-tuned fixture is worth building.  Reads only.
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 2000 }, {
  H.loadState("build/states/rafterlab_catwalk.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    for a = 0x1D4C, 0x1D4F do
      H.log(string.format("[cfg] $%04X = %02X", a, H.readByte(a)))
    end
  end),
})

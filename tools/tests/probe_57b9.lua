-- probe_57b9.lua -- write-watcher: is $7E57B9 (candidate OT6_FONTDIRTY
-- relocation target, spare byte in the m2 trace-verified strip) free of
-- vanilla writers?  Watches $7E57B9-$7E57BF through doorstep -> battle ->
-- Fire Beam banner -> resolution.  $7E57D5 rides along as the positive
-- control: the banner machinery MUST hit it (GfxCmd_01 et al).

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local hits = {}       -- addr -> { count, pcs = {pcstr -> n} }
local function watch(lo, hi)
  emu.addMemoryCallback(function(addr, value)
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} }; hits[addr] = h end
    h.count = h.count + 1
    local ok = pcall(function()
      local s = emu.getState()
      local pc = string.format("%02X:%04X v=%02X", s["cpu.k"], s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
    end)
  end, emu.callbackType.write, lo, hi)
end

watch(0x7E57B9, 0x7E57BF)
watch(0x7E57D5, 0x7E57D5)

H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6), H.waitFrames(24),
  H.pressButtons({ "a" }, 6),
  H.waitFrames(400),

  H.call(function()
    local addrs = {}
    for a in pairs(hits) do addrs[#addrs + 1] = a end
    table.sort(addrs)
    for _, a in ipairs(addrs) do
      local h = hits[a]
      local pcs = {}
      for pc, n in pairs(h.pcs) do pcs[#pcs + 1] = pc .. " x" .. n end
      table.sort(pcs)
      H.log(string.format("W $%06X: %d writes | %s", a, h.count,
        table.concat(pcs, " | ")))
    end
    if next(hits) == nil then H.log("no writes observed at all (bad watcher?)") end
  end),
})

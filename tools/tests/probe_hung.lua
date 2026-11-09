-- probe_hung.lua (#519): load the hung state and dump the battle-end cells
local H = dofile("tools/tests/lib/ot6.lua")
local function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", H.readByte(a + i)) end
  return table.concat(t, " ")
end
local function dump(tag)
  H.log("[probe] " .. tag .. " f" .. H.frame)
  H.log("[probe] present3AA8 " .. hex(0x3AA8, 20))
  H.log("[probe] hp3BF4     " .. hex(0x3BF4, 20))
  H.log("[probe] st3EE4     " .. hex(0x3EE4, 20))
  H.log("[probe] st3EF8     " .. hex(0x3EF8, 20))
  H.log("[probe] 3A2x       " .. hex(0x3A20, 32))
  H.log("[probe] 3A4x-3A9x  " .. hex(0x3A40, 80))
  H.log("[probe] 3AC8       " .. hex(0x3AC8, 16))
  H.log("[probe] 3F4x       " .. hex(0x3F40, 16))
  H.log("[probe] 2F4x       " .. hex(0x2F40, 16))
  H.log("[probe] B0-BF      " .. hex(0xB0, 16))
  H.log("[probe] 7BC2/7BCA  " .. hex(0x7BC2, 1) .. " " .. hex(0x7BCA, 1) .. " actor " .. hex(0x62CA, 1))
  H.log("[probe] 3EE0       " .. hex(0x3EE0, 4))
  H.log("[probe] 3AA0-3AA7  " .. hex(0x3AA0, 8))
  H.log("[probe] 3A6x       " .. hex(0x3A60, 16))
  H.log("[probe] 3A38       " .. hex(0x3A38, 8))
  H.log("[probe] 3A70-3A9F  " .. hex(0x3A70, 48))
  H.log("[probe] 2F4C-2F4F  " .. hex(0x2F4C, 4) .. " 3A3A " .. hex(0x3A3A, 1) .. " 3408/9 " .. hex(0x3408, 2))
  H.log("[probe] 3018/3021  " .. hex(0x3018, 12) .. " | " .. hex(0x3021, 12))
  H.log("[probe] 3ebc/3ee0/3a6e " .. hex(0x3EBC, 1) .. " " .. hex(0x3EE0, 1) .. " " .. hex(0x3A6E, 1) .. " 1dd1 " .. hex(0x1DD1, 1))
  H.log("[probe] 3AA8-3AB7 " .. hex(0x3AA8, 16) .. " 3EEC st1 " .. hex(0x3EEC, 12))
  H.log("[probe] 3219 atb " .. hex(0x3219, 20) .. " 3AC8 " .. hex(0x3AC8, 20))
  H.log("[probe] 32cc/3184 " .. hex(0x32CC, 20) .. " | " .. hex(0x3184, 12))
  H.log("[probe] 340A/3407/3A68/69 " .. hex(0x340A, 1) .. " " .. hex(0x3407, 1) .. " " .. hex(0x3A68, 2) .. " 2F2F " .. hex(0x2F2F, 1) .. " 3A58 " .. hex(0x3A58, 1) .. " 3A46 " .. hex(0x3A46, 1) .. " 3402 " .. hex(0x3402, 1))
  H.log("[probe] 3A44 " .. hex(0x3A44, 8) .. " 3A8x " .. hex(0x3A88, 8) .. " B0/B1 " .. hex(0xB0, 2) .. " 3A5A " .. hex(0x3A5A, 4))
end
local pcs, total = {}, 0
local function hist()
  emu.addMemoryCallback(function(addr)
    pcs[addr] = (pcs[addr] or 0) + 1
    total = total + 1
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
end
local function stack(tag)
  local st = emu.getState()
  local sp = st["cpu.sp"] & 0xffff
  local t = {}
  for i = 1, 64 do t[#t + 1] = string.format("%02X", emu.read(sp + i, emu.memType.snesMemory)) end
  H.log(string.format("[probe] %s sp=%04X pc=%02X:%04X stack+1..: %s", tag, sp, st["cpu.k"] & 0xff, st["cpu.pc"] & 0xffff, table.concat(t, " ")))
end
local function script()
  H.log("[probe] dp76 " .. hex(0x76, 4) .. " dp10 " .. hex(0x10, 6))
  local ptr = H.readWord(0x76)
  H.log(string.format("[probe] script ptr %04X; commands from 2D6E (4 bytes each):", ptr))
  local a = 0x2D6E
  for i = 0, 40 do
    local b = H.readByte(a + i * 4)
    H.log(string.format("[probe]   %04X: %s%s", a + i * 4, hex(a + i * 4, 4), (a + i * 4 == ptr) and "   <== current" or ""))
    if b == 0xFF then break end
  end
  H.log("[probe] data 2C6E.. " .. hex(0x2C6E, 64))
  H.log("[probe] 62a5.. " .. hex(0x62A5, 8) .. " 628c " .. hex(0x628C, 1) .. " 7b3d " .. hex(0x7B3D, 1))
end
local function report()
  local t = {}
  for a, n in pairs(pcs) do t[#t + 1] = { a, n } end
  table.sort(t, function(x, y) return x[2] > y[2] end)
  H.log("[probe] exec C2 total " .. total .. " distinct " .. #t)
  for _, a in ipairs({0xC20019, 0xC20033, 0xC20049, 0xC2004E, 0xC20062, 0xC2006F, 0xC2007D, 0xC20092, 0xC22163, 0xC24B7B, 0xC247ED, 0xC24807, 0xC24833, 0xC2488C}) do
    H.log(string.format("[probe] key %06X x%d", a, pcs[a] or 0))
  end
  for i = 1, math.min(60, #t) do H.log(string.format("[probe] pc %06X x%d", t[i][1], t[i][2])) end
end
local steps = {
  H.waitFrames(20),
  H.loadState("build/states/nav519_hung.mss.lua"),
  H.waitFrames(2),
  H.call(function() dump("loaded") hist() end),
  H.waitFrames(600),
  H.call(function() dump("+600") stack("a") script() H.screenshot("hung600") end),
  H.waitFrames(1),
  H.call(function() stack("c") end),
  H.waitFrames(3),
  H.call(function() stack("d") end),
  H.waitFrames(60),
  H.call(function() dump("+660") stack("b") report() end),
}
H.run({ maxFrames = 5000, retries = 1 }, steps)

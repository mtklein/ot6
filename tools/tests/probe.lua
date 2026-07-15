-- probe.lua: joypad-register spoofing test. Exit 0.
local function say(s) print("[probe] " .. s) end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        .. B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        .. (b and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "=")
        .. (c and B64:sub(n % 64 + 1, n % 64 + 1) or "=")
  end
  return table.concat(out)
end

local function emitScreenshot(tag)
  local ok, png = pcall(emu.takeScreenshot)
  if not ok or type(png) ~= "string" or #png == 0 then
    say("shot " .. tag .. ": EMPTY")
    return
  end
  say("shot " .. tag .. ": " .. #png .. " bytes")
  local enc = b64encode(png)
  for i = 1, #enc, 4000 do print("[b64:" .. tag .. "] " .. enc:sub(i, i + 3999)) end
end

-- current spoofed pad state (16-bit joypad 1 value: hi=BYSelStUDLR, lo=AXLR0000)
local padLo, padHi = 0, 0
local buttons = {
  a = { "lo", 0x80 }, x = { "lo", 0x40 }, l = { "lo", 0x20 }, r = { "lo", 0x10 },
  b = { "hi", 0x80 }, y = { "hi", 0x40 }, select = { "hi", 0x20 }, start = { "hi", 0x10 },
  up = { "hi", 0x08 }, down = { "hi", 0x04 }, left = { "hi", 0x02 }, right = { "hi", 0x01 },
}
local function setPad(held)
  padLo, padHi = 0, 0
  if held then
    for name in pairs(held) do
      local spec = buttons[name]
      if spec then
        if spec[1] == "lo" then padLo = padLo | spec[2] else padHi = padHi | spec[2] end
      end
    end
  end
end

local reads = 0
emu.addMemoryCallback(function(addr, value)
  reads = reads + 1
  if addr == 0x4218 then return padLo end
  if addr == 0x4219 then return padHi end
end, emu.callbackType.read, 0x4218, 0x4219)

local frame = 0
emu.addEventCallback(function()
  frame = frame + 1

  if frame == 10 then
    for port = 0, 4 do
      local ok, inp = pcall(emu.getInput, port)
      local n = 0
      if ok and type(inp) == "table" then for _ in pairs(inp) do n = n + 1 end end
      say("port " .. port .. ": ok=" .. tostring(ok) .. " nkeys=" .. n)
    end
  end

  -- Press start: frames 500-507, 620-627 (title -> save select)
  if (frame >= 500 and frame < 508) or (frame >= 620 and frame < 628) then
    setPad({ start = true })
  else
    setPad(nil)
  end

  if frame == 490 then emitScreenshot("t0490") end
  if frame == 610 then emitScreenshot("t0610") end
  if frame == 740 then
    emitScreenshot("t0740")
    say("joypad reads intercepted: " .. reads)
    emu.stop(0)
  end
end, emu.eventType.startFrame)

say("probe4 registered")

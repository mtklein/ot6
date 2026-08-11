-- probe_v07_fly.lua -- flight-register instrument (issue #31, step F->G).
-- Cold-Continues terra-returned-v1, boards with A, then holds each
-- direction while dumping the candidate position cells, then tries B
-- (land) and X (deck) so the step gen knows every control.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function map() return H.mapId() & 0x1ff end

local function dump(tag)
  local zp = {}
  for a = 0x28, 0x3f do zp[#zp + 1] = string.format("%02X", H.readByte(a)) end
  H.log(string.format("[%s] f%d map=%03X zp28..3f= %s | e0=%d e2=%d c2=%02X "
    .. "11F3=%02X 11FA=%02X 19=%02X e7=%02X e8=%02X 59=%02X",
    tag, H.frame, H.readWord(0x1f64), table.concat(zp, " "),
    H.readByte(0xe0), H.readByte(0xe2), H.readByte(0xc2),
    H.readByte(0x11F3), H.readByte(0x11FA), H.readByte(0x19),
    H.readByte(0xe7), H.readByte(0xe8), H.readByte(0x59)))
end

local function holdDump(dir, frames, tag)
  local n = 0
  return H.driveUntil(function() return n >= frames end, frames + 60, {
    H.call(function()
      n = n + 1
      if n % 60 == 0 then dump(tag .. n) end
      H.setPad({ [dir] = true })
    end),
  }, "hold " .. tag)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "world", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  dump and H.call(function() dump("boot") end),

  H.pressButtons({ "a" }, 8),
  H.waitFrames(60), H.call(function() dump("board60") end),
  H.waitFrames(120), H.call(function() dump("board180") end),
  H.waitFrames(240), H.call(function() dump("board420") end),
  H.call(function() H.screenshot("v07f_board") end),

  holdDump("right", 240, "R"),
  H.release(), H.waitFrames(30), H.call(function() dump("afterR") end),
  holdDump("down", 240, "D"),
  H.release(), H.waitFrames(30), H.call(function() dump("afterD") end),
  holdDump("left", 240, "L"),
  H.release(), H.waitFrames(30), H.call(function() dump("afterL") end),
  holdDump("up", 240, "U"),
  H.release(), H.waitFrames(30), H.call(function() dump("afterU") end),
  H.call(function() H.screenshot("v07f_flew") end),

  -- X: exit to deck?
  H.pressButtons({ "x" }, 8),
  H.waitFrames(240),
  H.call(function()
    dump("afterX")
    H.log(string.format("[afterX] map=%d field=(%d,%d)", map(), H.fieldX(), H.fieldY()))
    H.screenshot("v07f_afterX")
  end),
  H.logStep("fly probe complete"),
})

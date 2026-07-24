-- probe_fight.lua -- boot dadaluma_doorstep, face the gentleman and talk,
-- logging dialog/event/battle state every 30 frames to learn how battle 69
-- is actually triggered. Read-only.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/dadaluma_doorstep.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[boot] map=%d (%d,%d) $034A=%d ctl=%s",
      map(), H.fieldX(), H.fieldY(), sw(0x034A), tostring(H.hasControl())))
    -- party char current HP (char records $1600, cur HP at +9 word, 37/rec)
    for c = 0, 3 do
      local base = 0x1600 + c * 37
      H.log(string.format("  char%d id=%02X curHP=%d maxHP=%d",
        c, H.readByte(base), H.readWord(base + 9), H.readWord(base + 11)))
    end
  end),
  -- face down and tap A ONCE to start the talk
  H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(6),
  H.hold({ "a" }), H.waitFrames(4), H.release(), H.waitFrames(4),
  -- ROBUST drive: kill-bit any monsters, broadly edge-A (4 on/4 off) to
  -- push every dialog incl the reward, until the win clears $034A and
  -- control returns on the roof at (30,13).
  (function()
    local ph, hb = 0, 0
    return H.driveUntil(function()
      return sw(0x034A) == 0 and map() == 221 and H.hasControl()
        and H.tileAligned() and bright() >= 15
    end, 12000, {
      H.call(function()
        hb = hb + 1; ph = (ph + 1) % 8
        if hb % 60 == 0 then
          H.log(string.format("[f%d] map=%d (%d,%d) $034A=%d ctl=%s ev=%s dlg=%s mon=%d bri=%d",
            hb, map(), H.fieldX(), H.fieldY(), sw(0x034A), tostring(H.hasControl()),
            tostring(H.eventRunning()), tostring(H.dialogWaiting()),
            H.monstersPresent(), bright()))
        end
        if H.monstersPresent() > 0 then
          for s = 0, 5 do
            if H.readByte(0x3aa8 + s*2) % 2 == 1 then
              H.writeByte(0x3eec + s*2, H.readByte(0x3eec + s*2) | 0x80)
            end
          end
        end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "talk -> win")
  end)(),
  H.call(function()
    H.log(string.format("[after] map=%d (%d,%d) $034A=%d porch=%s",
      map(), H.fieldX(), H.fieldY(), sw(0x034A),
      tostring(H.bfsPath(33,10) ~= nil)))
  end),
})

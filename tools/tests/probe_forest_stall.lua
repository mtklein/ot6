-- @manual
-- probe_forest_stall.lua -- reproduce forest_done's post-battle stall on
-- map 132 (the party parks at (16,8) with an empty BFS plan forever) and
-- dump every hasControl component per pulse, so the blocked gate is a
-- measurement instead of a theory.  Read-only: pad presses and reads.
-- The dump rides navTo's own `arrive` thunk (evaluated every frame), and
-- the thunk doubles as the escape hatch so the timeout never raises.
local H = dofile("tools/tests/lib/ot6.lua")

local DOOR = "build/states/camp_escaped.mss.lua"
local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local hb, t0 = 0, nil
local function dumpControl(tag)
  local pc = H.readByte(0xE7) * 65536 + H.readByte(0xE6) * 256 + H.readByte(0xE5)
  H.log(string.format(
    "[%s] f%d (%d,%d) ctl=%s aligned=%s evt=%s dlg=%s | $087C=%02X " ..
    "$1EB9=%02X evtPC=%06X $0084=%02X $0059=%02X $BA=%02X $D3=%02X " ..
    "batt=%s bright=%d",
    tag, H.frame, H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    H.readByte(0x087C), H.readByte(0x1EB9), pc,
    H.readByte(0x0084), H.readByte(0x0059), H.readByte(0xBA),
    H.readByte(0xD3), tostring(H.battleLoadStarted()), bright()))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.worldNavTo(178, 82, {
    maxFrames = 25000,
    playBattles = "flee",
    arrive = function() return not H.worldMode() end,
  }),
  H.waitUntil(function()
    return mapIdx() == 132 and H.hasControl() and H.tileAligned()
  end, 4000, "map 132 control", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "map 132 fade", 10),
  H.waitFrames(30),
  H.call(function()
    t0 = H.frame
    H.log(string.format("[probe] on 132 at (%d,%d) f%d; walking toward the stall",
      H.fieldX(), H.fieldY(), H.frame))
    -- tile-property truth for the corridor: $7600 props (z bits 0/1,
    -- bridge 4, diagonal $40/$80) and $7700 exits, x=1..20, y=8 and 9
    for y = 8, 9 do
      local row = {}
      for x = 1, 20 do
        local tile = H.readByte(0x7F0000 + y * 256 + x)
        row[#row + 1] = string.format("%d:%02X/%02X", x,
          H.readByte(0x7600 + tile), H.readByte(0x7700 + tile))
      end
      H.log(string.format("[props y=%d] %s", y, table.concat(row, " ")))
    end
  end),
  H.navTo(28, 7, {
    maxFrames = 30000,
    playBattles = "flee",
    arrive = function()
      if mapIdx() == 133 then return true end          -- genuine success
      -- dense tap through the battle window: the wedge forms in the
      -- ~900 frames after the encounter fires, so sample fast there
      local cadence = H.battleLoadStarted() and 60 or 300
      if H.frame - hb >= cadence then
        hb = H.frame
        dumpControl("watch")
        if H.battleLoadStarted() then
          local mons = {}
          for s = 0, 5 do
            if H.readByte(0x3AA8 + s * 2) % 2 == 1 then
              mons[#mons + 1] = string.format("s%d:%d", s,
                H.readWord(0x3BFC + 8 + s * 2))
            end
          end
          H.log(string.format(
            "[batt] f%d present={%s} $3A76=%02X $3A77=%02X b_end=%02X " ..
            "$B2=%02X sub=%02X,%02X",
            H.frame, table.concat(mons, ","), H.readByte(0x3A76),
            H.readByte(0x3A77), H.readByte(0x3A6E), H.readByte(0xB2),
            H.readByte(0x0869), H.readByte(0x086C)))
        end
      end
      -- 14000 frames is several times the healthy crossing; by then the
      -- stall is established and the autopsy below takes over.
      return t0 ~= nil and (H.frame - t0) > 14000
    end,
  }),
  H.call(function()
    t0 = H.frame
    H.log(string.format("[probe] navTo ended on map %d at (%d,%d) f%d",
      mapIdx(), H.fieldX(), H.fieldY(), H.frame))
  end),
  H.driveUntil(function() return H.frame - t0 > 1100 end, 2400, {
    H.call(function()
      if H.frame - hb >= 120 then hb = H.frame; dumpControl("autopsy") end
      H.setPad({})
    end),
  }, "post-stall autopsy window"),
})

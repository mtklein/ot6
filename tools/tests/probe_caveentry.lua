-- probe_caveentry.lua -- watch a FAITHFUL cave battle's entry, frame by frame,
-- for the reported "white characters overdrawn" glitch.  Unlike probe_cavehud
-- (which force-loads a formation and had a suspicious hud-up-but-sprites-absent
-- window at entry), this paces kolts_cave's own map-96 pool to a NATURAL
-- encounter (Cirpius x3), so battle init -- monster gfx transfer, the fade-in,
-- the hud's first draw -- runs exactly as it does in play.  Dense screenshots
-- across entry + the settle, plus a per-frame note of hud-present vs the gfx
-- present buffer $2F2F, so a window where the hud is up while the sprites are
-- not is on the record.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local STATE = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua"
local DANGER = 0x1f6e
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function()
    H.assertEq(map(), 96, "kolts_cave on map 96")
    H.log("[caveentry] pacing map 96 pool for a natural encounter")
  end),

  -- pace the auto-detected walkable lane until a battle starts loading
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        H.writeWord(DANGER, 0xff00)
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),

  -- dense entry capture: from battle-load through the first ~160 frames, note
  -- hud-present vs $2F2F (gfx present buffer) every frame and shoot a burst.
  (function()
    local f = 0
    return H.driveUntil(function() f = f + 1; return f > 170 end, 220, {
      H.call(function()
        local hud = H.fieldHudPresent()
        local present2f = H.readByte(0x2f2f)
        local live = H.monstersPresent()
        if f <= 170 and f % 3 == 0 then
          H.screenshot(string.format("entry_f%03d", f))
        end
        if f % 4 == 0 then
          -- candidate "shown/entered" gates: $201e visible, $61ab shown,
          -- $2f2f gfx-present, and per-slot hidden flag $3ec2 (bit0).  find
          -- which one is CLEAR while the hud floats and SET after entry.
          local ec2 = {}
          for s = 0, 5 do ec2[#ec2 + 1] = string.format("%02x", H.readByte(0x3ec2 + s * 2)) end
          H.log(string.format(
            "[caveentry] f%d hud=%s 201e=%02x 61ab=%02x 2f2f=%02x 3ec2=[%s] veil=%02x active=%s",
            f, tostring(hud), H.readByte(0x201e), H.readByte(0x61ab), present2f,
            table.concat(ec2, " "), H.readByte(0x57be), tostring(H.battleActive())))
        end
      end),
    }, "entry captured")
  end)(),

  H.call(function()
    H.log(string.format("[caveentry] formation %04X %04X %04X %04X %04X %04X",
      table.unpack(H.formationWords())))
    H.screenshot("entry_settled")
    H.assertEq(true, true, "probe ran")
  end),
})

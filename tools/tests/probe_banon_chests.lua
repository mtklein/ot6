-- probe_banon_chests.lua -- replays the escort to the Green Cherry treasure
-- on map 109 at (26,21) (treasure bit 41), dumps walkability and the
-- $7E2000 logical-map bytes around the treasure tile, and attempts the
-- open from every reachable neighbour, logging the CheckTreasure gates:
-- the z gate reads $b8/$b2, the marker gate wants bit 7 of the facing
-- tile's $7E2000 byte.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local CX, CY = 26, 21

local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/returner_hideout.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),

  -- into map 109's vestibule
  H.navTo(10, 48, { maxFrames = 20000, arrive = mapChanged(),
    playBattles = "tactical" }),
  H.release(),
  H.waitFrames(120),
  H.waitUntil(function()
    return map() == 109 and H.hasControl() and H.tileAligned()
  end, 2000, "on map 109", 10),

  -- the greeter at (9,25): stage below, face up, edge-A, ride the escort
  H.navTo(9, 26, { maxFrames = 8000, playBattles = "tactical" }),
  H.release(),
  H.driveUntil(function() return H.eventRunning() or H.dialogWaiting() end,
    1200, {
      H.call(function()
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
        H.setPad(H.frame % 8 < 4 and { a = true } or {})
      end),
    }, "greeter engaged"),
  H.release(),
  H.advanceStory(function()
    return map() == 109 and sw(0x01F0) == 1 and H.hasControl()
       and H.tileAligned()
  end, 20000, { playBattles = "tactical" }),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] escorted: (%d,%d) $01F0=%d",
      H.fieldX(), H.fieldY(), sw(0x01F0)))
  end),

  -- walkability around the treasure tile
  H.call(function()
    for y = CY - 4, CY + 4 do
      local row = {}
      for x = CX - 5, CX + 5 do
        local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
          or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
        row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
      end
      H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
    end
    -- the logical-map bytes CheckTreasure indexes ($7E2000 + (y<<8|x)):
    -- the facing tile's byte needs bit 7
    for y = CY - 2, CY + 2 do
      local row = {}
      for x = CX - 2, CX + 2 do
        row[#row + 1] = string.format("%02X", H.readByte(0x2000 + y * 256 + x))
      end
      H.log(string.format("[tilemap] y=%2d x=%d..%d %s", y, CX - 2, CX + 2,
        table.concat(row, " ")))
    end
  end),

  -- attempt the open from each reachable neighbour
  H.call(function() end),
  (function()
    local attempts = {
      { CX, CY + 1, "up",    "below (26,22) face up"    },
      { CX + 1, CY, "left",  "right (27,21) face left"  },
      { CX - 1, CY, "right", "left (25,21) face right"  },
      { CX, CY - 1, "down",  "above (26,20) face down"  },
    }
    local steps = {}
    for _, a in ipairs(attempts) do
      local sx, sy, dir, label = a[1], a[2], a[3], a[4]
      steps[#steps + 1] = H.cond(function()
        if sw and H.chestOpen(41) then
          H.log("[probe] bit 41 already set; skipping " .. label)
          return false
        end
        local p = H.bfsPath(sx, sy)
        H.log(string.format("[probe] %s: %s", label,
          p and (#p .. " steps") or "NO PATH"))
        return p ~= nil
      end, {
        H.navTo(sx, sy, { maxFrames = 8000, playBattles = "tactical" }),
        H.release(),
        (function()
          local t = 0
          return H.driveUntil(function()
            t = t + 1
            return t > 500 or H.dialogWaiting()
          end, 700, {
            H.call(function()
              if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
              H.setPad(H.frame % 12 < 4 and { a = true } or {})
              if t % 120 == 0 then
                H.log(string.format(
                  "[probe] %s: t=%d at (%d,%d) face=%d $b8=%02X $b2=%02X " ..
                  "tile=%02X dlg=%s bit41=%s", label, t, H.fieldX(),
                  H.fieldY(), facing(), H.readByte(0x00b8), H.readByte(0x00b2),
                  H.readByte(0x2000 + CY * 256 + CX),
                  tostring(H.dialogWaiting()), tostring(H.chestOpen(41))))
              end
            end),
          }, label)
        end)(),
        H.release(),
        (function()
          local t = 0
          return H.driveUntil(function()
            t = t + 1
            return t > 400 or not H.dialogWaiting()
          end, 600, {
            H.call(function()
              H.setPad(H.frame % 8 < 4 and { a = true } or {})
            end),
          }, label .. ": dismiss")
        end)(),
        H.release(),
        H.call(function()
          H.log(string.format("[probe] %s: RESULT bit41=%s",
            label, tostring(H.chestOpen(41))))
        end),
      }, {})
    end
    return H.cond(function() return true end, steps)
  end)(),

  H.call(function()
    H.log(string.format("[probe] final: bit41=%s at (%d,%d)",
      tostring(H.chestOpen(41)), H.fieldX(), H.fieldY()))
  end),
})

-- probe_mog_take.lua -- takes MOG off the cliff. Boots wob_kupo.mss
-- ($023F=1, party at (9,19) on map 23, Mog hanging off the LEFT cliff
-- edge, Lone Wolf up-right). Talking to Wolf swaps Mog for a Gold Hairpin.
--
-- Presses face+A from each column tile, LEFT-facing first. $02FA is set
-- when Mog is taken. Saves wob_mog_done.mss.
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mogIn()
  return (H.readByte(0x1850 + 10) & 0x07) ~= 0 or sw(0x2FA) == 1
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
-- face `dir` (short tap, below the step threshold), press A, ride any
-- dialog A-only
local function tryTake(x, y, dir, tag)
  return H.cond(function() return not mogIn() end, flatten({
    H.navTo(x, y, { maxFrames = 4000, playBattles = "flee" }),
    H.waitFrames(20),
    H.hold({ dir }), H.waitFrames(2), H.release(), H.waitFrames(10),
    (function()
      local t = 0
      return H.driveUntil(function()
        return mogIn() or t >= 900
      end, 1500, {
        H.call(function()
          t = t + 1
          if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
          elseif t < 60 then H.setPad(t % 12 < 4 and { "a" } or {})
          else H.setPad({}) end
        end),
      }, tag)
    end)(),
    H.waitFrames(30),
    H.call(function()
      H.log(string.format("[%s] mogIn=%s $2FA=%d at (%d,%d)", tag,
        tostring(mogIn()), sw(0x2FA), H.fieldX(), H.fieldY()))
    end),
  }), {})
end
H.run({ maxFrames = 60000 }, flatten({
  H.loadState("build/states/wob_kupo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("boot: map %d (%d,%d) $023F=%d $0640=%d",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), sw(0x23F),
      (H.readByte(0x1E80 + (0x640 >> 3)) >> (0x640 & 7)) & 1))
    H.screenshot("take_boot")
  end),
  -- Mog hangs at ~(4-5,16); the ledge west of the column can't be
  -- bfs-pathed, so burst left along each row, then press A.
  (function()
    local out = {}
    for _, y in ipairs({ 16, 15, 17, 14 }) do
      out[#out+1] = H.cond(function() return not mogIn() end, flatten({
        H.navTo(8, y, { maxFrames = 4000, playBattles = "flee" }),
        (function()
          local t, x0 = 0, nil
          return H.driveUntil(function()
            if x0 == nil then x0 = H.fieldX() end
            return t >= 1500 or mogIn()
          end, 2500, {
            H.call(function()
              t = t + 1
              if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
              else H.setPad({ left = true }) end
            end),
          }, "west burst y" .. y)
        end)(),
        H.release(), H.waitFrames(30),
        H.call(function()
          H.log(string.format("[west y%d] reached (%d,%d)", y,
            H.fieldX(), H.fieldY()))
          H.screenshot("west_y" .. y)
        end),
        -- press A facing left, then down, then up from wherever we are
        (function()
          local seq = {}
          for _, dir in ipairs({ "left", "down", "up" }) do
            seq[#seq+1] = H.cond(function() return not mogIn() end, flatten({
              H.hold({ dir }), H.waitFrames(2), H.release(), H.waitFrames(10),
              (function()
                local t = 0
                return H.driveUntil(function()
                  return mogIn() or t >= 600
                end, 1200, {
                  H.call(function()
                    t = t + 1
                    if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
                    elseif t < 60 then H.setPad(t % 12 < 4 and { "a" } or {})
                    else H.setPad({}) end
                  end),
                }, "press " .. dir .. " y" .. y)
              end)(),
              H.waitFrames(20),
            }), {})
          end
          return flatten(seq)
        end)(),
      }), {})
    end
    return flatten(out)
  end)(),
  H.call(function()
    if not mogIn() then
      H.screenshot("take_stuck")
      error("no take press reached Mog -- see take_stuck")
    end
  end),
  -- ride out the join scene: dialogs A-tapped, the naming menu
  -- ($0059~=0) committed with START, until the party has control again
  (function()
    local t, calm, named = 0, 0, false
    return H.driveUntil(function()
      if H.dialogWaiting() or not H.hasControl()
        or H.readByte(0x0059) ~= 0 then calm = 0; return false end
      calm = calm + 1
      return calm >= 240
    end, 30000, {
      H.call(function()
        t = t + 1
        if H.readByte(0x0059) ~= 0 then
          if not named then
            named = true
            H.log(string.format("naming menu up ($0059=%02X) -- START",
              H.readByte(0x0059)))
          end
          H.setPad(t % 8 == 0 and { "start" } or {})
        elseif H.dialogWaiting() then
          H.setPad(t % 16 < 4 and { "a" } or {})
        elseif not H.hasControl() then
          H.setPad(t % 8 < 4 and { "a" } or {})
        else
          H.setPad({})
        end
      end),
    }, "the join scene settles")
  end)(),
  H.call(function()
    H.log(string.format("MOG RECRUITED: party byte=%02X $2FA=%d",
      H.readByte(0x1850 + 10), sw(0x2FA)))
    H.screenshot("mog_joined")
  end),
  H.saveState("wob_mog_done.mss"),
  H.logStep(function() return "done" end),
}))

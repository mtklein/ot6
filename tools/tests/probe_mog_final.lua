-- probe_mog_final.lua -- the full WoB Mog recruit (#133 item 3, closes
-- the #134 mystery: the cliff opens behind a press-A secret).
--
-- The missing link was never a missing path: map 20's trigger (15,57)
-- (_ccb133) is a press-A-at-the-cracked-wall secret.  $01B4/$01B0 are
-- not story switches -- UpdateCtrlFlags (field/event.asm:5416) writes
-- the LIVE PAD into $1EB6: bit4 = A held, low nibble = facing.  Stand
-- on (15,57) facing up with A held (plus $0020=1/$006B=1/$0076=1, all
-- true in the routed chain) and the wall at (14,54) blasts open
-- ($01F0=1; map 20's init re-applies the mod forever after).  Behind it
-- the always-present door record (15,56) -> map 41 (7,33) leads to the
-- REAL northern mine -- the walkthrough's route: north mine, the wooden
-- bridge over town (map 42), a short mine, the cliffs.
--
-- Full sequence (chase first so the cliff triggers are armed):
--   treasure room intro [$0239] -> town rows [$023A,$023B] ->
--   map 21 "Persistent!" [$023C] -> back to town ->
--   the cracked wall (15,57) -> 41 (7,33) -> explore NE (goal-checked)
--   across the bridge to 41's (107/117,12) doors -> 21 top pocket ->
--   22 -> 23 -> standoff [$023D] -> ledge [$023F] -> MOG at (9,16),
--   talked from (9,17) with the choice-menu-safe A-only ride.
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
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
local function stage(x, y, pred, tag, opts)
  opts = opts or {}
  local aPhase, calm = 0, 0
  return {
    H.navTo(x, y, { maxFrames = opts.maxFrames or 9000,
      playBattles = "flee", arrive = pred }),
    H.driveUntil(function()
      if not pred() then calm = 0; return false end
      return calm >= 60
    end, 6000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then
          calm = 0
          H.setPad(aPhase < 4 and { "a" } or {})
        else
          if pred() and H.hasControl() then calm = calm + 1 end
          H.setPad({})
        end
      end),
    }, tag),
  }
end
local function edge(cands, dir, destMap, tag)
  local tile = nil
  return {
    H.call(function()
      for _, c in ipairs(cands) do
        if H.bfsPath(c[1], c[2]) or (H.fieldX()==c[1] and H.fieldY()==c[2]) then
          tile = c
          H.log(string.format("[%s] approach (%d,%d)", tag, c[1], c[2]))
          return
        end
      end
      error(tag .. ": no reachable approach")
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 12000, playBattles = "flee",
        arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1500,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[%s] now map %d (%d,%d)", tag,
        H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    end),
  }
end

H.run({ maxFrames = 120000 }, flatten({
  H.loadState("build/states/wob_narshe_town.mss.lua"),
  H.waitFrames(8),
  -- the chase, all proven stages
  edge({{52,38}}, "up", 30, "into the treasure room"),
  stage(79, 17, function() return sw(0x239) == 1 end, "Lone Wolf intro [$0239]",
    { maxFrames = 4000 }),
  edge({{79,17},{79,18}}, "down", 20, "back to town"),
  stage(49, 37, function() return sw(0x23A) == 1 end, "chase [$023A]"),
  stage(38, 20, function() return sw(0x23B) == 1 end, "chase [$023B]"),
  edge({{36,2},{35,2},{37,2},{38,2}}, "up", 21, "north to 21"),
  stage(31, 22, function() return sw(0x23C) == 1 end, "chase [$023C]"),
  edge({{24,52},{25,52},{26,52},{23,52}}, "down", 20, "back to town again"),
  -- THE CRACKED WALL: stand (15,57), face up, hold A until the shake
  H.navTo(15, 57, { maxFrames = 12000, playBattles = "flee" }),
  H.driveUntil(function() return sw(0x1F0) == 1 end, 900, {
    H.call(function() H.setPad({ up = true, a = true }) end),
  }, "the wall opens [$01F0]"),
  H.release(), H.waitFrames(60),
  H.call(function()
    H.log("WALL OPEN -- entering the northern mine")
    H.screenshot("wall_open")
  end),
  -- through the new mouth: door (15,56) -> 41 (7,33)
  H.driveUntil(function() return mapIs(41) end, 1500, {
    H.call(function() H.setPad({ up = true }) end),
  }, "into the northern mine (41)"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("in 41 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- explore toward the top doors; long pushes (the climb tiles need
  -- ~200f holds); goal-check every round
  (function()
    local out = {}
    local used = {}
    local function round(r)
      local tile = nil
      return H.cond(function() return mapIs(41) or mapIs(42) end, flatten({
        H.call(function()
          local m = H.mapId() & 0x1ff
          if m == 41 then
            for _, c in ipairs({ {107,12},{106,12},{107,13},{108,12},
                                 {117,12},{116,12},{117,13},{118,12} }) do
              if H.bfsPath(c[1], c[2]) then
                tile = c
                H.log(string.format("[nmine r%d] TOP door (%d,%d)!", r, c[1], c[2]))
                return
              end
            end
          end
          local DOORS = {
            [41] = { {41,5},{42,5},{40,5},{43,5},{44,5},{39,5},
                     {42,9},{43,9},{41,9},{42,10},
                     {57,11},{57,21},{25,59},{18,51} },
            [42] = { {86,29},{86,30},{85,29},{87,29},{87,13},{86,13} },
          }
          for _, c in ipairs(DOORS[H.mapId() & 0x1ff] or {}) do
            local key = (H.mapId() & 0x1ff) .. ":" .. c[1] .. "," .. c[2]
            if not used[key] and H.bfsPath(c[1], c[2]) then
              used[key] = true
              tile = c
              H.log(string.format("[nmine r%d] door (%d,%d) on map %d", r,
                c[1], c[2], H.mapId() & 0x1ff))
              return
            end
          end
          for yy = 0, 62, 3 do
            local row = {}
            for xx = 0, 126, 3 do
              row[#row+1] = H.bfsPath(xx, yy) and "O" or "."
            end
            H.log("  chart y" .. yy .. " " .. table.concat(row))
          end
          error(string.format("nmine r%d: nothing new from map %d (%d,%d)",
            r, H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
        end),
        H.cond(function() return tile ~= nil end, {
          (function()
            local px, py, sm, jumped = nil, nil, nil, false
            return H.navTo(function() return tile[1] end,
                           function() return tile[2] end,
              { maxFrames = 12000, playBattles = "flee",
                arrive = function()
                  local x, y = H.fieldX(), H.fieldY()
                  if sm == nil then sm = H.mapId() & 0x1ff end
                  if (H.mapId() & 0x1ff) ~= sm then return true end
                  -- a real door teleport moves >=4 tiles in one frame;
                  -- an ordinary walk never does
                  if px ~= nil and math.abs(x - px) + math.abs(y - py) >= 4 then
                    jumped = true
                  end
                  px, py = x, y
                  return jumped
                end })
          end)(),
          H.waitFrames(40),
          -- long push in case the target is a row/climb one step past
          (function()
            local m0, x0, y0, pt, pi = nil, nil, nil, 0, 1
            local pushes = { "up", "left", "right", "down" }
            return H.driveUntil(function()
              if m0 == nil then m0, x0, y0 = H.mapId() & 0x1ff, H.fieldX(), H.fieldY() end
              return (H.mapId() & 0x1ff) ~= m0
                or math.abs(H.fieldX()-x0)+math.abs(H.fieldY()-y0) > 10
                or pi > #pushes
            end, 1400, {
              H.call(function()
                pt = pt + 1
                if pt % 300 == 0 then pi = pi + 1 end
                H.setPad(pushes[pi] and { [pushes[pi]] = true } or {})
              end),
            }, "nmine push r" .. r)
          end)(),
          H.waitFrames(40),
          H.call(function()
            H.log(string.format("[nmine r%d] now map %d (%d,%d)", r,
              H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
          end),
        }, {}),
      }), {})
    end
    for r = 1, 10 do out[#out+1] = round(r) end
    return out
  end)(),
  -- take the TOP door if we're parked next to it on 41
  H.cond(function() return mapIs(41) end, flatten({
    edge({{107,12},{108,12},{117,12},{116,12},{107,13},{117,13}},
      "up", 21, "41 -> 21 top pocket"),
  }), {}),
  -- 21 top -> 22 -> 23
  H.cond(function() return mapIs(21) end, flatten({
    edge({{35,2},{34,2},{36,2},{37,2},{35,3},{34,3}}, "up", 22, "21 -> 22"),
  }), {}),
  H.cond(function() return mapIs(22) end, flatten({
    edge({{19,2},{18,2},{20,2},{21,2},{19,3},{18,3}}, "up", 23, "22 -> 23"),
  }), {}),
  H.call(function()
    H.assertEq(mapIs(23), true, "reached the cliffs (map 23)")
    H.screenshot("cliffs")
  end),
  stage(22, 20, function() return sw(0x23D) == 1 end, "the standoff [$023D]"),
  stage(8, 18, function() return sw(0x23F) == 1 end, "the ledge [$023F]"),
  H.navTo(9, 17, { maxFrames = 6000, playBattles = "flee" }),
  (function()
    local t, talked = 0, false
    return H.driveUntil(function() return mogIn() end, 9000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then talked = true end
        if talked then
          H.setPad(t % 24 < 3 and { "a" } or {})
        else
          H.setPad(t % 30 < 3 and { up = true, a = true } or { up = true })
        end
      end),
    }, "MOG joins")
  end)(),
  H.call(function()
    H.log("MOG RECRUITED")
    H.screenshot("mog_joined")
  end),
  H.saveState("wob_mog_done.mss"),
  H.logStep(function() return "done" end),
}))

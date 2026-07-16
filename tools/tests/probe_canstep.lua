-- probe_canstep: validate the CheckPlayerMove port (H.canStep) against
-- the engine itself before anything depends on it.  Boot the injected save
-- (Narshe mines, party at rest), render the model's view of the 15x15
-- neighborhood as ASCII (flood fill over canStep edges: party @, reachable
-- ., unreachable #), then for each cardinal direction: predict canStep,
-- actually press it (adaptive hold -- release the instant the tile coord
-- changes), and compare prediction against observed movement.  Two rounds
-- of all four directions; steps back after each move (best effort).  Random
-- encounters are cleared between samples and void a sample they interrupt.
-- PASS iff zero mismatches and at least 6 of 8 samples landed.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

local OPP = { up = "down", down = "up", left = "right", right = "left" }
local DEL = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }
local results = {}

-- one adaptive single-tile step: hold btn until the tile coord changes
-- (blocked ~30 frames = give up), release, settle to tile-alignment.
local function adaptiveStep(btn, tag)
  local hx, hy, held
  return {
    H.call(function() hx, hy = H.fieldX(), H.fieldY(); held = 0 end),
    H.driveUntil(function()
      if H.battleLoadStarted() then return true end
      if H.fieldX() ~= hx or H.fieldY() ~= hy then return true end
      held = held + 1
      return held > 30
    end, 120, { H.hold({ btn }) }, "hold " .. tag),
    H.release(),
    H.waitUntilSoft(function()
      return H.battleLoadStarted() or H.tileAligned()
    end, 120, "align_" .. tag, 2),
  }
end

local function append(list, steps)
  for _, s in ipairs(steps) do list[#list + 1] = s end
end

-- wait for control at rest on a tile, clearing any encounter that fires
-- meanwhile (a plain waitUntil starves if the battle only BEGINS loading
-- after a battle-check step already passed)
local function settleStep(tag)
  local aPhase = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned()
  end, 4000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2,
                          H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPhase < 4 and { "a" } or {})
      else
        H.setPad({})
      end
    end),
  }, "settle " .. tag)
end

local function testDir(btn, round)
  local px, py, pred
  local steps = {
    settleStep("before " .. btn .. round),
    H.call(function()
      px, py = H.fieldX(), H.fieldY()
      pred = H.canStep(px, py, btn)
    end),
  }
  append(steps, adaptiveStep(btn, btn .. round))
  steps[#steps + 1] = H.call(function()
    if H.battleLoadStarted() then
      results[#results + 1] = { btn = btn, skip = true }
      H.log(string.format("  r%d %-5s: encounter interrupted, sample void",
        round, btn))
      return
    end
    local moved = (H.fieldX() ~= px or H.fieldY() ~= py)
    results[#results + 1] = { btn = btn, pred = pred, moved = moved }
    H.log(string.format("  r%d canStep(%d,%d,%-5s)=%-5s moved=%-5s %s",
      round, px, py, btn, tostring(pred), tostring(moved),
      pred == moved and "MATCH" or "MISMATCH"))
  end)
  -- best-effort restore so both rounds sample the same tile
  append(steps, {
    H.cond(function()
      return not H.battleLoadStarted() and H.hasControl()
         and (H.fieldX() ~= px or H.fieldY() ~= py)
    end, adaptiveStep(OPP[btn], "back" .. round), {}),
  })
  return steps
end

local steps = {
  -- boot preamble (the SRM-inject Continue dance, verbatim from gen_whelk)
  H.waitFrames(5),
  H.call(function()
    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.hasControl() end, 2000, "field control", 10),

  -- flag telemetry + the model's-eye view of the neighborhood
  H.call(function()
    local px, py = H.fieldX(), H.fieldY()
    H.log(string.format(
      "start (%d,%d) map=%d z$B2=%02X mv$087C=%02X evPC=%02X%02X%02X dlg=%s",
      px, py, H.mapId(), H.readByte(0x00b2), H.readByte(0x087c),
      H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
      tostring(H.dialogWaiting())))
    local open = { [py * 256 + px] = true }
    local q, qi = { { px, py } }, 1
    while qi <= #q do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for dir, d in pairs(DEL) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= px - 7 and nx <= px + 7 and ny >= py - 7 and ny <= py + 7
           and not open[ny * 256 + nx] and H.canStep(x, y, dir) then
          open[ny * 256 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
    for y = py - 7, py + 7 do
      local row = {}
      for x = px - 7, px + 7 do
        row[#row + 1] = (x == px and y == py) and "@"
          or (open[y * 256 + x] and "." or "#")
      end
      H.log(string.format("map Y=%3d %s", y, table.concat(row)))
    end
  end),
}

for round = 1, 2 do
  for _, btn in ipairs({ "up", "right", "down", "left" }) do
    append(steps, testDir(btn, round))
  end
end

-- negative sample: hug the west wall (one step left of the boot area the
-- next left is a wall on both plausible end rows) and confirm a press the
-- model calls BLOCKED really doesn't move the party
append(steps, { settleStep("before wallwalk") })
append(steps, adaptiveStep("left", "wallwalk"))
append(steps, testDir("left", 3))

steps[#steps + 1] = H.call(function()
  local tested, mism, negs = 0, 0, 0
  for _, r in ipairs(results) do
    if not r.skip then
      tested = tested + 1
      if r.pred ~= r.moved then mism = mism + 1 end
      if not r.pred then negs = negs + 1 end
    end
  end
  H.log(string.format(
    "canstep validation: %d/%d samples, %d mismatches, %d negative",
    tested, #results, mism, negs))
  H.assertEq(mism, 0, "canStep matches observed movement")
  H.assertEq(tested >= 6, true, "enough samples survived the encounters")
end)

H.run({ maxFrames = 8000 }, steps)

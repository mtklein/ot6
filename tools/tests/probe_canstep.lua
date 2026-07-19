-- probe_canstep: validate the movement model (H.canStep) against the engine
-- itself before anything depends on it.  TWO parts, because
-- UpdatePlayerMovement has two branches and the model ports both:
--
-- PART 1 -- CARDINAL (player.asm:456 -> CheckPlayerMove).  Boot the injected
-- save (Narshe mines, party at rest), render the model's view of the 15x15
-- neighborhood as ASCII (flood fill over canStep edges: party @, reachable
-- ., unreachable #), then for each cardinal direction: predict canStep,
-- actually press it (adaptive hold -- release the instant the tile coord
-- changes), and compare prediction against observed movement.  Two rounds
-- of all four directions; steps back after each move (best effort).  Random
-- encounters are cleared between samples and void a sample they interrupt.
--
-- PART 2 -- DIAGONAL (player.asm:379).  On a tile whose prop byte has $c0
-- set, a LEFT or RIGHT press moves the party diagonally; Figaro Castle's
-- staircases are built from those tiles, and before the model knew the
-- branch they read as solid wall (map 55 split into three regions BFS could
-- not join, and gen_edgar hand-held four staircases with pushUntil).  So:
-- boot figaro_matron.mss, walk to the foot of the matron's own staircase,
-- and at each of its tiles press ALL FOUR directions, comparing the exact
-- displacement the model predicts against the exact displacement the engine
-- produces.  That covers the three cases the branch can produce -- a
-- diagonal, the cardinal fallback when the diagonal destination is refused,
-- and no movement at all -- and the run asserts at least one of each.
--
-- PASS iff zero mismatches in either part, at least 6 of 8 part-1 samples
-- landed, and part 2 saw a real diagonal, a real fallback and a real refusal.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"
local MATRON = "/Users/mtklein/ot6/build/states/figaro_matron.mss.lua"

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

-- ===================================================================== --
-- PART 2: the diagonal branch, on Figaro's own staircases.
-- ===================================================================== --

-- every move the model can plan, and the displacement each one means
local MOVEDEL = {
  up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
  upright = { 1, -1 }, downright = { 1, 1 },
  downleft = { -1, 1 }, upleft = { -1, -1 },
}
local ALLMOVES = { "up", "right", "down", "left",
                   "upright", "downright", "downleft", "upleft" }

local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end

-- The matron's staircase, measured from figaro_matron.mss: (66,26) carries
-- prop $83 and (65,25)/(64,24) carry $8b -- all bit7, i.e. "\" tiles, so a
-- LEFT press climbs them up-left and a RIGHT press descends down-right.
-- (67,26) is the plain $02 floor tile at the foot, included so the sweep
-- also samples a NON-diagonal tile on the same map.
local STAIR = { { 67, 26 }, { 66, 26 }, { 65, 25 }, { 64, 24 } }
local dresults = { diag = 0, fallback = 0, refused = 0, mism = 0, n = 0 }

-- one predict-then-press trial: work out what the model says the press does
-- BEFORE touching anything (a press changes both the party position and the
-- object map, so a prediction computed afterwards is measuring a different
-- world -- that mistake made a first draft of this probe report a bogus
-- mismatch), then hold the button and compare exact displacements.
local function diagTrial(x, y, btn)
  local pred, px, py, held
  return H.cond(function() return true end, {
    H.call(function()
      px, py = H.fieldX(), H.fieldY()
      held = 0
      pred = nil
      for _, m in ipairs(ALLMOVES) do
        if H.movePress(m) == btn and H.canStep(px, py, m) then pred = m end
      end
    end),
    -- a refused press is a RESULT here, not a timeout: hold the adaptive
    -- 45 frames (well past the ~16 a real step takes) and let "never moved"
    -- be the observation
    H.driveUntil(function()
      held = held + 1
      return H.fieldX() ~= px or H.fieldY() ~= py or held > 45
    end, 90, { H.hold({ btn }) }, string.format("press %s at (%d,%d)", btn, x, y)),
    H.release(),
    H.waitUntilSoft(function() return H.tileAligned() end, 120, "diagalign", 2),
    H.call(function()
      local dx, dy = H.fieldX() - px, H.fieldY() - py
      local wx, wy = 0, 0
      if pred then wx, wy = MOVEDEL[pred][1], MOVEDEL[pred][2] end
      local ok = dx == wx and dy == wy
      dresults.n = dresults.n + 1
      if not ok then dresults.mism = dresults.mism + 1 end
      if pred == nil then dresults.refused = dresults.refused + 1
      elseif H.movePress(pred) ~= pred then dresults.diag = dresults.diag + 1
      elseif (prop(px, py) & 0xC0) ~= 0 and (btn == "left" or btn == "right")
        then dresults.fallback = dresults.fallback + 1 end
      H.log(string.format(
        "  (%2d,%2d) p1=%02X press %-5s -> model %-9s (%+d,%+d) | engine (%+d,%+d) | %s",
        px, py, prop(px, py), btn, pred or "(none)", wx, wy, dx, dy,
        ok and "MATCH" or "MISMATCH"))
    end),
  }, {})
end

local dsteps = {
  H.loadState(MATRON),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "matron control", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1FF, 57, "booted the matron's room (map 57)")
    H.log(string.format("part 2: map=%d (%d,%d) $86=%02X $87=%02X z$B2=%02X",
      H.mapId() & 0x1FF, H.fieldX(), H.fieldY(),
      H.readByte(0x0086), H.readByte(0x0087), H.readByte(0x00b2)))
    -- the model's-eye view, now including diagonal edges
    local px, py = H.fieldX(), H.fieldY()
    local open = { [py * 256 + px] = true }
    local q, qi = { { px, py } }, 1
    while qi <= #q do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, m in ipairs(ALLMOVES) do
        local d = MOVEDEL[m]
        local nx, ny = x + d[1], y + d[2]
        if nx >= px - 10 and nx <= px + 10 and ny >= py - 7 and ny <= py + 7
           and not open[ny * 256 + nx] and H.canStep(x, y, m) then
          open[ny * 256 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
    for y = py - 7, py + 7 do
      local row = {}
      for x = px - 10, px + 10 do
        row[#row + 1] = (x == px and y == py) and "@"
          or (open[y * 256 + x] and "." or "#")
      end
      H.log(string.format("map Y=%3d %s", y, table.concat(row, "")))
    end
  end),

  -- THE connectivity claim: (67,27) is where the west-ring door D13 drops
  -- the party, and from there the matron used to be unreachable -- her room
  -- "flooded to FOUR tiles" and gen_edgar needed three pushUntil hand-holds
  -- to cross the staircase.  BFS must now find her on its own.
  H.navTo(67, 27, { maxFrames = 6000 }),
  -- settle before reading the object map: the party's marker at $7e2000 is
  -- written by CheckPlayerMove as the step BEGINS (player.asm:1176-1189) and
  -- the tile just vacated is only released a few frames later, so a BFS run
  -- the instant navTo's predicate fires sees the party's own stale marker
  -- one tile back and calls the whole return path blocked (measured: this
  -- assertion failed with no wait and passes with one).
  H.waitFrames(30),
  H.call(function()
    local plan = H.bfsPath(59, 22)     -- the tile below the matron's NPC
    H.assertEq(plan ~= nil, true,
      "BFS reaches the matron from the door tile (67,27) with no hand-holds")
    local diag = 0
    for _, m in ipairs(plan) do
      if H.movePress(m) ~= m then diag = diag + 1 end
    end
    H.log(string.format(
      "BFS (67,27)->(59,22): %d steps, %d of them diagonal [%s]",
      #plan, diag, table.concat(plan, " ")))
    H.assertEq(diag > 0, true, "the plan actually uses the staircase")
  end),
}

-- sweep the staircase: at each tile, all four presses, restoring position
-- between trials with navTo (which the fix is what makes possible)
for _, t in ipairs(STAIR) do
  dsteps[#dsteps + 1] = H.navTo(t[1], t[2], { maxFrames = 4000 })
  dsteps[#dsteps + 1] = H.logStep(string.format(
    "stair tile (%d,%d):", t[1], t[2]))
  for _, btn in ipairs({ "up", "right", "down", "left" }) do
    dsteps[#dsteps + 1] = diagTrial(t[1], t[2], btn)
    dsteps[#dsteps + 1] = H.navTo(t[1], t[2], { maxFrames = 4000 })
  end
end

dsteps[#dsteps + 1] = H.call(function()
  H.log(string.format(
    "diagonal validation: %d trials, %d mismatches (%d diagonal, %d cardinal " ..
    "fallback, %d refused)", dresults.n, dresults.mism, dresults.diag,
    dresults.fallback, dresults.refused))
  H.assertEq(dresults.mism, 0, "canStep matches observed movement (diagonal)")
  -- A quiet probe is not a passing probe: assert the sweep actually
  -- exercised all three outcomes of the branch, not just the easy one.
  H.assertEq(dresults.diag > 0, true, "sweep produced a real diagonal move")
  H.assertEq(dresults.fallback > 0, true,
    "sweep produced a diagonal-refused -> cardinal fallback")
  H.assertEq(dresults.refused > 0, true, "sweep produced a refused press")
end)

for _, s in ipairs(dsteps) do steps[#steps + 1] = s end

H.run({ maxFrames = 30000 }, steps)

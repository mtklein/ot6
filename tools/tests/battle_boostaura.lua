-- @suite savestate=kolts_cave
-- battle_boostaura: a pending boost shows as an aura on the boosting
-- character (#445, ot6_aura.asm), growing with the boost, through an open
-- list and the boosted action, and gone once the charge lands.
--
-- The aura is two things, both measured here from what the PPU is given:
--   * the glow: the character's sprite palette (obj palette 4 + slot) has its
--     outline colour (colour 1) replaced from Ot6AuraOutline's row for the
--     level, stepping through the row (the pulse);
--   * the halo: copies of the character's two body sprites (tiles slot*4 +
--     0/2, palette 4 + slot): at most 4/6/9 at 1/2/3 BP (Ot6HaloTopN +
--     Ot6HaloBotN), fewer where the battle's other sprites crowd the
--     booster's scanlines.  How many is not a constant: Ot6AuraHalo grants
--     copies against a per-16-line-band sliver budget (fullest band + 2n <=
--     34; lines from $97 down are left alone), so what a frame owes depends
--     on the draw (which monsters, where they stand, who is in the party).
--     This suite computes the owed count from that frame's own OAM by the
--     rule (expectedCopies), asserts the frame has exactly that many, and
--     that the copies never take a line above $97 past 34 slivers;
--     battle_auraband is the mechanism test that crowds the lines on
--     purpose.
-- With no boost pending both are absent: two body sprites, and colour 1 is
-- the character's unaltered colour (w7e81ad, the copy UpdateCharPal restores
-- from).
--
-- A real fight: a kolts_cave encounter, the first character whose menu opens
-- banks 3 BP by Defending (right, A), raises the boost with R, opens a list,
-- then Fights with it.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local OAM, CG = emu.memType.snesSpriteRam, emu.memType.snesCgRam
local PRISTINE = 0x7E81AD                  -- w7e81ad: unaltered char palettes
local FLOOR = 0x97                      -- the budget stops here (FF6 overflows lines below it on purpose)
local TOPN, BOTN = { 2, 3, 6 }, { 2, 3, 3 } -- Ot6HaloTopN, Ot6HaloBotN: copies a half wants at 1/2/3 BP
local actor
local copiesSeen = 0                       -- halo copies seen over the run: the halo must show somewhere
local function pend(s) return H.readByte(0x3e9d + s * 2) end
local function bp(s) return H.readByte(0x3e9c + s * 2) end
local function map() return H.mapId() & 0x1ff end

-- body sprites of `slot` in the PPU's OAM, and the leftmost/rightmost x
local function bodies(slot)
  local n, xs = 0, {}
  for i = 0, 127 do
    local t, a = emu.read(i * 4 + 2, OAM), emu.read(i * 4 + 3, OAM)
    local y = emu.read(i * 4 + 1, OAM)
    if (t & 0xf0) == 0 and (t >> 2) == slot and (a & 0x0f) == 8 + slot * 2
        and y < 0xe0 then
      n = n + 1
      xs[#xs + 1] = emu.read(i * 4, OAM)
    end
  end
  return n, xs
end
local function colour1(slot) return emu.readWord(((12 + slot) * 16 + 1) * 2, CG) end
local function pristine1(slot) return H.readWord(PRISTINE + slot * 32 + 2) end
local function outlineRow(level)
  local base, row = H.sym("Ot6AuraOutline") & 0x3FFFFF, {}
  for i = 0, 4 do row[H.readRomWord(base + ((level - 1) * 5 + i) * 2)] = true end
  return row
end

-- ---- the budget rule, read off the frame's own OAM ----------------------
-- (ot6_aura.asm, Ot6AuraHalo / Ot6HaloHalf.)  The halo's character is the
-- only one boosting here.  Its bodies are the first OAM entry of tile
-- slot*4 and of slot*4+2 in the slot's palette; later entries of the same
-- tile and palette are its copies.  Every other entry that touches the
-- halo's rows (it starts above the window's end and its last row reaches the
-- window's start) puts its slivers (16x16: 2, 32x32: 4) into the 16-line
-- bands it touches (a small one a second band only when its y is off a band
-- edge, a large one a third); a half gets n copies while its fullest band +
-- 2n <= 34, and its copies' slivers join the bands before the next half.
local function oam()
  local e = {}
  for i = 0, 127 do
    e[i] = { x = emu.read(i * 4, OAM), y = emu.read(i * 4 + 1, OAM),
             t = emu.read(i * 4 + 2, OAM), a = emu.read(i * 4 + 3, OAM),
             hb = (emu.read(512 + (i >> 2), OAM) >> ((i & 3) * 2)) & 3 }
  end
  return e
end
local function split(e, slot)
  local top, bot, copy = nil, nil, {}
  for i = 0, 127 do
    local o = e[i]
    if (o.t & 0xf1) == 0 and (o.t >> 2) == slot and (o.a & 0x0f) == 8 + slot * 2 and o.y < 0xe0 then
      if (o.t & 2) == 0 and not top then top = i
      elseif (o.t & 2) ~= 0 and not bot then bot = i
      else copy[i] = true end
    end
  end
  return top, bot, copy
end
-- the copies a half owes (top, bottom) for `slot` at boost `level`, or nil
-- when the two bodies are not both in OAM
local function expectedCopies(e, slot, level)
  local top, bot, copy = split(e, slot)
  if not top or not bot then return nil end
  if level == 0 then return 0, 0 end
  local wlo = math.max(e[top].y - 2, 0)
  local whi = math.min(e[bot].y + 0x11, FLOOR)
  local hist = {}
  for b = 0, 15 do hist[b] = 0 end
  for i = 0, 127 do
    local o = e[i]
    if not copy[i] and o.y < whi then
      local large = (o.hb & 2) ~= 0
      if o.y + (large and 31 or 15) >= wlo then
        local b, sl = o.y >> 4, large and 4 or 2
        hist[b] = hist[b] + sl
        if large or (o.y & 15) ~= 0 then hist[b + 1] = hist[b + 1] + sl end
        if large and (o.y & 15) ~= 0 then hist[b + 2] = hist[b + 2] + sl end
      end
    end
  end
  local function half(lo, hi, nmax)
    if hi >= FLOOR then hi = FLOOR - 1 end
    local b0, b1 = lo >> 4, math.min(hi >> 4, 11)
    local full = 0
    for b = b0, b1 do full = math.max(full, hist[b]) end
    local n = math.min(nmax, math.max(34 - full, 0) // 2)
    for b = b0, b1 do hist[b] = hist[b] + 2 * n end
    return n
  end
  local nt = half(wlo, wlo + 0x11, TOPN[level])
  local nb = half(e[bot].y, e[bot].y + 0x10, BOTN[level])
  return nt, nb
end
-- slivers on each line above the floor (16x16 / 32x32, x clipped to the
-- screen: the PPU's own count), all entries and without `slot`'s copies
local function lineSlivers(e, copy)
  local all, own = {}, {}
  for l = 0, FLOOR - 1 do all[l], own[l] = 0, 0 end
  for i = 0, 127 do
    local o = e[i]
    local x = o.x - ((o.hb & 1) ~= 0 and 256 or 0)
    local w = (o.hb & 2) ~= 0 and 32 or 16
    if x > -w and x < 256 then
      local sl = (math.min(x + w, 256) - math.max(x, 0) + 7) // 8
      for dy = 0, w - 1 do
        local l = (o.y + dy) & 0xff
        if l < FLOOR then
          all[l] = all[l] + sl
          if not copy[i] then own[l] = own[l] + sl end
        end
      end
    end
  end
  return all, own
end
-- one frame: the actor's body+copy count, what the rule owes, and whether
-- the copies kept every line above the floor inside the PPU's 34 slivers
-- (a line the other sprites alone overfill is theirs, not the halo's)
local function snap()
  local e = oam()
  local level = pend(actor)
  local nt, nb = expectedCopies(e, actor, level)
  local top, bot, copy = split(e, actor)
  local n = (top and 1 or 0) + (bot and 1 or 0)
  local ncopy = 0
  for _ in pairs(copy) do ncopy = ncopy + 1 end
  local all, own = lineSlivers(e, copy)
  local worst, wl = 0, -1
  for l = 0, FLOOR - 1 do
    local over = all[l] - math.max(34, own[l])
    if over > worst then worst, wl = over, l end
  end
  return { n = n + ncopy, want = nt and (2 + nt + nb) or nil, level = level,
           over = worst, overLine = wl }
end

-- sample `n` frames; returns per-frame body counts and colour-1 values
local samples
local function sample(n)
  return H.repeatN(n, {
    H.call(function()
      local f = snap()
      samples[#samples + 1] = { n = f.n, want = f.want, over = f.over, overLine = f.overLine,
        c1 = colour1(actor), pend = pend(actor), bp = bp(actor) }
    end),
    H.waitFrames(1),
  })
end
local function startSample() return H.call(function() samples = {} end) end

-- press R until the pending boost reads `level`, as a player who sees the
-- press not take presses again.  Ot6Boost samples the held buttons once per
-- battle main-loop tick, and the main loop can stall for several frames
-- (an enemy's turn being worked out), so a single short press can fall
-- inside a stall and be missed: kolts_cave's regenerated fight did that to
-- a 6-frame press (qualification, v0.32 #445).  Each attempt is a 6-frame
-- hold and a 10-frame release; the boost is only ever raised one step.
local function raiseTo(level)
  local ph = 0
  return H.driveUntil(function() return pend(actor) == level end, 600, {
    H.call(function()
      if pend(actor) > level then
        error(string.format("R raised the boost past %d (now %d)", level, pend(actor)), 0)
      end
      H.setPad(ph % 16 < 6 and { r = true } or {})
      ph = ph + 1
    end),
  }, "R raises the boost to " .. level)
end

local function checkLevel(level, what)
  return H.call(function()
    local row, seen, distinct = nil, {}, 0
    local lo, hi, short = 99, 0, 0
    for k, s in ipairs(samples) do
      H.assertEq(s.pend, level, what .. ": pending boost held (frame " .. k .. ")")
      H.assertEq(s.want ~= nil, true, string.format("%s: both body sprites are in OAM (frame %d)", what, k))
      H.assertEq(s.n, s.want, string.format("%s: body sprites + halo copies at %d BP, as the scanline "
        .. "budget grants them from this frame's OAM (frame %d)", what, level, k))
      H.assertEq(s.over, 0, string.format("%s: the copies keep every line above $%02X inside 34 slivers "
        .. "(frame %d, line %d)", what, FLOOR, k, s.overLine))
      copiesSeen = copiesSeen + (s.n - 2)
      lo, hi = math.min(lo, s.n), math.max(hi, s.n)
      if s.want < 2 + TOPN[level] + BOTN[level] then short = short + 1 end
      row = row or outlineRow(level)
      if not row[s.c1] then
        error(string.format("%s: colour 1 $%04x is not on Ot6AuraOutline's %d BP row (frame %d)",
          what, s.c1, level, k), 0)
      end
      if not seen[s.c1] then seen[s.c1] = true; distinct = distinct + 1 end
    end
    if distinct < 2 then
      error(string.format("%s: the glow does not pulse at %d BP (one colour over %d frames)",
        what, level, #samples), 0)
    end
    H.log(string.format("[aura] %s: %d BP, %d..%d sprites (the budget granted exactly that every frame; "
      .. "%d of %d frames trimmed from the uncrowded %d), %d outline colours",
      what, level, lo, hi, short, #samples, 2 + TOPN[level] + BOTN[level], distinct))
  end)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),
  (function()
    local waited, lane = 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      if H.battleLoadStarted() then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
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
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  -- every menu that opens Defends (right, A) until the first character to
  -- open one holds 3 BP (1 at the open + 1 per unboosted action) with its
  -- command window up again
  (function()
    local ph = 0
    return H.driveUntil(function()
      if H.readByte(MENU) == 0 then return false end
      local a = H.readByte(ACTOR) & 3
      if actor == nil then actor = a; H.log("boosting slot " .. a) end
      return a == actor and bp(a) >= 3 and H.readByte(MSTATE) == 0x05
    end, 20000, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        else
          local step = ph % 40
          if step < 4 then H.setPad({ right = true })
          elseif step >= 20 and step < 24 then H.setPad({ a = true })
          else H.setPad({}) end
        end
      end),
    }, "the first actor banks 3 BP by Defending")
  end)(),
  H.release(),
  H.waitFrames(30),

  -- no boost: two body sprites, the unaltered outline colour
  startSample(), sample(32),
  H.call(function()
    local _, xs = bodies(actor)
    for _, x in ipairs(xs) do
      if x < 3 or x > 252 then error("precondition: the actor stands inside x 3..252 (x=" .. x .. ")", 0) end
    end
    for k, s in ipairs(samples) do
      H.assertEq(s.pend, 0, "no boost pending yet (frame " .. k .. ")")
      H.assertEq(s.n, 2, "no boost: the two body sprites only (frame " .. k .. ")")
      H.assertEq(s.c1, pristine1(actor), "no boost: colour 1 unaltered (frame " .. k
        .. "; a status glow on the actor would also move it)")
    end
    H.log(string.format("[aura] no boost: 2 sprites, colour 1 $%04x for %d frames",
      pristine1(actor), #samples))
  end),

  -- R, R, R: each level's aura, sampled over 32 frames (the 1-BP pulse is
  -- 32 frames, so every level shows at least two outline colours)
  raiseTo(1), H.waitFrames(12), startSample(), sample(32), checkLevel(1, "command window"),
  raiseTo(2), H.waitFrames(12), startSample(), sample(32), checkLevel(2, "command window"),
  raiseTo(3), H.waitFrames(12), startSample(), sample(32), checkLevel(3, "command window"),

  -- a list open: the second command's window (Magic, Steal, Tools...)
  H.pressButtons({ down = true }, 4), H.waitFrames(8),
  H.pressButtons({ a = true }, 4), H.waitFrames(30),
  H.call(function()
    local st = H.readByte(MSTATE)
    H.log(string.format("[aura] list open: menu state $%02x", st))
    if st == 0x05 then error("precondition: a list window opened over the command window", 0) end
  end),
  startSample(), sample(32), checkLevel(3, "list open"),
  H.pressButtons({ b = true }, 4), H.waitFrames(30),
  H.pressButtons({ up = true }, 4), H.waitFrames(8),

  -- Fight with the 3-BP boost: the aura holds through the action until the
  -- charge (bp drops by 3), then goes
  H.pressButtons({ a = true }, 4), H.waitFrames(20),
  H.pressButtons({ a = true }, 4),
  startSample(),
  H.driveUntil(function() return bp(actor) == 0 end, 1200, {
    H.call(function()
      local f = snap()
      samples[#samples + 1] = { n = f.n, want = f.want, over = f.over, overLine = f.overLine,
        c1 = colour1(actor), pend = pend(actor) }
    end),
  }, "the boosted Fight charges its 3 BP"),
  H.call(function()
    local held, exact, bad = 0, 0, nil
    for k, s in ipairs(samples) do
      if s.pend == 3 then
        held = held + 1
        if s.want ~= nil and s.n == s.want and s.over == 0 then exact = exact + 1
        else bad = bad or string.format("frame %d: %d sprites, the budget grants %s, %d slivers over on line %d",
          k, s.n, tostring(s.want), s.over or -1, s.overLine or -1) end
      end
    end
    H.log(string.format("[aura] boosted Fight: %d frames with 3 BP pending, %d of them with exactly the "
      .. "copies the budget grants", held, exact))
    if held < 30 then error(string.format("only %d frames with 3 BP pending in the boosted action", held), 0) end
    -- (a frame with an actor body out of OAM -- want nil -- is not a halo frame: the pose the
    -- engine draws in the middle of the swing; those are counted out, not forgiven)
    local scored = 0
    for _, s in ipairs(samples) do if s.pend == 3 and s.want ~= nil then scored = scored + 1 end end
    if scored < held // 2 then error(string.format("the action's frames mostly lack the body sprites (%d of %d)", scored, held), 0) end
    if exact < scored then
      error(string.format("the halo did not hold the budget through the boosted action (%d of %d frames; %s)",
        exact, scored, bad), 0)
    end
  end),
  H.waitFrames(8),
  startSample(), sample(16),
  H.call(function()
    for k, s in ipairs(samples) do
      H.assertEq(s.pend, 0, "the charge cleared the pending boost (frame " .. k .. ")")
      H.assertEq(s.n, 2, "after the charge: the halo is gone (frame " .. k .. ")")
      H.assertEq(s.c1, pristine1(actor), "after the charge: colour 1 restored (frame " .. k .. ")")
    end
    H.log("[aura] after the charge: 2 sprites, colour 1 restored")
  end),
  H.call(function()
    -- some frame of the run wore a halo: a build with no halo owes the same 2 sprites only
    -- where every line is crowded, and no draw crowds every level's lines for the whole run
    H.assertEq(copiesSeen > 0, true, "the halo shows: copies were drawn in some frame of the run")
    H.log(string.format("[aura] %d halo copies seen over the run's level frames", copiesSeen))
  end),
})

-- gen_mrf_chute.lua -- v0.6 leg 4: mrf_entry (MAGITEK FACTORY map 262,
-- {28,8}) -> the conveyor chute at {19,25} -> the factory's lower half,
-- control back at {10,45}.  Mints mrf_chute.
--
-- MAP 262 IS NOT ONE WALKABLE REGION, and the reason is scripted
-- transitions rather than a maze.  Measured live off the loaded tilemap
-- (probe_mrf262, booted on mrf_entry), from the landing tile {28,8}:
--
--   (19,23) door anim _cc7753      39 steps      (11,16) _cc7862   32 steps
--   (19,24) door anim _cc7735      40 steps      (11,17) _cc784a   33 steps
--   (19,25) THE CHUTE   _cc7771    41 steps      (11,21) _cc78a5   43 steps
--   (21,25) short chute _cc77ec    43 steps       (9,22) platform  44 steps
--   (11,45) _cc78d0    NO PATH     (10,54) _cc7682 NO PATH
--   (6,31)  _cc76a7    NO PATH     (21,27) _cc781b  NO PATH
--
-- So the recon's offline "only 130 tiles reachable" understated it -- the
-- upper floor is a single connected region containing both chutes, both
-- door-animation pairs and the east end of the platform gap -- but its
-- conclusion holds where it matters: everything below y~27 is unreachable
-- on foot and has to be entered through a script.
--
-- THE CHUTE.  event_trigger.asm's map-262 block puts _cc7771
-- (event_main.asm:94990) on {19,25}; unlike its neighbours {19,23}/{19,24}
-- (which are `if_switch $01B5=1, EventReturn`-latched door animations that
-- only run `mod_bg_tiles`), it is ungated and runs an obj_script that
-- carries SLOT_1 down and across:
--
--   {19,25} -> DOWN 5 -> {19,30} -> LEFT 4 -> {15,30} -> LEFT 1 -> {14,30}
--   -> DOWN_LEFT 3 -> {11,33} -> LEFT 1 -> {10,33} -> DOWN 8 -> {10,41}
--   -> DOWN 3 -> {10,44} -> jump_low DOWN 1 -> {10,45}
--
-- and ends `player_ctrl_on` at {10,45}, one tile west of the {11,45}
-- trigger _cc78d0 that the upper floor could not reach.  It is one-way:
-- the party is walked over non-walkable tiles with `layer 2`/`layer 3`.
--
-- Stepping onto {19,23} and {19,24} on the way in is harmless and expected
-- -- both are `mod_bg_tiles BG1/BG2 {19,24}` door frames guarded by the
-- once-per-tile latch $01B5 (which is $1EB6 bit 5, cleared by player.asm
-- :529-531 on every step, NOT a story switch -- see gen_vector_sneak.lua).
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hands off while a scene owns
-- it, edge-A through dialogs.  Used to walk INTO a trigger whose scene then
-- takes over -- the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- STOP TAPPING once we are where we were going.  The terminator
        -- wants 16 consecutive calm frames on the target, and an eager tap
        -- walks straight off it before the count gets there: the first
        -- version of this rode the chute correctly to (10,45) and then
        -- tapped itself to (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/mrf_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY", "booted in the MAGITEK FACTORY")
    H.assertEq(map(), 262, "booted on map 262")
    H.assertEq(H.fieldX(), 28, "boot x")
    H.assertEq(H.fieldY(), 8, "boot y")
    -- Positive control for the leg itself: the chute's landing zone must be
    -- unreachable on foot RIGHT NOW.  If it ever becomes reachable this
    -- generator is walking somewhere it thinks it is riding, and the
    -- assertion below that we ended at (10,45) would stop proving anything.
    H.assertEq(H.bfsPath(10, 45), nil,
      "CONTROL: (10,45) is NO-PATH on foot from the landing -- the chute "
      .. "is the only way down")
    H.log(partyReport("mrf_entry"))
  end),

  -- 1. across the upper floor to {19,22}, one tile above the door frames.
  H.navTo(19, 22, { maxFrames = 25000,
    arrive = function() return H.fieldY() >= 40 end }),
  H.navTo(19, 22, { maxFrames = 9000 }),   -- above the chute doors
  H.call(function()
    H.assertEq(H.fieldX(), 19, "above the chute x")
    H.assertEq(H.fieldY(), 22, "above the chute y")
    H.log(string.format("[chute] poised at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("mrf_chute_doorstep")
  end),

  -- 2. three tapped DOWN steps: {19,23} and {19,24} animate the door open,
  --    {19,25} is the chute and takes the party over.
  tapInto("down", function() return H.fieldX() == 10 and H.fieldY() == 45 end,
    16000, "DOWN through the door frames onto the chute -> (10,45)"),

  H.waitFrames(60),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY", "still in the MAGITEK FACTORY")
    H.assertEq(map(), 262, "still on map 262 -- the chute is intra-map")
    H.assertEq(H.fieldX(), 10, "chute exit x (obj_script move list)")
    H.assertEq(H.fieldY(), 45, "chute exit y")
    H.assertEq(sw(0x0069), 0, "$0069 still CLEAR")
    H.log(string.format("[mrf_chute] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("mrf_chute"))
    H.screenshot("mrf_chute")
  end),
  H.saveState("mrf_chute.mss"),

  -- 3. census of the lower half, to plan the next leg off measurement.
  H.call(function()
    census("mrf_chute", {
      { 11, 45, "_cc78d0" },
      { 22, 53, "the scripted 263 transition _cc7651" },
      { 22, 54, "its twin _cc765f" },
      { 10, 54, "_cc7682 lift down" },
      { 6, 31, "_cc76a7 lift up" },
      { 12, 60, "short entrance -> 263 (12,7)" },
      { 15, 60, "long entrance -> 263 (15,9)" },
      { 21, 27, "_cc781b" },
      { 4, 22, "platform hop west _cc76cc" },
      { 9, 22, "platform hop east _cc76f1" },
    })
  end),
  H.logStep(function()
    return string.format("mrf_chute minted at frame %d -- map 262 (10,45), "
      .. "below the one-way chute", H.frame)
  end),
})

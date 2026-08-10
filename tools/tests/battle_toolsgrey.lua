-- @suite frontier=kolts_cave slow
-- battle_toolsgrey.lua -- v0.5 MP costs: the Tools window greys what Edgar
-- can't afford, the twin of battle_blitzgrey on the REAL tools window.
--
-- Same mechanism as Blitz (see battle_blitzgrey's header): Ot6AbilityGrey
-- (ot6.asm) compares each row's MP cost to the active caster's current MP
-- ($3c08,slot*2) and returns magic's $04/$00, which Ot6ToolRowDecorate OR's into
-- the column's $21 font byte -> $25 grey.  The tools decorator additionally lays
-- each column out [font][cost][name] so the one font command colors the price
-- and the name together; the just-landed price display had put the cost tile
-- ahead of the font, out of greying's reach.
--
-- ISSUE #75 CONVERSION -- the boundary is SPENT to, not written.  This file
-- used to install an all-Edgar party into the magitek intro fight, hand-write
-- the tool records, and PIN current MP to 8 -- which proved the grey follows
-- a poked number.  It now boots kolts_cave (real TERRA/LOCKE/EDGAR, real
-- bag: AutoCrossbow 4 / NoiseBlaster 6 / Bio Blaster 8, Ot6AbilityCostTbl
-- prices read from the ROM), fights real encounters, and drives the pool to
-- the affordability line WITH THE TOOLS THEMSELVES: Bio Blaster casts while
-- the pool is rich, one AutoCrossbow to finish, until current MP lands in
-- [4,7] -- Bio Blaster (8) unaffordable, AutoCrossbow (4) still affordable.
-- That is strictly stronger than the pin: it proves the CHARGE and the GREY
-- agree -- the very cell CalcAttackEffect debits is the cell the decorator
-- reads.  If a fight ends before the pool is down, the lane is paced to the
-- next natural encounter and the spend continues (MP writes back to the
-- field and loads again -- battle_naturalmp's proven path).
--
-- What is asserted (attribute = the odd byte of a name tile's tilemap word,
-- $21 white / $25 grey):
--   1. RICH POOL: every owned tool the pool can afford renders WHITE at the
--      first open -- the same rows that later grey, so the grey is proven
--      affordability-driven, not unconditional.
--   2. SPENT-TO BOUNDARY: with MP really spent into [4,7], Bio Blaster
--      renders GREY and AutoCrossbow WHITE on one screen; NoiseBlaster
--      follows its own line (white iff mp >= 6).
--   3. THE GREY IS THE DISABLED BIT.  grey - white == $04, magic's own delta.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_TGT = 0x05, 0x30, 0x38
local CMD_TOOLS = 0x09
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local EDGAR = 0x04
local WHITE, GREY = 0x21, 0x25
local BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW = 0xA4, 0xA3, 0xAA

local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- "Bio Blaster" spells its space as the narrow-space glyph $fe in item-name
-- records (battle_toolslist's finding); the other two are contiguous.
local function seqJoin(a, mid, b)
  local t = {}
  for _, v in ipairs(a) do t[#t + 1] = v end
  t[#t + 1] = mid
  for _, v in ipairs(b) do t[#t + 1] = v end
  return t
end
local NM = {
  [BIOBLASTER]   = { name = "Bio Blaster",
                     g = seqJoin(glyphs("Bio"), 0xfe, glyphs("Blaster")) },
  [NOISEBLASTER] = { name = "NoiseBlaster", g = glyphs("NoiseBlaster") },
  [AUTOCROSSBOW] = { name = "AutoCrossbow", g = glyphs("AutoCrossbow") },
}

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

local function map() return H.mapId() & 0x1ff end

local edgarSlot, edgarOfs = nil, nil
-- Edgar's live pool: the battle cell when a battle is up, else his field MP
-- (writeback keeps them one number -- battle_naturalmp phase 3).
local function pool()
  if H.battleLoadStarted() and edgarSlot then
    return H.readWord(0x3C08 + edgarSlot * 2)
  end
  return edgarOfs and H.readWord(0x160d + edgarOfs) or 0xFFFF
end

-- the spend plan, from the pool as read: park the pool in [4,7].
--   while mp >= 12: Bio Blaster (8) -- ends in [4,11]
--   then if mp >= 8: AutoCrossbow (4) -- [8,11] -> [4,7]
local function planCast(mp)
  if mp >= 12 then return BIOBLASTER end
  if mp >= 8 then return AUTOCROSSBOW end
  return nil
end

-- ------------------------------------------------------------------------
-- THE PER-FRAME MACHINE.  mode "spend": on Edgar's menu, walk the real
-- cursors to planCast's tool and confirm it; everyone else Defends (right
-- swaps Fight->Def, then A -- battle_naturalmp's consumption).  mode
-- "open": walk to the Tools list and HOLD it open (the assert window).
-- Off-battle: pace the detected lane until the next natural encounter.
-- ------------------------------------------------------------------------
local mode = "spend"
local ph, lane, hb = 0, nil, -600
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then           -- heartbeat: where is the machine?
    hb = H.frame
    H.log(string.format("[hb f%d] mode=%s pool=%d batt=%s menu=%02x actor=%d "
      .. "mstate=%02x map=%d", H.frame, mode, pool(),
      tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
      H.readByte(MSTATE), map()))
  end
  local edge = ph % 10 < 5              -- 5-on/5-off press edges
  if not H.battleLoadStarted() then
    -- field: pace the lane for the next encounter
    if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
    if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  if H.readByte(MENU) == 0 then
    -- no menu up: page any battle dialog with A -- measured on the first run
    -- of this conversion, the exact battle_vargas hazard: a monster's dialog
    -- blocked the whole queue for 20k+ frames of menu=00/mstate=00 with the
    -- fight otherwise alive and this machine's hands off.
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= edgarSlot then
    -- a bystander's window: real Defend (right, then A), slow cadence
    local step = ph % 40
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local st = H.readByte(MSTATE)
  local wantTool = (mode == "spend") and planCast(pool()) or AUTOCROSSBOW
  if mode == "spend" and wantTool == nil then
    -- pool already parked: hands off, the driver's predicate ends the phase
    H.setPad({})
    return
  end
  if st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_TOOLS then wantCell = i end
    end
    assert(wantCell, "EDGAR's real command list carries Tools")
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  elseif st == ST_TOOLS then
    if mode == "open" then H.setPad({}) return end   -- window up: hold it
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == wantTool then entry = i end
    end
    if entry == nil then H.setPad({}) return end     -- list still building
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else H.setPad(edge and { a = true } or {}) end
  elseif st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == 0x01 then
    H.setPad({})                        -- transitional: hands off
  else
    H.setPad(edge and { b = true } or {})
  end
end

-- drive until Edgar's Tools window is OPEN and settled (for the asserts)
local function openToolsWindow(what)
  return H.repeatN(1, {
    H.call(function() mode = "open" end),
    H.driveUntil(function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == edgarSlot and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),                   -- let every row finish drawing
  })
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function()
    H.assertEq(map(), 96, "kolts_cave on map 96")
    -- Edgar's field record: $1600 offsets via the character id, so the pool
    -- can be read before the first battle seeds slot indices.
    for c = 0, 15 do
      if H.readByte(0x1850 + c) & 0x07 ~= 0 and c == EDGAR then
        edgarOfs = 37 * c               -- $160d + 37*char (kolts party layout)
      end
    end
    -- $160d stride: the field record is 37 bytes from $1600; MP cur at +$0d.
    edgarOfs = 37 * EDGAR
    H.log(string.format("EDGAR field MP as saved: %d", H.readWord(0x160d + edgarOfs)))
    H.assertEq(H.readWord(0x160d + edgarOfs) >= 8, true,
      "positive control: the saved pool can afford a Bio Blaster, so the "
      .. "first open has at least one white row that will later grey")
  end),

  -- first natural encounter
  H.driveUntil(function() return H.battleLoadStarted() end, 8600,
    { H.call(pulse), H.waitFrames(1) }, "a cave encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == EDGAR then edgarSlot = s end
    end
    assert(edgarSlot, "EDGAR present (kolts party)")
    H.log(string.format("EDGAR slot %d, battle pool %d", edgarSlot, pool()))
  end),

  -- 1. RICH POOL: the first open, everything affordable renders white -------
  openToolsWindow("edgar's tools window, rich pool"),
  H.call(function()
    local mp = pool()
    H.screenshot("tools_grey_rich")
    for _, id in ipairs({ BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW }) do
      local a = attrOf(NM[id].g)
      local want = (mp >= costOf(id)) and WHITE or GREY
      H.log(string.format("  rich pool (%d MP): %-12s attr=%s want $%02x",
        mp, NM[id].name, a and string.format("$%02x", a) or "nil", want))
      H.assertEq(a, want, string.format(
        "%s (cost %d, MP %d) renders %s at the rich pool",
        NM[id].name, costOf(id), mp, want == WHITE and "white" or "grey"))
    end
    H.assertEq(pool() >= 8, true,
      "the rich-pool pass had Bio Blaster white -- the row that must grey below")
  end),

  -- 2. SPEND to the boundary with the tools themselves ----------------------
  H.call(function() mode = "spend" end),
  H.driveUntil(function() return pool() <= 7 end, 120000,
    { H.call(pulse), H.waitFrames(1) }, "the pool is spent into the boundary"),
  H.call(function()
    local mp = pool()
    H.log(string.format("pool after real casts: %d MP", mp))
    H.assertEq(mp >= 4 and mp <= 7, true,
      "the spend plan parked the pool in [4,7]: Bio Blaster unaffordable, "
      .. "AutoCrossbow affordable -- both states on one screen")
  end),

  -- ... and the boundary window: grey and white side by side ----------------
  openToolsWindow("edgar's tools window, spent pool"),
  H.call(function()
    local mp = pool()
    H.screenshot("tools_grey_display")
    local aBio = attrOf(NM[BIOBLASTER].g)
    local aNoise = attrOf(NM[NOISEBLASTER].g)
    local aXbow = attrOf(NM[AUTOCROSSBOW].g)
    local fmt = function(a) return a and string.format("$%02x", a) or "nil" end
    H.log(string.format("spent pool (%d MP): Bio=%s Noise=%s Xbow=%s",
      mp, fmt(aBio), fmt(aNoise), fmt(aXbow)))
    H.assertEq(aBio, GREY, string.format(
      "Bio Blaster (cost 8, MP %d) renders grey -- the charge priced it out", mp))
    H.assertEq(aXbow, WHITE, string.format(
      "AutoCrossbow (cost 4, MP %d) renders white -- still affordable", mp))
    H.assertEq(aNoise, (mp >= 6) and WHITE or GREY,
      "NoiseBlaster follows its own affordability line")
    H.assertEq(aBio - aXbow, 0x04,
      "grey - white == $04, magic's own disabled-bit delta")
    H.log("PASSED: the tools window greys exactly what the SPENT pool cannot "
      .. "afford -- the charge and the grey read the same cell")
  end),
})

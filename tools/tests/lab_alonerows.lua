-- lab_alonerows.lua -- a lab (#556): the thief's and the painter's ally rows with nobody to take them.
-- lab_tower_split's flight and split (Continue wor-desert-v1, the Falcon to Kefka's Tower, party_menu 3), with
-- LAB_SPLIT's first group one character alone (default LOCKE; RELM with LAB_SPLIT = { { 8 }, ... }), then that
-- party walks a lap on the tower's first map into a battle and plays LAB_PLAN through the real menu
-- (H.kitBattle), reading each row's colour off VRAM at every list it opens (LAB_ROWS: name -> glyph text).
-- Reads and presses only.
-- @manual a lab (#556)
-- @checkpoint wor-desert-v1
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = H.SPLIT_NAMES
local SPLIT = LAB_SPLIT or {
  { LOCKE },
  { TERRA, SHADOW, SABIN, EDGAR },
  { CELES, CYAN, GAU, STRAGO },
}
local PARTY = LAB_PARTY or 1
local BATTLES = LAB_BATTLES or 8
local BURN = LAB_BURN or 0
local BURN_PARTY = LAB_BURN_PARTY or 2
local TOWER_LANDING = { 137, 198 }
local MAP_TOWER = 334
-- the tower's first map's species: the Vectaur and the Brontaur are weak to ice, the Evil Oscar absorbs it (and
-- is weak to fire); whoever holds the element casts it while its target stands, as the forest's legs do
local VECTAUR, BRONTAUR, OSCAR, BEHEMOTH = 0x080, 0x084, 0x0B7, 0x0E0
local ICE, FIRE = 0x01, 0x00
local FIGHT = {}
FIGHT.nuke = function()
  if H.formationHas({ [OSCAR] = true }) then return { FIRE } end
  if H.formationHas({ [VECTAUR] = true, [BRONTAUR] = true }) then return { ICE } end
  return nil
end
H.NAV_REFIRE_HOLD = true
-- the care between battles tops everyone up to full and casts first, as the line's forest and desert do
-- (route-wor-side-trips.md finding 3: at the default 65% the two-Tyranosaur battles lost a third); the tower has
-- no counter, so the cures are cast before the bag is reached for
H.careThreshold = LAB_CARE or 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, settled, board, watches = K.map, K.settled, K.board, K.watches

local function roster(p)
  local t = {}
  for _, c in ipairs(H.partyRoster(p)) do
    t[#t + 1] = string.format("%s L%d %d/%d", NAMES[c], H.readByte(0x1600 + 37 * c + 8), H.charHp(c), H.charMaxHp(c))
  end
  return table.concat(t, ", ")
end
local function bag()
  return string.format("potion=%d xpotion=%d fenix=%d revivify=%d tincture=%d ether=%d remedy=%d tent=%d",
    H.invCountOf(0xE9), H.invCountOf(0xEA), H.invCountOf(0xF0), H.invCountOf(0xF1), H.invCountOf(0xEB),
    H.invCountOf(0xEC), H.invCountOf(0xF5), H.invCountOf(0xF7))
end
local function say(what)
  H.log(string.format("[lab] f%d %s; %s; %s", H.frame, what, H.partiesLine(), bag()))
end

-- a lap of two tiles from where the walked party stands (paceToEncounter's choice: three tiles off, then two)
local LAP = nil
local function pickLap(tag)
  local x0, y0 = H.fieldX(), H.fieldY()
  LAP = nil
  for _, d in ipairs({ { 0, 3 }, { 0, -3 }, { 3, 0 }, { -3, 0 }, { 0, 2 }, { 2, 0 }, { -2, 0 }, { 0, -2 } }) do
    if H.bfsPath(x0 + d[1], y0 + d[2]) then LAP = { { x0, y0 }, { x0 + d[1], y0 + d[2] } }; break end
  end
  H.assertEq(LAP ~= nil, true, string.format("%s: a walkable lap from map %d (%d,%d)", tag, map(), x0, y0))
  H.log(string.format("[lab] %s: lap (%d,%d) <-> (%d,%d)", tag, LAP[1][1], LAP[1][2], LAP[2][1], LAP[2][2]))
end

local wp, n0, seen = 1, 0, 0
local function still() return not H.battleLoadStarted() and H.hasControl() and H.tileAligned() end

-- ---- the rows read and the plan played (#556) -----------------------------------------------------------------
local function glyphs(str)
  local t = {}
  for i = 1, #str do
    local c = str:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte()) or (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- a row's font attribute where its name stands in VRAM ($21 white, $25 grey), or nil
local function attrOf(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return emu.read(w * 2 + 1, vr) end
  end
end
local ALONE = SPLIT[PARTY][1]
local ROWS = LAB_ROWS or (ALONE == RELM and { "Portrait", "Tint", "Varnish", "Gesture", "Sketch" }
  or { "Steal", "Bestow" })
local CMD = ALONE == RELM and 0x0D or 0x05
local PEEKROW = ALONE == RELM and 0xE9 or 0x58          -- Portrait / Bestow
function ALONE_ARM()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      H.log(string.format("[alone] seat %d char %02X hp %d bank %d", s, H.readByte(0x3ED8 + s * 2),
        H.readWord(0x3BF4 + s * 2), H.readByte(0x3E9C + s * 2)))
    end
  end
end
function ALONE_PLAN()
  return LAB_ALONE_PLAN or {
    { who = ALONE, cmd = CMD, row = PEEKROW, peek = true, boost = 0 },
    { who = ALONE, cmd = CMD, row = PEEKROW, peek = true, boost = 1 },
    { who = ALONE, cmd = CMD, row = PEEKROW, boost = 1, refused = "list" },
  }
end
local shots = 0
function ALONE_ONLIST(p, a)
  local t = {}
  for _, n in ipairs(ROWS) do
    local at = attrOf(glyphs(n))
    t[#t + 1] = string.format("%s %s", n, at and string.format("$%02X", at) or "nil")
  end
  H.log(string.format("[alone] f%d list (entry boost %d, refused %s): pending %d bank %d mp %d: %s", H.frame,
    p.boost or 0, tostring(p.refused), H.readByte(0x3E9D + a * 2), H.readByte(0x3E9C + a * 2),
    H.readWord(0x3C08 + a * 2), table.concat(t, ", ")))
  shots = shots + 1
  if shots <= 6 then H.screenshot(string.format("alone_%d", shots)) end
end

H.run({ maxFrames = 1200000 }, {
  H.bootCheckpoint(LAB_BOOT or "wor-desert-v1"),
  watches(),
  H.call(function()
    H.log(string.format("[lab] split %s; party %d fights %d battles after %d run from",
      table.concat((function()
        local g = {}
        for i, ids in ipairs(SPLIT) do
          local n = {}
          for _, c in ipairs(ids) do n[#n + 1] = NAMES[c] end
          g[#g + 1] = i .. ": " .. table.concat(n, " ")
        end
        return g
      end)(), " / "), PARTY, BATTLES, BURN))
  end),
  -- @@setup-end

  -- ---- the flight and the split --------------------------------------------------------------------------
  board(),
  H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
  H.flyTo(TOWER_LANDING[1], TOWER_LANDING[2], { what = "the Falcon to Kefka's Tower", entersMap = true, fight = FIGHT,
    maxFrames = 20000 }),
  H.driveUntil(function() return H.readByte(0x0059) ~= 0 and H.readByte(0x26) == 0x2d end, 9000, {
    H.call(function() H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {}) end),
  }, "the tower's party menu (party_menu 3)"),
  H.waitFrames(20),
  H.partySelect(SPLIT, { tag = "the tower's three groups" }),
  H.advanceStory(function() return map() == MAP_TOWER and settled() end, 12000, { playBattles = "tactical",
    fight = FIGHT }),
  H.call(function()
    for g, ids in ipairs(SPLIT) do
      for _, c in ipairs(ids) do
        H.assertEq(H.partyOfChar(c), g, string.format("%s is in party %d", NAMES[c], g))
      end
    end
    H.assertEq((H.readByte(0x1EB9) & 0x40) ~= 0, true, "party switching on ($01CE, EnterKefkasTower)")
    say("in the tower")
  end),
  -- one bag for three parties: LAB_SHARES splits it (default three parts of four to the measured party, one to
  -- the burn's, none to the third, which never walks here)
  H.lazy(function()
    local shares = LAB_SHARES or { [PARTY] = 3, [BURN_PARTY] = 1 }
    for p = 1, 3 do shares[p] = shares[p] or 0 end
    return H.splitBegin({ shares = shares })
  end),

  H.cond(function() return H.activeParty() ~= PARTY end, {
    H.lazy(function() return H.switchParty(PARTY) end),
  }, {}),
  H.fieldCare({ tag = "care before the lab", threshold = 1.0 }),
  H.call(function() pickLap("party " .. PARTY); say("alone: " .. roster(PARTY)) end),
  H.driveUntil(function() return H.battleLoadStarted() end, 200000, {
    H.navTo(function() return LAP[wp][1] end, function() return LAP[wp][2] end,
      { maxFrames = 20000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % 2 + 1 end),
  }, "a battle on the lap"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.waitFrames(30),
  H.call(function() ALONE_ARM() end),
  H.kitBattle(ALONE_PLAN(), { untilPlanDone = true, idle = "defend", maxFrames = 40000, onList = ALONE_ONLIST,
    care = false }),
  H.call(function() say("the plan is spent") end),
})

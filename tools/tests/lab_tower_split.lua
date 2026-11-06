-- lab_tower_split.lua -- a lab (#496): what each of Kefka's Tower's three parties needs.  Continue a battery
-- that stands beside the Falcon (the line's `wor-desert-v1`, Kefka's Tower's boot; or a training stretch's save),
-- fly to the tower (world (137,198): the one World of Ruin tile whose property word has bit $8000, LandAirship's
-- VehicleEvent_04 -> EnterKefkasTower), seat the three groups `party_menu 3` offers as LAB_SPLIT says, land on
-- the tower's first map (334, pool group 208: Brontaur with Evil Oscar 272, Vectaur x4 271, GtBehemoth with Evil
-- Oscar and Vectaur 329), then walk LAB_PARTY's party on a two-tile lap there, the walker playing every battle and
-- the field care after each, for LAB_BATTLES battles.  LAB_BURN encounters are used up first by another party
-- (LAB_BURN_PARTY) fighting them on the same map (its formations refuse the run), so a sweep varies the draw by the
-- encounters used up (docs/TESTING.md) and leaves the measured party as the split seated it.  A party that wipes
-- ends the run (a game over), and that is the measurement: the log says which battle, whose death and which
-- formation.  Reads and presses only; the save it Continues is never written.
--
-- The knobs are globals a maker prepends ahead of the lib (Mesen's Lua has no os.getenv):
--   LAB_BOOT    the checkpoint key it Continues (default wor-desert-v1; wor-bench-v1 after the bench's training)
--   LAB_SPLIT   { { ids }, { ids }, { ids } }: the three groups, each in battle order (default: two of the six at
--               L53-64 in each party beside two of the bench)
--   LAB_PARTY   the party that fights (1-3; default 1)
--   LAB_BATTLES battles it fights (default 8)
--   LAB_BURN    encounters used up first by LAB_BURN_PARTY (default 0; the party default 2)
--   LAB_CARE    the field care's threshold (default 1.0, to full); LAB_SHARES the bag's split (party -> weight)
-- Run (px13; the capture, never the tracked save):
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-desert-v1 OT6_RETRIES=1 OT6_SEED_SHIFT=0 \
--     tools/tests/run.sh tools/tests/lab_tower_split.lua
-- and tally with tools/tower_tally.py.  docs/design/route-wor-kefka-tower.md 7.1 has what it measured.
-- @manual a lab: the tower's first map, one party of a three-party split (#496)
-- @checkpoint wor-desert-v1
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = H.SPLIT_NAMES
local SPLIT = LAB_SPLIT or {
  { TERRA, SHADOW, SABIN, EDGAR },
  { CELES, CYAN, LOCKE, GAU },
  { RELM, STRAGO, GOGO, SETZER },
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

  -- ---- the encounters used up: LAB_BURN battles fought by another party ------------------------------------
  -- The tower's first map refuses the run in its formations ($B1 bit 1: "this formation cannot be run from"), so
  -- the encounters are used up by fighting them, by a party the lab does not measure (LAB_BURN_PARTY, default
  -- 2): the measured party's XP, HP and bag share stay as the split left them.
  H.cond(function() return BURN > 0 end, {
    H.lazy(function() return H.switchParty(BURN_PARTY) end),
    H.call(function() pickLap("the burn (party " .. BURN_PARTY .. ")"); wp, n0, seen = 1, #H.outcomes, #H.outcomes end),
    H.driveUntil(function()
      while seen < #H.outcomes do
        seen = seen + 1
        local o = H.outcomes[seen]
        H.log(string.format("[lab] used up encounter %d of %d: party %d formation %d %s", seen - n0, BURN,
          BURN_PARTY, o.form & 0x1FF, o.kind))
      end
      return #H.outcomes - n0 >= BURN and still()
    end, 3000000, {
      H.call(function() H.watchQuiet(600, nil) end),
      H.navTo(function() return LAP[wp][1] end, function() return LAP[wp][2] end,
        { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
      H.call(function() wp = wp % 2 + 1 end),
      H.cond(function() return not H.battleLoadStarted() end, { H.fieldCare({ tag = "care on the burn" }) }, {}),
    }, "the encounters LAB_BURN uses up"),
  }, {}),

  -- ---- the measured party ----------------------------------------------------------------------------------
  H.cond(function() return H.activeParty() ~= PARTY end, {
    H.lazy(function() return H.switchParty(PARTY) end),
  }, {}),
  H.fieldCare({ tag = "care before the measure", threshold = 1.0 }),
  H.call(function()
    pickLap("party " .. PARTY)
    wp, n0, seen = 1, #H.outcomes, #H.outcomes
    say(string.format("party %d starts: %s", PARTY, roster(PARTY)))
    local cures = {}
    for _, c in ipairs(H.partyRoster(PARTY)) do
      local k = {}
      for _, sp in ipairs({ { 0x2D, "Cure" }, { 0x2E, "Cure 2" }, { 0x2F, "Cure 3" }, { 0x30, "Life" } }) do
        if H.knowsSpell(c, sp[1]) then k[#k + 1] = sp[2] end
      end
      if #k > 0 then cures[#cures + 1] = NAMES[c] .. " " .. table.concat(k, "/") end
    end
    H.log(string.format("[lab] party %d's cures: %s", PARTY, #cures > 0 and table.concat(cures, ", ") or "none"))
  end),
  H.driveUntil(function()
    while seen < #H.outcomes do
      seen = seen + 1
      local o = H.outcomes[seen]
      H.log(string.format("[lab] party %d battle %d formation %d %s after %d ticks; %s", PARTY, seen - n0,
        o.form & 0x1FF, o.kind, o.tick or -1, roster(PARTY)))
    end
    return #H.outcomes - n0 >= BATTLES and still()
  end, 3000000, {
    H.call(function() H.watchQuiet(600, nil) end),
    H.navTo(function() return LAP[wp][1] end, function() return LAP[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.call(function() wp = wp % 2 + 1 end),
    H.cond(function() return not H.battleLoadStarted() end, { H.fieldCare({ tag = "care on the lap" }) }, {}),
  }, "the measured party's battles"),
  H.splitEnd(),
  H.call(function() say(string.format("party %d done: %d battles", PARTY, #H.outcomes - n0)) end),
})

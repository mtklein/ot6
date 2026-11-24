-- @suite slow
-- battle_runicmonster.lua -- RunicBlade sends a monster's spell back at the
-- monster (#378, #424).
--
-- kits.md: a 3-BP Runic (RunicBlade, once CELES has learned it) sends every
-- player-magic spell it absorbs back at its caster as her own free cast of
-- it (Ot6BladeAbsorb banks it, Ot6BladeBounce queues it through vanilla's
-- counterattack queue).  battle_runicblade's caster is always EDGAR; here
-- the caster is a monster.
--
-- Played: Continue the wor-narshe-cliffs-v1 battery (the factory long
-- behind CELES), walk from the cliffs' save point (map 34) up onto
-- Tritoch's ledge (map 35, the same pool, group 191) and pace there into
-- random battles, and in one that fields a Wizard (its script is nothing
-- but player magic: Mute, Osmose, Rasp, Stop, Muddle, Sleep; formations 276
-- and 277, 160/256 of the ledge's battles, route_data.py map 35)
-- CELES raises Runic at 3 BP through the real menu (H.kitBattle; Defends
-- bank the points); everyone Defends.  A battle with no Wizard, or one that
-- ends first, is fought out and the next taken; a stance that runs out
-- without catching a Wizard's spell is raised again.  Nothing is written.
--
-- Recorded: every absorb by a RunicBlade stance (Ot6BladeAbsorb: the caster
-- and the spell), and every $3410 write (the spell an attack pass uses)
-- with the counter flag ($b1 bit 0), the command and the target masks.
-- Asserted, for the first absorb of a Wizard's spell:
--   1. the absorb banked a bounce for that monster (OT6_BLADEPEND valid,
--      OT6_BLADECASTER = its entity, OT6_BLADESPELL = the spell);
--   2. a counter came: Magic, that spell, at that monster alone ($b9 = its
--      bit, $b8 = 0).  (Its price, none, is battle_runicblade's.)
-- Old-ROM red and mutants: build/attempts/wt/v031-cleanup/ (#424).
--
-- The rune (#563, ot6_rune.asm): a Runic absorb of a spell that carries an
-- element arms the absorber's blade with it (Ot6RuneAbsorb, inside
-- Ot6RunicBP), and a spell with none leaves the rune as it was.  Recorded at
-- every Ot6RunicBP that runs for CELES's seat on a monster's spell: the
-- spell ($b6), OT6_RUNE at her seat before it and as Ot6BladeAbsorb, the
-- next call, finds it.  Asserted for every one, in both halves:
--   3. the rune after the absorb is the spell's element byte in the ROM
--      (MagicProp+1) when that is not zero, and unchanged when it is;
--   4. its tier (OT6_RUNETIER) is then the spell's place in its line
--      (Ot6FoldTbl: the second column 2, the third 3, any other spell 1,
--      as Ot6RuneTierOf), and unchanged with the rune.
-- A Wizard's six spells carry no element, so the first half holds only the
-- "unchanged" arm.  The second half is the other arm: the walk back down
-- the cliffs (34, kept off the Ice Dragon's live tile and the four beside
-- it, re-planned whenever it moves) and through their lower map (33) into
-- the mines (36), whose every battle is Mag Roaders (formations 280 and 281;
-- $0E7 casts Ice and Ice 2, $0F3 Fire and Fire 2, all runic: route_data.py
-- pool field 36).  There CELES raises Runic at 1 BP, the others Defend, and
-- the half ends at the first absorb of an elemental spell past its line's
-- head (Ice 2 or Fire 2: tier 2), so both a rune and a tier above 1 have
-- been armed by a monster.
-- Mutant red (Ot6RuneAbsorb arms nothing; the absorb's tier always 1):
-- build/attempts/wt/v051-spellblade/sb2/B/ and sb2/E/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, RUNIC, CMD_MAGIC, WIZARD = 0x06, 0x0B, 0x02, 0x0C4
local RUNE = 0xED8F                  -- OT6_RUNE (ot6_memory.inc): a seat's rune, stride 2
local RUNETIER = 0xEE3A              -- OT6_RUNETIER: its tier, 1-3, stride 2
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF
local FOLD = H.sym("Ot6FoldTbl") & 0x3FFFFF
-- a spell's tier, its place in its line (Ot6RuneTierOf): Ot6FoldTbl's rows
-- are [head, one boost, two boosts]; fire, ice, bolt and poison's second
-- column is tier 2, the first three's third column tier 3, any other spell 1
local function tierOf(spell)
  for row = 0, 3 do if H.readRomByte(FOLD + row * 3 + 1) == spell then return 2 end end
  for row = 0, 2 do if H.readRomByte(FOLD + row * 3 + 2) == spell then return 3 end end
  return 1
end
-- Not on map 34, where this suite paced below the save point until v0.38:
-- the Ice Dragon (NPC_2, event battle 132: L74, 24400 HP, no running, a game
-- over when lost) walks that map at random (npc_prop.asm: set_npc_movement
-- RANDOM) and came to the pace first on every draw measured -- "[seed]
-- first battle ... group $016E" at f1413-f1419 on shifts 0, 7 and 13
-- (build/attempts/wt/v036-fragile/K/res/) -- so the suite's first battle
-- was the dragon's, fought out with plain Fights: won while the chain's
-- party could, wiped once wt/v038-wob-gear's play dressed it otherwise
-- ("GAME OVER fired ... battle wipe x1", formation ... 0149 ...,
-- build/attempts/wt/v038-wob-suites/repro/).  The dragon is the route's
-- (gen_wor_tritoch fights it armed for ice), not this suite's; Tritoch's
-- ledge deals the cliffs' own pool and holds no wanderer.  The walk: the
-- save point (25,5) to the long exit (20,1) -> map 35 (25,30), 13 steps
-- (route_data.py field-path 34 25 5 20 1); the pace two tiles up the
-- ledge's straight run, well clear of its exit row (y 32) and of
-- Tritoch's triggers (9,14) and (9,12) (route_data.py field-path 35 25 30
-- 25 25: 5 steps up x = 25).
local MAP_CLIFFS, MAP_LEDGE, ICEDRAGON = 34, 35, 0x149
local LEDGE_EXIT = { 20, 1 }
local PACE = { { 25, 28 }, { 25, 25 } }
local RUNICBLADE, BLADEPEND, BLADECASTER, BLADESPELL = 0xEDD4, 0xEDD5, 0xEDD6, 0xEDD7

local celes = nil
local dragonMet = false
local absorbs, passes = {}, {}
-- every absorb of a monster's spell by CELES's seat, any Runic stance:
-- { spell, elem (MagicProp+1), before, after (OT6_RUNE at her seat), f }
local runes, runeAt, runeChecked = {}, nil, 0
local function arm()
  local ab = H.sym("Ot6BladeAbsorb")
  local rb = H.sym("Ot6RunicBP")
  emu.addMemoryCallback(function()
    runeAt = nil
    if celes == nil then return end
    local st = emu.getState()
    if (st["cpu.y"] & 0xFF) ~= celes * 2 or (st["cpu.x"] & 0xFF) < 8 then return end
    runeAt = { before = H.readByte(RUNE + celes * 2), tierBefore = H.readByte(RUNETIER + celes * 2),
      spell = H.readByte(0xB6), f = H.frame }
  end, emu.callbackType.exec, rb, rb)
  emu.addMemoryCallback(function()
    local r = runeAt
    runeAt = nil
    if r == nil or celes == nil or (emu.getState()["cpu.y"] & 0xFF) ~= celes * 2 then return end
    r.after, r.elem = H.readByte(RUNE + celes * 2), H.readRomByte(MAGIC_PROP + r.spell * 14 + 1)
    r.tierAfter, r.tier = H.readByte(RUNETIER + celes * 2), tierOf(r.spell)
    r.caster = emu.getState()["cpu.x"] & 0xFF
    runes[#runes + 1] = r
    H.log(string.format("[rbm] f%d CELES's Runic absorbs spell $%02X (element byte $%02X, tier %d) from monster slot "
      .. "%d: OT6_RUNE at her seat $%02X -> $%02X, its tier %d -> %d", r.f, r.spell, r.elem, r.tier,
      (r.caster - 8) // 2, r.before, r.after, r.tierBefore, r.tierAfter))
  end, emu.callbackType.exec, ab, ab)
  -- Ot6BladeAbsorb's tail: the bank is written (or not) by its rtl; read it
  -- at the next $3410 write or Ot6ActionEnd instead, from this record
  emu.addMemoryCallback(function()
    if celes == nil then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if y ~= celes * 2 or x < 8 then return end
    if (H.readByte(RUNICBLADE) & H.readByte(0x3018 + y)) == 0 then return end
    local a = { caster = x, spell = H.readByte(0xB6), species = H.monsterIds()[(x - 8) // 2 + 1], f = H.frame,
      mp = H.readWord(0x3C08 + y) }
    absorbs[#absorbs + 1] = a
    H.log(string.format("[rbm] f%d CELES's RunicBlade absorbs spell $%02X from monster slot %d (species $%03X)", a.f,
      a.spell, (x - 8) // 2, a.species or 0))
  end, emu.callbackType.exec, ab, ab)
  -- the bank, as CheckRetal's head finds it (Ot6BladeBounce consumes it)
  local bb = H.sym("Ot6BladeBounce")
  emu.addMemoryCallback(function()
    local a = absorbs[#absorbs]
    if a ~= nil and a.pend == nil then
      a.pend, a.bcaster, a.bspell = H.readByte(BLADEPEND), H.readByte(BLADECASTER), H.readByte(BLADESPELL)
    end
  end, emu.callbackType.exec, bb, bb)
  emu.addMemoryCallback(function(_, v)
    if celes == nil then return end
    local p = { spell = v, counter = (H.readByte(0xB1) & 1) == 1, cmd = H.readByte(0x3A7C), b8 = H.readByte(0xB8),
      b9 = H.readByte(0xB9), celesMp = H.readWord(0x3C08 + celes * 2), f = H.frame }
    passes[#passes + 1] = p
    if p.counter then
      H.log(string.format("[rbm] f%d counter pass: spell $%02X, command $%02X, targets chars $%02X mons $%02X, CELES "
        .. "MP %d", p.f, p.spell, p.cmd, p.b8, p.b9, p.celesMp))
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end

local function map() return H.mapId() & 0x1ff end
-- the Ice Dragon's object (gen_wor_tritoch's dragonObj): map 34's one live
-- object besides the save point's (25,5)
local function dragonLine()
  if map() ~= MAP_CLIFFS then return "not on map 34" end
  local t = {}
  for o = 0x10, 0x2F do
    local ox, oy = H.objX(o), H.objY(o)
    if not (ox == 0 and oy == 0) and not (ox == 25 and oy == 5) then
      t[#t + 1] = string.format("$%02X at (%d,%d)", o, ox, oy)
    end
  end
  return #t > 0 and table.concat(t, ", ") or "none"
end

local function wizardSlots()
  local ids, t = H.monsterIds(), {}
  for s = 0, 5 do
    if ids[s + 1] == WIZARD and (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 then
      t[#t + 1] = s
    end
  end
  return t
end

-- BATTLES: a battle fields a Wizard 160/256 of the time, so none in ten is
-- 0.375^10 = 5.5e-5; a stance raised in a Wizard battle catches its spell
-- unless CELES is stopped or the Wizards turn elsewhere, so RAISES = 8
-- stances in all.
local BATTLES, RAISES = 14, 8
local battles, raises, ok, mode, nAbs, nPass, raisedF, fresh = 0, 0, false, nil, 0, 0, 0, true
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

-- the bounce of absorb a: a counter pass, from the absorb on, of that spell
-- at its caster alone
local function bounceOf(a)
  for j = nPass + 1, #passes do
    local p = passes[j]
    if p.counter and p.f >= a.f and p.spell == a.spell and p.b8 == 0
        and p.b9 == (1 << ((a.caster - 8) // 2)) then
      return p
    end
  end
end

-- 3. the rune: every recorded absorb of a monster's spell left OT6_RUNE at
-- CELES's seat the spell's own element, or as it was when the spell has none
local function runeVerdict()
  while runeChecked < #runes do
    runeChecked = runeChecked + 1
    local r = runes[runeChecked]
    if r.elem ~= 0 then
      H.assertEq(r.after, r.elem, string.format("the absorb of monster spell $%02X at f%d armed CELES's blade with "
        .. "its element (OT6_RUNE at her seat = MagicProp+1 $%02X; it was $%02X before)", r.spell, r.f, r.elem,
        r.before))
      H.assertEq(r.tierAfter, r.tier, string.format("and with the spell's tier (OT6_RUNETIER at her seat = %d, "
        .. "spell $%02X's place in its line, Ot6FoldTbl; it was %d before)", r.tier, r.spell, r.tierBefore))
    else
      H.assertEq(r.after, r.before, string.format("the absorb of monster spell $%02X at f%d, which carries no "
        .. "element, left CELES's rune as it was (OT6_RUNE $%02X)", r.spell, r.f, r.before))
      H.assertEq(r.tierAfter, r.tierBefore, string.format("and its tier as it was (OT6_RUNETIER %d)", r.tierBefore))
    end
  end
end
-- the first absorb since record n of an elemental spell past its line's head
local function tieredSince(n)
  for i = n + 1, #runes do if runes[i].elem ~= 0 and runes[i].tier >= 2 then return runes[i] end end
end

local function verdict()
  runeVerdict()
  for i = nAbs + 1, #absorbs do
    local a = absorbs[i]
    if a.species == WIZARD then
      H.assertEq(a.pend, 0x80 | (celes * 2), string.format("the absorb banked a bounce for CELES (OT6_BLADEPEND "
        .. "$%02X)", a.pend or 0))
      H.assertEq(a.bcaster, a.caster, "the bounce's caster is the Wizard that cast it (OT6_BLADECASTER)")
      H.assertEq(a.bspell, a.spell, "the bounce is the absorbed spell (OT6_BLADESPELL)")
      local back = bounceOf(a)
      H.assertEq(back ~= nil, true, string.format("a counter sent spell $%02X back at the Wizard in slot %d", a.spell,
        (a.caster - 8) // 2))
      H.assertEq(back.cmd, CMD_MAGIC, "the bounce is a Magic cast")
      H.log(string.format("[rbm] the bounce at f%d: spell $%02X at monster mask $%02X; CELES MP %d before it",
        back.f, back.spell, back.b9, back.celesMp))
      ok = true
      return
    end
  end
end

-- back to walkable field control after a battle, paging any dialog with A
-- (4 frames on, 4 off: one edge per page).  A fought-out battle can end in
-- one: on the v0.32 aura chain's battery the cliffs dealt formation $16E,
-- a dragon, and its fall shows vanilla's "6 dragons left." until a key is
-- pressed, which a bare wait for control never gets past.
local function toControl()
  local t = 0
  return H.driveUntil(function() return H.hasControl() and H.tileAligned() end, 3000, {
    H.call(function()
      t = t + 1
      if H.dialogWaiting() then
        if t % 8 == 0 then H.log(string.format("[rbm] f%d a dialog waits after the battle: A", H.frame)) end
        H.setPad(t % 8 < 4 and { a = true } or {})
      else
        H.setPad({})
      end
    end),
  }, "rbm: field control after the battle")
end

-- ---- the second half's walk and pace -------------------------------------
-- route_data.py map 35/34/33/36: the ledge's long exit (23,32) len 4 -> map
-- 34 (20,2), a row past the ledge's 32 rows, so its last tile (25,31) and a
-- step down off the edge; map 34's long exit (16,41) len 4 -> map 33 (36,2);
-- map 33's door (31,10) -> map 36 (116,12), in the corridor that runs to
-- the mines' other cliff door ((116,12) -> (108,12) is 10 steps, field-path
-- 36).
local MAP_LOWER, MAP_MINES, MAG_ICE, MAG_FIRE = 33, 36, 0x0E7, 0x0F3
local LEDGE_EDGE, CLIFFS_DOWN, MINES_DOOR = { 25, 31 }, { 17, 41 }, { 31, 10 }
-- map 33's other doors and its way back up to map 34
local LOWER_AVOID = { { 37, 25 }, { 24, 10 }, { 30, 20 }, { 31, 20 }, { 32, 20 }, { 33, 1 }, { 34, 1 }, { 35, 1 },
  { 36, 1 }, { 37, 1 } }
-- the pace keeps to the corridor, a tile off each of its doors ((107,12)
-- and (117,12), kept off with the mines' other exits)
local PACE2 = { { 109, 12 }, { 115, 12 } }
local MINES_AVOID = { { 57, 11 }, { 57, 21 }, { 25, 59 }, { 18, 51 }, { 107, 12 }, { 117, 12 }, { 7, 34 }, { 21, 9 },
  { 113, 45 }, { 108, 60 }, { 73, 61 }, { 111, 29 }, { 112, 29 } }
-- BATTLES2: every battle of map 36 fields Mag Roaders and the party only
-- Defends, so a battle ends early only by CELES's own fall; RAISES2: a
-- 1-BP stance stands through one of her turns, two rounds of three
-- Roaders whose scripts are half spells, and half of those the tier-2 one
local BATTLES2, RAISES2 = 6, 12
local battles2, raises2, ok2, nRune = 0, 0, false, 0

-- the Ice Dragon's live tile on map 34 (dragonLine's object), or nil: it is
-- a touch-to-fight NPC that wanders (gen_wor_tritoch's touchNpc), so the
-- walk down plans off its tile and the four beside it and is planned again
-- whenever it has moved; the tiles of the exit back up to the ledge too
local function dragonTile()
  if map() ~= MAP_CLIFFS then return nil end
  for o = 0x10, 0x2F do
    local ox, oy = H.objX(o), H.objY(o)
    if not (ox == 0 and oy == 0) and not (ox == 25 and oy == 5) then return ox, oy end
  end
end
local function dragonKey()
  local ox, oy = dragonTile()
  return ox and (ox .. "," .. oy) or ""
end
local function dragonAvoid()
  local t = { { 18, 1 }, { 19, 1 }, { 20, 1 }, { 21, 1 } }
  local ox, oy = dragonTile()
  if ox then
    for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do t[#t + 1] = { ox + d[1], oy + d[2] } end
  end
  return t
end
-- walk map `from`'s tile `at` (an exit) onto map `to`; battles on the way
-- are played out by the walker, the Ice Dragon's refused as the
-- precondition it breaks
local function walkInto(from, at, to, what, avoid)
  -- the plan in force was made with the dragon on `seen`, near the party
  -- (within 6 steps) or not; a plan made far from it is good until the
  -- party comes near, and one made near it until it moves
  local seen, nearThen = "", false
  local function near()
    local ox, oy = dragonTile()
    return ox ~= nil and math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) <= 6
  end
  return H.seqStep({
    H.driveUntil(function() return map() ~= from or dragonMet end, 200000, {
      H.call(function()
        seen, nearThen = dragonKey(), near()
        if from == MAP_CLIFFS then
          H.log(string.format("[rbm] f%d a plan from (%d,%d); the Ice Dragon: %s", H.frame, H.fieldX(), H.fieldY(),
            dragonLine()))
        end
      end),
      H.navTo(at[1], at[2], { maxFrames = 30000, playBattles = "tactical", avoid = avoid, noPathRetries = 200,
        arrive = function()
          if H.battleLoadStarted() then
            if H.formationHas({ [ICEDRAGON] = true }) then dragonMet = true end
            return dragonMet
          end
          return map() ~= from or (near() and (dragonKey() ~= seen or not nearThen))
        end }),
      H.release(),
    }, what),
    H.call(function() H.assertEq(dragonMet, false, "precondition: " .. what .. " kept clear of the Ice Dragon") end),
    H.waitUntil(function() return map() == to and H.hasControl() and H.tileAligned() end, 1200, what .. ": control", 1),
    H.call(function()
      H.log(string.format("[rbm] f%d on map %d at (%d,%d)", H.frame, map(), H.fieldX(), H.fieldY()))
    end),
  })
end
-- off the ledge: to its bottom row, then Down over the edge (a battle that
-- comes up on the way is the walker's, one on the last step is fought out
-- here and the step taken again)
local function offLedge()
  return H.seqStep({
    H.repeatN(4, {
      H.cond(function() return map() == MAP_LEDGE end, {
        H.navTo(LEDGE_EDGE[1], LEDGE_EDGE[2], { maxFrames = 12000, playBattles = "tactical" }),
        H.release(),
        H.driveUntil(function() return map() ~= MAP_LEDGE or H.battleLoadStarted() end, 900, {
          H.call(function()
            H.setPad((H.hasControl() and H.tileAligned()) and { down = true } or {})
          end),
        }, "rbm: Down off the ledge's bottom row"),
        H.release(),
        H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}), toControl() }, {}),
      }, {}),
    }),
    H.waitUntil(function() return map() == MAP_CLIFFS and H.hasControl() and H.tileAligned() end, 1200,
      "rbm: the ledge -> the cliffs (34): control", 1),
    -- the map's objects take their tiles a few frames after control comes
    -- ("$10 at (8,11), $11 at (9,11)" on the first frame, then "$11 at (22,20)")
    H.waitFrames(30),
    H.call(function()
      H.log(string.format("[rbm] f%d on map %d at (%d,%d); the Ice Dragon: %s", H.frame, map(), H.fieldX(),
        H.fieldY(), dragonLine()))
    end),
  })
end
local function paceMines()
  local wp = 1
  return H.seqStep({
    H.fieldCare({ tag = "rbm: care before the mines' pace", threshold = 0.95 }),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.navTo(function() return PACE2[wp][1] end, function() return PACE2[wp][2] end,
        { maxFrames = 8000, avoid = MINES_AVOID, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % #PACE2 + 1 end),
    }, "rbm: a random battle in the mines"),
    H.waitUntil(function() return H.battleActive() end, 1200, "rbm: the mines' battle is up", 2),
    H.waitFrames(30),
  })
end

local steps = {
  H.bootCheckpoint("wor-narshe-cliffs-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (RunicBlade learned)")
  end),
  -- up onto Tritoch's ledge (a battle on the walk is played out by the
  -- walker; the Ice Dragon's would be the dragon this walk leaves behind,
  -- and is refused below as the precondition it breaks)
  H.call(function()
    H.log(string.format("[rbm] f%d on map %d at (%d,%d); the Ice Dragon: %s", H.frame, map(), H.fieldX(),
      H.fieldY(), dragonLine()))
  end),
  H.fieldCare({ tag = "rbm: care before the walk", threshold = 0.95 }),
  H.repeatN(3, {
    H.cond(function() return map() ~= MAP_LEDGE and not dragonMet end, {
      H.navTo(LEDGE_EXIT[1], LEDGE_EXIT[2], { maxFrames = 12000, playBattles = "tactical",
        arrive = function()
          if H.battleLoadStarted() and H.formationHas({ [ICEDRAGON] = true }) then dragonMet = true end
          return map() == MAP_LEDGE or dragonMet
        end }),
      H.release(),
      H.waitUntil(function() return map() == MAP_LEDGE or dragonMet end, 600, "rbm: onto Tritoch's ledge (map 35)", 5),
    }, {}),
  }),
  H.waitUntil(function() return dragonMet or (map() == MAP_LEDGE and H.hasControl() and H.tileAligned()) end, 1200,
    "rbm: control on Tritoch's ledge", 1),
  H.call(function()
    H.assertEq(dragonMet, false, "precondition: the walk to Tritoch's ledge kept clear of the Ice Dragon")
    H.log(string.format("[rbm] f%d on Tritoch's ledge (map %d) at (%d,%d)", H.frame, map(), H.fieldX(), H.fieldY()))
  end),
  H.paceToEncounter("rbm", nil, PACE),
  H.driveUntil(function() return ok end, 800000, {
    H.cond(function() return not H.battleLoadStarted() end,
      { toControl(), H.paceToEncounter("rbm", 0, PACE), H.call(function() fresh = true end) }, {}),
    H.call(function()
      if fresh then
        fresh = false
        battles = battles + 1
        H.assertEq(battles <= BATTLES, true, string.format("a Wizard's spell sent back within %d battles", BATTLES))
      end
      H.assertEq(H.formationHas({ [ICEDRAGON] = true }), false,
        "precondition: the suite's battles are the ledge's pool, not the Ice Dragon's")
      celes = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CELES then celes = s end end
      H.assertEq(celes ~= nil, true, "CELES is seated")
      local e, w = celes * 2, wizardSlots()
      plan, mode = {}, "stance"
      if #w == 0 or H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0
          or (H.readByte(0x3EE5 + e) & 0x90) ~= 0 then
        mode = "fightout"
        H.log(string.format("[rbm] battle %d: %d Wizard(s); CELES status %02X %02X: this battle is fought out",
          battles, #w, H.readByte(0x3EE4 + e), H.readByte(0x3EE5 + e)))
        return
      end
      raises = raises + 1
      H.assertEq(raises <= RAISES, true, string.format("a Wizard's spell caught within %d stances", RAISES))
      nAbs, nPass = #absorbs, #passes
      H.log(string.format("[rbm] battle %d: %d Wizard(s) (slots %s); CELES seat %d raises Runic at 3 BP (stance %d)",
        battles, #w, table.concat(w, ","), celes, raises))
      plan = { { who = CELES, cmd = RUNIC, boost = 3, self = true } }
    end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function()
          local k = H.vars.kit[#H.vars.kit]
          if k == nil then return false end
          if raisedF < k.frame then raisedF = k.frame end
          -- a Wizard's spell caught and its bounce come (or 1500 frames for
          -- it), or the stance ran out, or no Wizard is left.  The bounce
          -- is the verdict's own match, not the first counter pass after
          -- the absorb: a Wizard's own counter can come between (shift 3:
          -- "absorbs spell $29 from monster slot 3" at f14006, then "counter
          -- pass: spell $FF, command $29, targets chars $01" at f14455, and
          -- the verdict read before the bounce came;
          -- build/attempts/wt/v038-wob-suites/sw2/)
          runeVerdict()
          for i = nAbs + 1, #absorbs do
            if absorbs[i].species == WIZARD then
              return bounceOf(absorbs[i]) ~= nil or H.frame > absorbs[i].f + 1500
            end
          end
          local stance = (H.readByte(RUNICBLADE) & H.readByte(0x3018 + celes * 2)) ~= 0
          return (H.frame > raisedF + 600 and not stance) or #wizardSlots() == 0
        end }),
      H.call(verdict),
    }),
  }, "a Wizard's spell sent back"),
  H.call(function()
    runeVerdict()
    H.log(string.format("[rbm] PASS: CELES's RunicBlade sent a Wizard's spell back at it (battle %d, stance %d)",
      battles, raises))
  end),

  -- ---- the second half: a monster's elemental spell arms the rune (#563) ----
  H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
  toControl(),
  H.fieldCare({ tag = "rbm: care before the walk down", threshold = 0.95 }),
  H.call(function()
    H.log(string.format("[rbm] f%d the walk down to the mines: on map %d at (%d,%d); the Ice Dragon: %s", H.frame,
      map(), H.fieldX(), H.fieldY(), dragonLine()))
  end),
  offLedge(),
  walkInto(MAP_CLIFFS, CLIFFS_DOWN, MAP_LOWER, "rbm: down the cliffs, off the Ice Dragon -> their lower map (33)",
    dragonAvoid),
  walkInto(MAP_LOWER, MINES_DOOR, MAP_MINES, "rbm: the lower cliffs -> the mines (36)", LOWER_AVOID),
  H.call(function() nRune = #runes end),
  H.driveUntil(function() return ok2 end, 400000, {
    H.cond(function() return not H.battleLoadStarted() end,
      { toControl(), paceMines(), H.call(function() fresh = true end) }, {}),
    H.call(function()
      if fresh then
        fresh = false
        battles2 = battles2 + 1
        H.assertEq(battles2 <= BATTLES2, true, string.format("a Mag Roader's spell caught within %d battles",
          BATTLES2))
      end
      H.assertEq(H.formationHas({ [MAG_ICE] = true, [MAG_FIRE] = true }), true,
        "precondition: the mines' battle fields Mag Roaders (formations 280 and 281, the whole pool of map 36)")
      celes = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CELES then celes = s end end
      H.assertEq(celes ~= nil, true, "CELES is seated")
      local e = celes * 2
      plan, mode = {}, "stance"
      if H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0 or (H.readByte(0x3EE5 + e) & 0x90) ~= 0 then
        mode = "fightout"
        H.log(string.format("[rbm] mines battle %d: CELES status %02X %02X: this battle is fought out", battles2,
          H.readByte(0x3EE4 + e), H.readByte(0x3EE5 + e)))
        return
      end
      raises2 = raises2 + 1
      H.assertEq(raises2 <= RAISES2, true, string.format("a Mag Roader's Ice 2 or Fire 2 caught within %d stances",
        RAISES2))
      H.log(string.format("[rbm] mines battle %d: CELES seat %d raises Runic at 1 BP (stance %d); OT6_RUNE $%02X",
        battles2, celes, raises2, H.readByte(RUNE + e)))
      plan = { { who = CELES, cmd = RUNIC, boost = 1, self = true } }
    end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function()
          local k = H.vars.kit[#H.vars.kit]
          if k == nil then return false end
          if raisedF < k.frame then raisedF = k.frame end
          -- an elemental spell past its line's head caught, or the stance
          -- ran out ($3E4C bit 2, 600 frames after the pick for the raise
          -- itself to play)
          runeVerdict()
          if tieredSince(nRune) ~= nil then return true end
          return H.frame > raisedF + 600 and (H.readByte(0x3E4C + celes * 2) & 0x04) == 0
        end }),
      H.call(function()
        runeVerdict()
        local r = tieredSince(nRune)
        if r ~= nil then
          H.log(string.format("[rbm] PASS: the absorb of a monster's spell $%02X armed CELES's blade with its "
            .. "element and tier, OT6_RUNE $%02X -> $%02X at tier %d (mines battle %d, stance %d; %d absorb(s) in "
            .. "the mines)", r.spell, r.before, r.after, r.tierAfter, battles2, raises2, #runes - nRune))
          ok2 = true
        end
      end),
    }),
  }, "a Mag Roader's elemental spell absorbed"),
}
-- The frame budget is a hang guard, not a pace: 900000 held the first half
-- alone; #563's second half (the walk down the cliffs and into the mines,
-- and as many Mag Roader battles as it takes to absorb an elemental spell)
-- raised it to 1400000.  A passing run ends far inside either (frame 29450 on
-- build/attempts/wt/v051-spellblade/sb2/B/runicmonster_final/).
H.run({ maxFrames = 1400000 }, steps)

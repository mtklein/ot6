-- @suite savestate=returner_hideout
-- field_mpband.lua -- #231: field care's MP band and its Tent arm.
--
-- The rule (docs/design/supply.md): a living member under a quarter of
-- their max MP drinks a Tincture, and another if still under, with the
-- last one in the bag kept back the way the last four Tonics are; where
-- the item list offers a Tent -- a save point or the world map -- one is
-- pitched instead whenever a Tincture would otherwise be due; Elixirs are
-- never the field's to spend.  Reads and pad presses drive every visit;
-- the plans, the menu walk, each item's acceptance, the bag deltas and
-- the pools afterwards are the game's own, read back.
--
-- WHAT IS STAGED.  No shipped fixture arrives with a dry caster (the exit
-- contract ships parties whole, and a level-up refills the pool), and the
-- fixtures this ROM verifies were cut before the route buys a Tincture,
-- so each branch stages its own: one member's MP word, the party's HP
-- words where a branch needs a hole, and the item under test written into
-- an empty bag slot -- field_healpolicy's patient and field_zombiecure's
-- bit, one currency over.  Everything else is read.
--
-- Branches:
--   A. Under the band with Tinctures in the bag: two are drunk (the loop
--      picks again while still under), the third is the reserve, MP moves
--      by exactly the item's yield.
--   B. Reserved away (opts.reserve at the bag's count): nothing is spent,
--      the roster names the floor.                     (negative control)
--   C. opts.tincture = false: nothing is spent, "tinctures off".
--                                                       (negative control)
--   D. Off a save point (the hideout, $01BF clear) with a Tent in the bag,
--      the party hurt and one member dry: no Tent is planned; Tonics and a
--      Tincture do the work and the Tent count does not move.
--                                                       (negative control)
--   E. An Elixir in the bag and no Tincture: the Elixir is not touched and
--      the roster says what the bag would not offer.  (negative control)
--   F. On the Mt Kolts summit save point (map 103 (57,8), $01BF set by the
--      sparkle) with a dry member: the Tent is planned, accepted, the
--      menu leaves on its own, the tent event restores every pool.  Then,
--      from the same tile, the Tent reserved away: a Tincture is drunk
--      instead.                                          (negative control)
--   G. On the world map (Narshe's doorstep): the same Tent, through the
--      world module's own tent event.
local H = dofile("tools/tests/lib/ot6.lua")

local HIDEOUT = "build/states/returner_hideout.mss.lua"
local SUMMIT = "build/states/vargas_entry.mss.lua"
local WORLD = "build/states/worldmap_narshe.mss.lua"

local TONIC, TINCTURE, TENT, ELIXIR = 0xE8, 0xEB, 0xF7, 0xEE
local TINCTURE_MP = 50            -- item_prop +$14, the amount it restores

-- every line the lib logs, for assertions on what the visit said
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end
local function forget() lines = {} end

local function mpAddr(c) return 0x1600 + 37 * c + 13 end
local function hpAddr(c) return 0x1600 + 37 * c + 9 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- the party member with the biggest pool: the one whose band is widest
local function bigPool()
  local best, mx = nil, -1
  for _, c in ipairs(H.partyMembers()) do
    if H.charMaxMp(c) > mx then best, mx = c, H.charMaxMp(c) end
  end
  return best
end

-- staging: one MP word, the HP words, one bag slot
local function dryOut(c) H.writeWord(mpAddr(c), 0) end
local function hurtAll(frac)
  for _, c in ipairs(H.partyMembers()) do
    H.writeWord(hpAddr(c), math.floor(H.charMaxHp(c) * frac))
  end
end
local function stage(item, n)
  H.assertEq(H.invCountOf(item), 0,
    string.format("the fixture holds no $%02X of its own", item))
  for s = 0, 255 do
    if H.readByte(0x1869 + s) == 0xFF then
      H.writeByte(0x1869 + s, item)
      H.writeByte(0x1969 + s, n)
      H.assertEq(H.invCountOf(item), n,
        string.format("%d x $%02X staged into bag slot %d", n, item, s))
      return
    end
  end
  error("no empty bag slot to stage into", 0)
end

local function boot(sidecar, what)
  return H.seqStep({
    H.loadState(sidecar),
    H.waitFrames(30),
    H.waitUntil(function()
      if H.worldMode() then return H.worldHasControl() and H.worldAligned() end
      return H.hasControl()
    end, 600, what .. ": control", 5),
    H.call(forget),
  })
end

local function partyLine(what)
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  return string.format("[%s] %s | tonic=%d tincture=%d tent=%d elixir=%d $01BF=%d",
    what, table.concat(t, "  "), H.invCountOf(TONIC), H.invCountOf(TINCTURE),
    H.invCountOf(TENT), H.invCountOf(ELIXIR), sw(0x01BF))
end

local DRY = nil                   -- the staged member, resolved per boot

H.run({ maxFrames = 400000 }, {
  -- ---- A. the band ---------------------------------------------------------
  boot(HIDEOUT, "A"),
  H.call(function()
    H.assertEq(sw(0x01BF), 0, "the hideout is not a save point")
    DRY = bigPool()
    dryOut(DRY)
    stage(TINCTURE, 3)
    H.log(partyLine("A staged"))
  end),
  -- mpBand 0.7 so one Tincture (+50) leaves the widest pool still under it
  -- and the loop has to pick again; threshold 0.55 keeps the HP side out
  -- of the way (the fixture's party is above it)
  H.fieldCare({ tag = "A band", threshold = 0.55, mpBand = 0.7 }),
  H.call(function()
    H.log(partyLine("A after"))
    H.assertEq(said("plan: restore mp char " .. DRY .. " with $EB"), true,
      "the visit planned a Tincture for the dry member")
    H.assertEq(said("used $EB on char " .. DRY), true,
      "and the game accepted it")
    H.assertEq(H.invCountOf(TINCTURE), 1,
      "two of the three were drunk; the third is the reserve (M.CARE_RESERVE)")
    H.assertEq(H.charMp(DRY), math.min(H.charMaxMp(DRY), 2 * TINCTURE_MP),
      string.format("MP moved by exactly two Tinctures' yield (%d/%d)",
        H.charMp(DRY), H.charMaxMp(DRY)))
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "the menu is closed and the party has control back")
  end),

  -- ---- B. reserved away (negative control) ---------------------------------
  boot(HIDEOUT, "B"),
  H.call(function()
    dryOut(DRY)
    stage(TINCTURE, 3)
  end),
  H.fieldCare({ tag = "B reserved", threshold = 0.55,
    reserve = { [TONIC] = 4, [TINCTURE] = 3 } }),
  H.call(function()
    H.log(partyLine("B after"))
    H.assertEq(H.invCountOf(TINCTURE), 3, "nothing was spent under the reserve")
    H.assertEq(H.charMp(DRY), 0, "and the dry member stayed dry")
    H.assertEq(said("under the band"), true,
      "the roster names the member still under the band")
    H.assertEq(said("tincture 3 in the bag, floor 3"), true,
      "and the floor the bag would not go under")
    H.assertEq(H.hasControl() and H.tileAligned(), true, "control back")
  end),

  -- ---- C. the arm switched off (negative control) --------------------------
  boot(HIDEOUT, "C"),
  H.call(function()
    dryOut(DRY)
    stage(TINCTURE, 3)
  end),
  H.fieldCare({ tag = "C off", threshold = 0.55, tincture = false }),
  H.call(function()
    H.log(partyLine("C after"))
    H.assertEq(H.invCountOf(TINCTURE), 3, "nothing was spent with the arm off")
    H.assertEq(H.charMp(DRY), 0, "and the dry member stayed dry")
    H.assertEq(said("tinctures off"), true, "the roster says the arm is off")
  end),

  -- ---- D. off a save point: no Tent (negative control) ---------------------
  boot(HIDEOUT, "D"),
  H.call(function()
    H.assertEq(H.invCountOf(TENT) >= 1, true,
      "the hideout fixture carries the Tent from the shelf chest")
    dryOut(DRY)
    hurtAll(0.4)
    stage(TINCTURE, 3)
    H.log(partyLine("D staged"))
  end),
  H.fieldCare({ tag = "D no save point", threshold = 0.95, mpBand = 0.7 }),
  H.call(function()
    H.log(partyLine("D after"))
    H.assertEq(said("pitch a Tent"), false,
      "no Tent was planned off a save point (the item list would grey it)")
    H.assertEq(H.invCountOf(TENT), 1, "and the Tent count did not move")
    H.assertEq(said("used $E8 on char"), true, "the Tonics did the HP work")
    H.assertEq(said("used $EB on char " .. DRY), true, "and a Tincture the MP")
    H.assertEq(H.charMp(DRY) >= TINCTURE_MP, true, "the dry member is no longer dry")
  end),

  -- ---- E. an Elixir is not the field's to spend (negative control) ---------
  boot(HIDEOUT, "E"),
  H.call(function()
    dryOut(DRY)
    stage(ELIXIR, 1)
    H.assertEq(H.invCountOf(TINCTURE), 0, "no Tincture in the bag for this branch")
    H.log(partyLine("E staged"))
  end),
  H.fieldCare({ tag = "E elixir", threshold = 0.55 }),
  H.call(function()
    H.log(partyLine("E after"))
    H.assertEq(H.invCountOf(ELIXIR), 1, "the Elixir was not touched")
    H.assertEq(H.charMp(DRY), 0, "so the dry member stayed dry")
    H.assertEq(said("tincture 0 in the bag"), true,
      "and the roster names the Tincture the bag did not have")
    H.assertEq(said("with $EE"), false, "the Elixir was never even planned")
  end),

  -- ---- F. the summit save point: a Tent ------------------------------------
  boot(SUMMIT, "F"),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "vargas_entry boots on map 98")
  end),
  -- back through the ledge's door onto the summit (98 (10,10) -> 103 (59,9),
  -- the short-entrance table) and onto the save point
  H.navTo(10, 10, { maxFrames = 8000, playBattles = "tactical",
    arrive = function() return (H.mapId() & 0x1ff) == 103 end }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 103 and H.hasControl() and H.tileAligned()
  end, 1800, "F: the summit (map 103)", 5),
  H.navTo(57, 8, { maxFrames = 8000, playBattles = "tactical" }),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX() == 57 and H.fieldY() == 8, true, "F: on (57,8)")
    H.assertEq(sw(0x01BF), 1,
      "F: $01BF set -- the summit save point's sparkle ran, the item list offers a Tent")
    DRY = bigPool()
    dryOut(DRY)
    stage(TENT, 1)
    forget()
    H.log(partyLine("F staged"))
  end),
  H.fieldCare({ tag = "F summit", threshold = 0.55 }),
  H.call(function()
    H.log(partyLine("F after"))
    H.assertEq(said("plan: pitch a Tent"), true, "the visit planned the Tent")
    H.assertEq(said("pitched a Tent"), true,
      "and saw the tent event end with the party whole")
    H.assertEq(H.invCountOf(TENT), 0, "the Tent is gone")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c), H.charMaxHp(c), string.format("char %d at full HP", c))
      H.assertEq(H.charMp(c), H.charMaxMp(c), string.format("char %d at full MP", c))
    end
  end),
  -- On a save point tile the SavePoint script re-fires under the party
  -- every ~30 frames (probe_tent_summit), so control is a flicker there
  -- by the game's own doing: it is waited for, not read at an instant.
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 300,
    "F: the field is back after the tent event", 1),
  -- F2: the same tile, the Tent reserved away: the Tincture is the answer
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "F2: still on the save point")
    dryOut(DRY)
    stage(TENT, 1)
    stage(TINCTURE, 2)
    forget()
    H.log(partyLine("F2 staged"))
  end),
  H.fieldCare({ tag = "F2 tent reserved", threshold = 0.55,
    reserve = { [TONIC] = 4, [TINCTURE] = 1, [TENT] = 1 } }),
  H.call(function()
    H.log(partyLine("F2 after"))
    H.assertEq(said("pitch a Tent"), false, "no Tent under the reserve")
    H.assertEq(H.invCountOf(TENT), 1, "the Tent count did not move")
    H.assertEq(said("used $EB on char " .. DRY), true, "a Tincture was drunk instead")
    H.assertEq(H.invCountOf(TINCTURE), 1, "one drunk, one kept")
  end),

  -- ---- G. the world map: a Tent ---------------------------------------------
  boot(WORLD, "G"),
  H.call(function()
    H.assertEq(H.worldMode(), true, "worldmap_narshe is on the world map")
    DRY = bigPool()
    dryOut(DRY)
    stage(TENT, 1)
    H.log(partyLine("G staged"))
  end),
  H.fieldCare({ tag = "G world", threshold = 0.55 }),
  -- the world's tent event is a visit to map 3 and back (WorldTent_ext,
  -- event_main.asm): wait for the world module to have the party again
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "G: back on the world map after the tent", 20),
  H.call(function()
    H.log(partyLine("G after"))
    H.assertEq(said("plan: pitch a Tent"), true, "the visit planned the Tent on the world map")
    H.assertEq(said("pitched a Tent"), true, "and saw the world's tent event end")
    H.assertEq(H.invCountOf(TENT), 0, "the Tent is gone")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charMp(c), H.charMaxMp(c), string.format("char %d at full MP", c))
    end
    H.assertEq(H.worldHasControl() and H.worldAligned(), true,
      "the world is back after the tent event")
  end),
})

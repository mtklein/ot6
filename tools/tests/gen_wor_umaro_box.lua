-- gen_wor_umaro_box.lua -- a branch beside gen_wor_tritoch (#487, the monster boxes; wor-coverage.md section 12):
-- boot the graph's capture `wor_tritoch_cave` (CYAN, TERRA, CELES and MOG just dropped onto Umaro's cave's
-- landing, 281 (14,55)), walk off the floor's drops to 281 (9,52) -> 282 (16,32), the pocket below the drop that
-- the line's walk does not enter, and open the Pugs' box (282 (13,34), event group 152: three Pugs, L99, 14,001 HP
-- each, formation 235).  Its battle is an event battle and a game over when lost (TreasureMonster: _ca5ea9); the
-- runner retries from the boot.  The box is K.monsterBox (lib/ot6_field.lua): care to full and the arms against
-- the Pugs' absorbs before it, then its bit and its win asserted.  It pays no XP and no sure drop (each Pugs drops
-- a Minerva one time in eight, MonsterItems), so nothing boots what it leaves (the state `wor_umaro_box`).
-- Every battle's [outcome] is asserted said, judged on its own end reading, and paid as due.
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, CELES, MOG = 0, 2, 6, 10
local NAMES = { [0] = "TERRA", [1] = "LOCKE", [2] = "CYAN", [3] = "SHADOW", [4] = "EDGAR", [5] = "SABIN", [6] = "CELES",
  [7] = "STRAGO", [8] = "RELM", [9] = "SETZER", [10] = "MOG", [11] = "GAU", [12] = "GOGO", [13] = "UMARO" }
local MINERVA = 0x9C
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
local LINKS = {}
-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, lv, say, kitLine, watches, walk, settled = K.map, K.lv, K.say, K.kitLine, K.watches, K.walk, K.settled
local FOUR = { CYAN, TERRA, CELES, MOG }
-- the cave's floor drops (gen_wor_tritoch's), kept off the walk
local DROPS_281, DROPS_282 = { { 10, 54 }, { 11, 53 } }, { { 14, 30 }, { 33, 26 } }
local opened, minerva0 = {}, 0
local BOX = { x = 13, y = 34, bit = 170, form = 235, species = 0x0FF, what = "the Pugs' box (282 (13,34))",
  avoid = DROPS_282, done = function(line) opened[#opened + 1] = line end }

local seen, outcome0, battles0 = 0, 0, 0
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own end reading",
        what, i - outcome0, o.form & 0x3FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x3FF, o.kind))
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    seen = #H.outcomes
  end)
end

H.run({ maxFrames = 900000 }, {
  H.loadState("build/states/wor_tritoch_cave.mss.lua"),
  watches(),
  H.call(function()
    outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
    seen = outcome0
    minerva0 = H.invCountOf(MINERVA)
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 281, "the boot stands on Umaro's cave's landing (281): gen_wor_tritoch's capture wor_tritoch_cave")
    for _, ch in ipairs(FOUR) do
      H.assertEq(K.partyOf(ch), 1, NAMES[ch] .. " is seated (gen_wor_tritoch's four)")
    end
    H.assertEq(H.chestOpen(BOX.bit), false, BOX.what .. " is shut (bit " .. BOX.bit .. ")")
  end),
  -- @@setup-end
  walk(9, 52, "the landing -> 281 (9,52) -> 282 (16,32)", DROPS_281, function() return map() == 282 end),
  H.waitUntil(function() return map() == 282 and settled() end, 3000, "the pocket below the drop: control on 282", 1),
  checkOutcomes("the walk to the pocket below the drop"),
  K.monsterBox(BOX),
  checkOutcomes(BOX.what),
  H.call(function()
    H.log("[kit] " .. kitLine(FOUR))
    H.log(string.format("[box] Minervas in the bag: %d before the box, %d after", minerva0, H.invCountOf(MINERVA)))
    H.assertEq(#opened, 1, "the box opened and won")
  end),
  H.saveState("wor_umaro_box.mss"),
  H.logStep(function()
    return string.format("wor_umaro_box generated: map %d (%d,%d); CYAN L%d, TERRA L%d, CELES L%d, MOG L%d; box: %s",
      map(), H.fieldX(), H.fieldY(), lv(CYAN), lv(TERRA), lv(CELES), lv(MOG), table.concat(opened, "; "))
  end),
})

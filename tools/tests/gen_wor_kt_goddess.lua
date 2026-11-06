-- gen_wor_kt_goddess.lua -- Kefka's Tower, party 1 to the Goddess (docs/design/route-wor-kefka-tower.md sections 2,
-- 5 and 6): Continue the `wor-kt-poltergeist-v1` battery (party 2 on 412's save point; party 3 on Doom's, 355
-- (64,11); party 1 on the chamber's east plate; the cell doors open), then party 1 puts on the Ribbon party 2 left in
-- the bag (H.ribbonsOnSeated), goes down the east column to 337's east cell and through its door into 355's east
-- lane; its bench levels there (T.trainLap: the tower's own encounters; LAP_355 below); on through 291's east room to
-- 354 below the Goddess; dressed against her bolts (H.elementDress); the Goddess (354 (12,32): event battle 99, a
-- game over when lost: the runner retries from the save), and Save on the save point she guarded (354 (12,31)) with
-- party 1 standing: the `wor-kt-goddess-v1` battery.  The corridor above it leads to 411's right plate: party 1's
-- place at the convergence.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local GODDESS = 0x128
local GODDESS_SAVE = { 12, 31 }
local BOLT_ELEMENT = 0x04
local RIBBON = 0xCA
-- party 1's bench levels to TRAIN_LEVEL before the Goddess (route-wor-kefka-tower.md 6.1 and 6.3)
local TRAIN_LEVEL = KT_TRAIN or 46
-- where it laps: 355's east lane (pool group 220: the Scullion, three Innocs) or 354 below her (group 226: the
-- Madam and her Outsiders among four) (section 6.3)
local LAP_355 = KT_LAP355 ~= false
-- the tower's species whose vanilla weakness a player who knows the tower reads (gen_wor_kt_guardian's): 354's pool
-- deals formation 428 (the Madam with two Outsiders), which party 1 meets with Ultima, Pearl and Fire
local MACHINES = { [0x0FD] = true, [0x0D9] = true, [0x0EA] = true, [0x0ED] = true, [0x0F6] = true, [0x105] = true,
  [0x0FC] = true, [0x0A1] = true }
local FIRE, BOLT, PEARL = 0x00, 0x02, 0x0E
local OUTSIDER, ULTIMA = 0x0BD, 0x14
local FIGHT = {}
FIGHT.nuke = function()
  if H.formationHas({ [OUTSIDER] = true }) then return { ULTIMA, PEARL, FIRE } end
  if H.formationHas(MACHINES) then return { BOLT } end
  return nil
end
local BOSS_FIGHT = KT_BOSS_FIGHT or {}
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local door = T.door
local function train() return T.trainLap("party 1 " .. (LAP_355 and "in 355's east lane" or "below the Goddess"),
  TRAIN_LEVEL, { burn = KT_BURN, cap = KT_CAP }) end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("wor-kt-poltergeist-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (Doom and the Poltergeist beaten, the cell doors open) and where parties 1
  -- and 3 stand.  Asserted here: party 2 on 412's save point (gen_wor_kt_poltergeist; the contract's walking
  -- party), the Goddess not yet fought, and the Ribbon gen_wor_kt_poltergeist left in the bag for party 1.  Soft,
  -- fixed here: HP and MP (the care), the arms, the dress.
  H.call(function()
    say("tower", "boot")
    local m1, x1, y1 = H.partyWhere(1)
    H.assertEq(string.format("%d (%d,%d)", m1, x1, y1), "355 (43,6)", "party 1 on the chamber's east plate "
      .. "(gen_wor_kt_guardian)")
    H.assertEq(sw(0x0073), 0, "the Goddess not yet fought ($0073)")
    H.assertEq(H.invCountOf(RIBBON) >= 1, true, "a Ribbon in the bag for party 1 (gen_wor_kt_poltergeist hands "
      .. "334's on)")
  end),
  -- @@setup-end

  -- @@stage lane
  -- the bag's care stock is party 1's: parties 2 and 3 have only their walks to 411's plates left
  H.splitBegin({ shares = { [1] = 1, [2] = 0, [3] = 0 } }),
  H.switchParty(1),
  H.fieldCare({ threshold = 1.0, tag = "before the Ribbon" }),
  H.ribbonsOnSeated({ tag = "party 2's Ribbon onto party 1", noRegroup = true }),
  H.call(function()
    local n = 0
    for _, ch in ipairs(H.partyRoster(1)) do
      local b = 0x1600 + 37 * ch
      if H.readByte(b + 0x23) == RIBBON or H.readByte(b + 0x24) == RIBBON then n = n + 1 end
    end
    H.assertEq(n >= 2, true, "party 1 wears two Ribbons")
    say("tower", string.format("party 1 wears %d Ribbons", n))
  end),
  door(43, 18, 337, "party 1: the east column (43,18) -> 337's east cell (12,6)"),
  door(14, 5, 355, "party 1: the east cell's door (14,5) -> 355 (47,17)"),
  LAP_355 and train() or H.call(function() end),
  door(47, 8, 291, "party 1: 355 (47,8) -> 291 (18,15)"),
  door(18, 9, 354, "party 1: 291 (18,9) -> 354 (12,44)"),
  (not LAP_355) and train() or H.call(function() end),

  -- @@stage goddess
  -- the care first: the Equip menu refuses a fallen member
  H.fieldCare({ threshold = 1.0, tag = "before dressing for the Goddess" }),
  H.elementDress(BOLT_ELEMENT, { tag = "dress against the Goddess's bolts" }),
  H.absorbSafeArms(nil, { GODDESS }, { tag = "arms for the Goddess" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Goddess" }),
  H.call(function() say("boss", "party 1 before the Goddess: " .. H.partiesLine()) end),
  -- her trigger spans 354 (11..13,32) (_cc1716)
  H.navTo(12, 32, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, spare = { GODDESS },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [GODDESS] = true })) or H.fieldY() == 32
    end }),
  H.advanceStory(function() return sw(0x0073) == 1 and map() == 354 and settled() end, 300000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "the Goddess beaten") end),
  H.saveState("wor_kt_goddess_won.mss"),

  -- @@stage save
  -- Her Overcast turns a member who falls into a Zombie, and the field menu refuses Revivify on one (CheckCanUseItem):
  -- with one standing Zombied, party 1 meets a battle on her floor, where the driver's Revivify cures it, as a
  -- player does (route-wor-kefka-tower.md 6.3: "c9 0/3230 hp: zombie: revivify 57 in the bag, floor 0, refused")
  H.cond(function()
    for _, ch in ipairs(H.partyRoster(1)) do
      if (H.charStatus1(ch) & 0x02) ~= 0 then return true end
    end
    return false
  end, {
    H.call(function() say("tower", "a Zombie in party 1 after the Goddess: a battle on her floor to cure it") end),
    T.trainLap("party 1 cures its Zombie below the Goddess", 1, { min = 1, cap = 3 }),
    H.fieldCare({ threshold = 1.0, tag = "after the Zombie's battle" }),
    H.call(function()
      for _, ch in ipairs(H.partyRoster(1)) do
        H.assertEq((H.charStatus1(ch) & 0x02) == 0, true, NAMES[ch] .. " no longer a Zombie (the battle's Revivify)")
      end
    end),
  }, {}),
  H.stepOntoSavePoint(GODDESS_SAVE[1], GODDESS_SAVE[2]),
  H.fieldCare({ threshold = 1.0, tag = "on the Goddess's save point" }),
  H.call(function()
    say("tower", "on the Goddess's save point")
    for _, ch in ipairs(H.partyRoster(1)) do
      H.assertEq(H.charHp(ch) > 0, true, string.format("%s stands at the save (the care revives the fallen)",
        NAMES[ch]))
    end
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-kt-goddess-v1"),
  H.splitEnd(),
  H.saveState("wor_kt_goddess.mss"),
  H.logStep(function()
    return string.format("wor_kt_goddess generated: %s, saved in slot 3", H.partiesLine())
  end),
})

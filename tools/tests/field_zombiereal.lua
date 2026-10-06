-- @suite savestate=tomb_zombie
-- field_zombiereal.lua -- #316: field care cures a Zombie a battle really
-- left, measured from a real landing rather than a staged bit.
--
-- A zombied member walks out of a battle at 0 HP with status 1 $02 and no
-- Wound bit.  Care used to read that as "down", plan a Fenix Down, have the
-- game refuse it and give up: "REFUSED by the game: revive char 5 with $F0
-- (0/1225 hp, 211/239 mp, status1 02)", "nothing more can be done: c5
-- 0/1225 hp: down", with revivify=2 in the bag (the Black Drgn lab,
-- build/attempts/wt/black-drgn/ pair-final/k6_s0.log).  field_zombiecure's
-- branch D stages that state (HP word and status bit); this suite takes it
-- from play.
--
-- The fixture, tomb_zombie (gen_tomb_zombie), is the frame a Zombie lands on
-- a member in a battle in Darill's Tomb's grave room (the PowerDemon's Soul
-- Out or an Exoray's DoomPollen), with others standing.  Each branch fights
-- that battle out with the fight driver's in-battle Zombie cure switched off
-- (opts.zombieCure = false, the driver before #263) so the Zombie leaves the
-- battle as the game leaves it, then:
--   A. the step-form care (M.fieldCare): a Revivify is planned for the
--      zombie, the game accepts it, the bit clears; no Fenix Down is planned
--      for it and nothing is refused.
--   B. the same with every Revivify reserved away: nothing is spent on the
--      zombie, it stays zombied, and the roster names the Revivify floor --
--      never "down" or a Fenix Down.                  (negative control)
--   C. the navigators' own care after the battle (advanceStory's care stop,
--      the driver form M.newCareDriver): the same Revivify, unprompted.
-- The battle replays the same from the fixture (no inputs differ before it
-- ends), so all three branches meet the same zombie.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/tomb_zombie.mss.lua"
local REVIVIFY, FENIX = 0xF1, 0xF0
local ST1 = 0x3EE4

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

local Z, o0 = nil, nil          -- Z.char: the zombied member's character id

local function boot(what)
  return H.seqStep({
    H.loadState(STATE),
    H.call(function()
      lines = {}
      Z = nil
      H.assertEq(H.battleLoadStarted() and H.monstersPresent() > 0, true,
        what .. ": tomb_zombie stands in a battle")
      for e = 0, 3 do
        local s1 = H.readByte(ST1 + e * 2)
        if Z == nil and (s1 & 0x02) ~= 0 and (s1 & 0x80) == 0 and H.readWord(0x3C1C + e * 2) > 0 then
          Z = { e = e, char = H.readByte(0x3ED8 + e * 2) }
        end
      end
      H.assertEq(Z ~= nil, true, what .. ": a member stands Zombied (STATUS1 $02, no Wound)")
      o0 = #H.outcomes
    end),
  })
end

-- the battle fought out, the in-battle cure off; care after it on or off
local function fight(what, care)
  return H.seqStep({
    H.advanceStory(function() return #H.outcomes > o0 and H.hasControl() end, 50000,
      { playBattles = "tactical", care = care, fight = { zombieCure = false } }),
    H.call(function()
      local o = H.outcomes[o0 + 1]
      H.assertEq(o.kind, "won", what .. ": the battle was won")
      H.log(string.format("[zombiereal] %s: after the battle char %d reads %d/%d hp, status1 $%02X, " ..
        "revivify=%d fenix=%d", what, Z.char, H.charHp(Z.char), H.charMaxHp(Z.char),
        H.charStatus1(Z.char), H.invCountOf(REVIVIFY), H.invCountOf(FENIX)))
    end),
  })
end

local function carriedOut(what)
  H.assertEq(H.charStatus1(Z.char) & 0x82, 0x02, string.format(
    "%s: char %d walked out of the battle Zombied (status1 $%02X, no Wound)", what, Z.char,
    H.charStatus1(Z.char)))
end

local function cured(what, tag)
  H.assertEq(said(string.format("[%s] plan: cure zombie char %d with $F1", tag, Z.char)), true,
    what .. ": a Revivify was planned for the zombie")
  H.assertEq(said(string.format("[%s] used $F1 on char %d", tag, Z.char)), true,
    what .. ": and the game accepted it")
  H.assertEq(H.charStatus1(Z.char) & 0x02, 0, what .. ": the Zombie bit is clear")
  H.assertEq(said(string.format("char %d with $F0", Z.char)), false,
    what .. ": no Fenix Down was planned for the zombie")
  H.assertEq(said("REFUSED by the game"), false, what .. ": nothing was refused")
end

H.run({ maxFrames = 200000 }, {
  -- ---- A. the step form -----------------------------------------------------
  boot("A"),
  fight("A", false),
  H.call(function() carriedOut("A") end),
  H.fieldCare({ tag = "A care", threshold = 0.9 }),
  H.call(function() cured("A", "A care") end),

  -- ---- B. the Revivifies reserved away ---------------------------------------
  boot("B"),
  fight("B", false),
  H.call(function() carriedOut("B") end),
  H.fieldCare({ tag = "B care", threshold = 0.9,
    reserve = { [0xE8] = 4, [0xE9] = 4, [REVIVIFY] = 99 } }),
  H.call(function()
    H.assertEq(H.charStatus1(Z.char) & 0x02, 0x02, "B: the zombie stays zombied")
    H.assertEq(said(string.format("char %d with $F0", Z.char)), false,
      "B: no Fenix Down was planned for the zombie")
    H.assertEq(said("zombie: revivify"), true, "B: the roster names the Revivify floor")
    H.assertEq(said(string.format("c%d 0/", Z.char)) and said(": down;"), false,
      "B: the roster never calls the zombie down")
  end),

  -- ---- C. the navigators' own care stop after the battle ---------------------
  boot("C"),
  fight("C", true),
  H.call(function()
    H.assertEq(said(string.format("[care after battle (advanceStory)] used $F1 on char %d", Z.char)), true,
      "C: the care stop after the battle spent a Revivify on the zombie")
    H.assertEq(H.charStatus1(Z.char) & 0x02, 0, "C: the Zombie bit is clear")
  end),
})

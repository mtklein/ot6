-- @suite savestate=returner_hideout
-- field_menuopen.lua -- #332: the field menu helpers read "the main menu is
-- up" from the menu module, not from $26 alone.
--
-- $26 is the menu's state byte only while the menu module runs.  On a map
-- nothing keeps it: it holds whatever the last menu (or battle) left there,
-- and the re-cut of fire-out-v1 found it reading $05 and then $0F with the
-- party walkable after the Esper menu closed, so setRows' "field menu open"
-- was satisfied on the map, its LEFT presses walked the party and its row
-- assertion failed (9051b5f4, build/attempts/wt/recut/capture/
-- fire-out-v1.log).  The same bare `$26 == $05` read opened the step-form
-- care (M.fieldCare), the driver-form care (M.newCareDriver, which the
-- navigators' care stops and M.careStop run) and M.bagArrange.  They now
-- wait for M.mainMenuUp(): $26 == $05 while the menu module's NMI is the
-- one installed.
--
-- WHAT IS STAGED.  The stale byte is a fault the game produces only after
-- some menus, not on cue, so each branch writes $05 into $26 on the map
-- right before the helper runs (fault injection), and the HP hole the care
-- needs into one member's HP word (field_healpolicy's patient).  The menu
-- walk, the item's acceptance, the bag order and the party's tile
-- afterwards are the game's own, read back.
--
-- Branches (the Returners' hideout, a field map):
--   A. M.fieldCare with $26 staged: the menu really opens, the Tonic lands,
--      the party has not moved.
--   B. M.careStop (the driver form): the same.
--   C. M.bagArrange with $26 staged: the swap is made through the real
--      Item screen and the party has not moved.
--   D. Nothing staged, $26 whatever the fixture holds: A's visit, the same
--      result.                                         (control)
-- The mutant is main's lib before this change (the bare read), red on A-C.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/returner_hideout.mss.lua"
local TONIC = 0xE8

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

local function hpAddr(c) return 0x1600 + 37 * c + 9 end
local at, patient = nil, nil

local function boot(what)
  return H.seqStep({
    H.loadState(FIX),
    H.waitFrames(30),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
      600, what .. ": control", 5),
    H.call(function()
      lines = {}
      at = { H.fieldX(), H.fieldY(), H.mapId() }
      patient = H.partyMembers()[1]
      H.assertEq(H.invCountOf(TONIC) > 8, true, what .. ": Tonics in the bag")
    end),
  })
end

local function stage(what, hurt)
  return H.call(function()
    if hurt then
      H.writeWord(hpAddr(patient), H.charMaxHp(patient) // 4)
    end
    H.writeByte(0x26, 0x05)
    H.assertEq(H.readByte(0x26), 0x05, what .. ": $26 reads $05")
    H.assertEq(H.menuRunning(), false, what .. ": with no menu running")
    H.assertEq(H.hasControl(), true, what .. ": and the party walkable")
  end)
end

local function stayed(what)
  H.assertEq(H.fieldX() == at[1] and H.fieldY() == at[2] and H.mapId() == at[3], true,
    string.format("%s: the party is still on (%d,%d) map %d (now (%d,%d) map %d)",
      what, at[1], at[2], at[3], H.fieldX(), H.fieldY(), H.mapId()))
end

local function healed(what)
  H.assertEq(said("used $E8 on char " .. patient), true, what .. ": the Tonic landed")
  H.assertEq(H.charHp(patient) > H.charMaxHp(patient) // 4, true,
    what .. ": the patient's HP moved")
  stayed(what)
end

H.run({ maxFrames = 120000 }, {
  -- ---- A. the step form ----------------------------------------------------
  boot("A"),
  stage("A", true),
  H.fieldCare({ tag = "A step", threshold = 0.9, maxFrames = 6000 }),
  H.call(function() healed("A") end),

  -- ---- B. the driver form --------------------------------------------------
  boot("B"),
  stage("B", true),
  H.careStop("B driver", { threshold = 0.9 }),
  H.call(function() healed("B") end),

  -- ---- C. the bag order ----------------------------------------------------
  boot("C"),
  H.call(function()
    H.assertEq(H.invSlotOf(TONIC) ~= 0, true, "C: the Tonics are not already in slot 0")
  end),
  stage("C", false),
  H.bagArrange({ TONIC }, { tag = "C bag", maxFrames = 6000 }),
  H.call(function()
    H.assertEq(H.readByte(0x1869), TONIC, "C: the Tonics moved to slot 0")
    stayed("C")
  end),

  -- ---- D. control: nothing staged -----------------------------------------
  boot("D"),
  H.call(function() H.writeWord(hpAddr(patient), H.charMaxHp(patient) // 4) end),
  H.fieldCare({ tag = "D unstaged", threshold = 0.9, maxFrames = 6000 }),
  H.call(function() healed("D") end),
})

-- @suite frontier=kefka_doorstep
-- battle_kefka.lua -- FRONTIER-GATED gate for v0.3's stop-line boss: the
-- Battle for Narshe's KEFKA, fought for REAL from kefka_doorstep.mss
-- (party 1 = TERRA+EDGAR+CELES at (19,36), KEFKA one tile below --
-- gen_narshe_battle mints it; suite.sh adds this test when the fixture
-- exists and reports `skip` when it does not, the battle_vargas pattern).
--
-- What it asserts, and why each line is the one that matters:
--   1. battle 57 seeds formation 505: KEFKA_NARSHE $014A alone, gauge
--      6/6 and class row $03 = OT6_SLASH|OT6_PIERCE straight off
--      Ot6ShieldTbl (ot6.asm) -- the authored row, not the formula.
--   2. THE ELEMENT ADD IS LIVE.  His weak byte reads EXACTLY $09 =
--      fire|poison.  Vanilla KEFKA_NARSHE has NO weakness, so the whole
--      byte is Ot6ElemAddTbl's row -- this is the assertion that fails
--      if that row is dropped (battle_vargas's poison|holy $28, one boss
--      later).
--   3. BOTH CLASS AXES CHIP UNDER REAL INPUT.  Blind A/A picks FIGHT
--      with the default target every turn: CELES's sword is slash,
--      EDGAR's spear is pierce, so the gauge chips twice with revC
--      climbing $00 -> $01 -> $03 (measured f492/f661 on the spike twin,
--      probe_kefka_fight).  No skill is poked; the party is pinned
--      upright (Kefka hits hard and party HP is not what this is about).
--   4. THE SCRIPTED WIN TAKES IT.  Once both chips are in the log his
--      HP is floored (the vargas clamp idiom -- the gauge is never
--      poked) and the next real hit ends the fight through if_b_switch
--      $40 -> _ccbcb1: the party is NOT warped to the {25,5} lose-path
--      save point and the win scene owns the stage.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/kefka_doorstep.mss.lua"

local KEFKA = 0x014A

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local ks = -1
local function findKefka()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1
       and H.readWord(0x57c0 + s * 2) == KEFKA then return s end
  end
  return -1
end
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

H.run({ maxFrames = 40000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 22, "booted on map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "at (19,36), KEFKA's doorstep")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 (TERRA+EDGAR+CELES) active")
  end),
  -- activation: face down once, then CLEAN edge-A (a held direction
  -- starves CheckNPCs -- measured, probe_kefka_npc)
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "fight up", 10),
  H.waitFrames(150),

  H.call(function()
    ks = findKefka()
    H.assertEq(ks >= 0, true, "KEFKA_NARSHE $014A on the field (formation 505)")
    H.assertEq(H.readByte(SH(ks)), 6, "gauge seeds 6 (Ot6ShieldTbl $014A)")
    H.assertEq(H.readByte(SMX(ks)), 6, "gauge max 6")
    H.assertEq(H.readByte(WKC(ks)), 0x03,
      "class row $03 = OT6_SLASH|OT6_PIERCE")
    H.assertEq(H.readByte(WKE(ks)), 0x09,
      "weak byte EXACTLY $09 -- vanilla has none; the byte IS the ElemAdd row")
    H.assertEq(H.readByte(RVC(ks)), 0, "nothing revealed yet (classes)")
    H.assertEq(H.readByte(RVE(ks)), 0, "nothing revealed yet (elements)")
  end),

  -- the real fight: A/A every menu, both class chips demanded
  H.call(function() H.vars.bothChipped = false end),
  (function()
    local aPh, lastSh, lastRvc = 0, 6, 0
    return H.driveUntil(function()
      return not H.battleLoadStarted()
    end, 30000, {
      H.call(function()
        pinParty()
        aPh = (aPh + 1) % 8
        local sh, rvc = H.readByte(SH(ks)), H.readByte(RVC(ks))
        if sh ~= lastSh or rvc ~= lastRvc then
          H.log(string.format("[chip] f%d gauge %d->%d revC $%02X->$%02X hp=%d",
            H.frame, lastSh, sh, lastRvc, rvc, H.readWord(MHP(ks))))
          lastSh, lastRvc = sh, rvc
        end
        if not H.vars.bothChipped and sh <= 4 and rvc == 0x03 then
          H.vars.bothChipped = true
          H.log(string.format(
            "[fight] both axes chipped (gauge %d, revC $03) -- hp floored f%d",
            sh, H.frame))
          H.writeWord(MHP(ks), 1)
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the real Kefka fight")
  end)(),

  -- the win verdict: chips actually happened, and the WIN branch runs
  H.waitFrames(240),
  H.call(function()
    H.assertEq(H.vars.bothChipped, true,
      "BOTH class axes chipped and revealed before the fight ended")
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.assertEq(atSave, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(H.eventRunning() or H.dialogWaiting(), true,
      "the win scene owns the stage (_ccbcb1)")
    H.log(string.format("[verdict] win at f%d", H.frame))
  end),
})

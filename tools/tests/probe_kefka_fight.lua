-- probe_kefka_fight.lua -- SPIKE phase 5 (poked lineage): the REAL fight.
-- Boots spike_doorstep.mss, opens battle 57 with the proven clean-A
-- activation, and beats KEFKA with genuine pad input: every party menu
-- that opens gets A/A (= FIGHT, default enemy target), so CELES's sword
-- chips the SLASH class and EDGAR's spear chips PIERCE -- both bits of
-- the authored $03 row -- while the element row ($09, fire|poison) is
-- asserted at seed.  Once the gauge has visibly chipped and a class bit
-- is revealed, his HP is floored (battle_vargas's clamp idiom -- the
-- gauge is never poked) so the next real hit ends it through the
-- scripted if_b_switch $40 win.  This body is battle_kefka's core,
-- proven here before the suite test exists.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/spike_doorstep.mss.lua"

local KEFKA = 0x014A

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local ks = -1                           -- Kefka's monster slot
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
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "A into KEFKA"),
  H.waitUntil(function() return H.battleActive() end, 3000, "fight up", 10),
  H.waitFrames(150),
  H.call(function()
    ks = findKefka()
    H.assertEq(ks >= 0, true, "KEFKA $014A on the field")
    H.assertEq(H.readByte(SH(ks)), 6, "gauge seeds 6")
    H.assertEq(H.readByte(WKC(ks)), 0x03, "class row $03 (slash|pierce)")
    H.assertEq(H.readByte(WKE(ks)), 0x09,
      "weak byte EXACTLY $09 -- vanilla has no weakness; the byte IS the add")
    H.assertEq(H.readByte(RVC(ks)), 0, "nothing revealed yet")
  end),

  -- the fight: A-mash (FIGHT + default target), party pinned upright.
  -- Log every gauge/reveal change with the last-resolved skill $3410.
  (function()
    local aPh, lastSh, lastRvc, lastRve = 0, 6, 0, 0
    local floored = false
    return H.driveUntil(function()
      return not H.battleLoadStarted()
    end, 30000, {
      H.call(function()
        pinParty()
        aPh = (aPh + 1) % 8
        local sh, rvc, rve = H.readByte(SH(ks)), H.readByte(RVC(ks)),
                             H.readByte(RVE(ks))
        if sh ~= lastSh or rvc ~= lastRvc or rve ~= lastRve then
          H.log(string.format(
            "[chip] f%d gauge %d->%d revC $%02X->$%02X revE $%02X->$%02X " ..
            "lastSkill=$%02X hp=%d",
            H.frame, lastSh, sh, lastRvc, rvc, lastRve, rve,
            H.readByte(0x3410), H.readWord(MHP(ks))))
          lastSh, lastRvc, lastRve = sh, rvc, rve
        end
        -- once the runtime proof is in the log, floor his hp: the chips
        -- are real, the kill should not cost 25 more turns
        if not floored and sh <= 4 and rvc ~= 0 then
          floored = true
          H.writeWord(MHP(ks), 1)
          H.log(string.format("[fight] chips proven (gauge %d, revC $%02X) " ..
            "-- hp floored at f%d", sh, rvc, H.frame))
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the real Kefka fight")
  end)(),
  H.call(function()
    H.log(string.format("[fight] battle torn down f%d", H.frame))
  end),
  -- WIN vs LOSE discrimination: the lose path (_ccc8e7) warps the party
  -- to the {25,5} save point with 1 HP and returns control; the win path
  -- (_ccbcb1) keeps the event interpreter busy with the "I won't forget
  -- this!" scene.  ($0612 itself only clears deep in the esper tail --
  -- run 1 waited on the wrong signal.)
  H.waitFrames(240),
  H.call(function()
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.log(string.format("[verdict] f%d (%d,%d) ev=%s dlg=%s",
      H.frame, H.fieldX(), H.fieldY(), tostring(H.eventRunning()),
      tostring(H.dialogWaiting())))
    H.assertEq(atSave, false, "NOT at the save point -- the lose path did not run")
    H.assertEq(H.eventRunning() or H.dialogWaiting(), true,
      "the win scene owns the stage (_ccbcb1)")
  end),
  H.logStep(function()
    return string.format("real fight complete at f%d -- win path confirmed", H.frame)
  end),
})

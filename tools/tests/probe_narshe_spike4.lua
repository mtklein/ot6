-- probe_narshe_spike4.lua -- SPIKE phase 4 (poked lineage, never FRONTIER):
-- boots spike_doorstep.mss (party 1 at {19,36}, KEFKA one tile below) and
-- finishes the arc: activate _ccbca0 with the pattern probe_kefka_npc
-- proved (face down once, then CLEAN edge-A -- a held direction starves
-- CheckNPCs and the activation never fires), assert the OT6 seed on
-- battle 57, END it with the kill-bit (recording that the scripted
-- if_b_switch $40 win path accepts it), and ride _ccbcb1 + the esper
-- scene to the first controllable frame.  Mints spike_kefka_won.mss --
-- the poked twin of the state the honest chain will mint as v0.3's stop
-- line.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/spike_doorstep.mss.lua"

local KEFKA = 0x014A

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local function killBitAll()
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "doorstep boot: map 22")
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "doorstep boot: at (19,36)")
  end),
  -- face down (one tap -- Kefka's tile blocks the step, the facing sets),
  -- then clean edge-A until the event takes
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  (function()
    local pressing = false
    return H.driveUntil(function()
      return H.battleLoadStarted()
    end, 2000, {
      H.cond(function() return true end, {
        H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
      }),
    }, "edge-A into KEFKA -> battle 57")
  end)(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka fight up", 10),
  H.waitFrames(150),

  H.call(function()
    local ks = -1
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1
         and H.readWord(0x57c0 + s * 2) == KEFKA then ks = s end
    end
    H.assertEq(ks >= 0, true, "KEFKA_NARSHE $014A present (formation 505)")
    H.log(string.format(
      "[kefka] slot=%d hp=%d shields=%d/%d class=$%02X weak=$%02X revE=$%02X revC=$%02X",
      ks, H.readWord(MHP(ks)), H.readByte(SH(ks)), H.readByte(SMX(ks)),
      H.readByte(WKC(ks)), H.readByte(WKE(ks)),
      H.readByte(RVE(ks)), H.readByte(RVC(ks))))
    H.assertEq(H.readByte(SH(ks)), 6, "6 shields seeded (Ot6ShieldTbl $014A)")
    H.assertEq(H.readByte(SMX(ks)), 6, "gauge max 6")
    H.assertEq(H.readByte(WKC(ks)), 0x03,
      "class row OT6_SLASH|OT6_PIERCE ($03)")
    H.assertEq(H.readByte(WKE(ks)) & 0x09, 0x09,
      "weak elements carry the fire|poison add (Ot6ElemAddTbl $014A)")
    H.screenshot("spike_kefka_battle")
  end),

  -- kill-bit him down; the scripted finish must take the $40 win branch
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down (kill-bit)")
  end)(),
  H.logStep(function()
    return string.format("Kefka battle torn down at f%d; riding _ccbcb1", H.frame)
  end),

  -- the win tail: "I won't forget this!", raiders hidden, party re-formed
  -- to TERRA alone, map 23 esper scene, map 30 Arvis with STARTUP_EVENT.
  -- First calm controllable frame = the mint.
  (function()
    local cnt = 0
    return H.advanceStory(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted() and not H.worldMode()
      cnt = ok and cnt + 1 or 0
      return cnt >= 60
    end, 40000)
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0139), 1, "$0139 SET -- the battle-won latch")
    H.assertEq(sw(0x0612), 0, "$0612 clear -- KEFKA's NPC gone")
    H.assertEq(sw(0x061D), 0, "$061D clear -- raiders retired")
    H.log(string.format("[kefka_won] f%d map=%d (%d,%d) $0046=%d $01CE=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0046), sw(0x01CE)))
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("spike_kefka_won")
  end),
  H.saveState("spike_kefka_won.mss"),
  H.logStep(function()
    return string.format("spike 4 complete at f%d -- v0.3's stop line reached (poked twin)", H.frame)
  end),
})

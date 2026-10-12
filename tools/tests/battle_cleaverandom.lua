-- @suite savestate=cyan_defence slow
-- battle_cleaverandom.lua -- a random SwdTech never picks Cleave (v0.27).
--
-- Cleave (SwdTech tech 7, attack $5c) is Cyan's divine, and its one gate is
-- a full 3-BP boost (kits.md "Divines").  RandBushido (battle_main.asm)
-- picks a random known tech when Cyan acts on his own -- Muddled, Charmed,
-- at the Colosseum -- and spends no boost, so OT6 stops its range at tech
-- 6, Quadra Slice (Ot6RandBushidoTop, ot6_divine.asm).  Vanilla's range is
-- every tech known, 0..$2020.
--
-- Boots cyan_defence (a solo Cyan, L11, beside battle 43's two soldiers on
-- map 120) and engages the soldiers.  Declared unit-test expedients
-- (tools/state_write_waivers.txt), because Cleave is learned at L70 and no
-- generated battle Muddles Cyan on cue: the highest tech known ($2020) := 7
-- and the learned set ($1CF7) := all eight, MP := 999, both soldiers' HP :=
-- 30,000 (so his own techs do not end the battle before the picks are
-- counted), and Muddle ($3EE5 bit 5) set on him again whenever a hit
-- clears it.  Nothing else is touched: the command, the pick and the
-- attack are the engine's.
--
-- Watched: each RandBushido entry, and the bound RandA takes right after
-- it (A at RandA's entry: the number of techs the pick ranges over), and
-- every Ot6Oblivion entry with Cleave's attack id.  Asserted, over PICKS
-- random SwdTechs: every bound is 7 (techs 0..6), and no Cleave executed.
-- With Cleave in range (vanilla, or the cap removed) the bound is 8.
-- Old-ROM red and mutant: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_cleaverandom.out).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local CYAN, CLEAVE, PICKS = 0x02, 0x5C, 6
local KNOWN = 0x2020

local cyanSlot = nil
local pending, bounds, cleaves, armed = false, {}, 0, false

local function arm()
  local rb, ra = H.sym("RandBushido"), H.sym("RandA")
  emu.addMemoryCallback(function()
    if armed then pending = true end
  end, emu.callbackType.exec, rb, rb)
  emu.addMemoryCallback(function()
    if not pending then return end
    pending = false
    local n = emu.getState()["cpu.a"] & 0xFF
    bounds[#bounds + 1] = n
    H.log(string.format("[crand] f%d random SwdTech %d: RandA's bound %d ($2020 = %d)", H.frame, #bounds, n,
      H.readByte(KNOWN)))
  end, emu.callbackType.exec, ra, ra)
  local ob = H.sym("Ot6Oblivion")
  emu.addMemoryCallback(function()
    if not armed or H.readByte(0x3A7D) ~= CLEAVE then return end
    cleaves = cleaves + 1
    H.log(string.format("[crand] f%d a Cleave executed", H.frame))
  end, emu.callbackType.exec, ob, ob)
end

local function muddled() return (H.readByte(0x3EE5 + cyanSlot * 2) & 0x20) ~= 0 end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(arm),
  H.talkToObj(17, "the soldiers: engage", 20000),
  H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
    H.call(function() H.setPad(H.frame % 8 < 4 and { a = true } or {}) end),
  }, "the soldiers: battle starts"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 5),
  H.waitFrames(60),
  H.call(function()
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CYAN then cyanSlot = s end end
    H.assertEq(cyanSlot ~= nil, true, "CYAN is in this battle")
    H.writeWord(KNOWN, 7)
    H.writeByte(0x1CF7, 0xFF)
    H.writeWord(0x3C08 + cyanSlot * 2, 999)
    for m = 0, 5 do
      if (H.readByte(0x3AA8 + m * 2) & 1) == 1 then H.writeWord(0x3BFC + m * 2, 30000) end
    end
    H.log("[crand] staged: $2020 := 7, $1CF7 := all eight, MP := 999, soldiers' HP := 30000 (declared expedients)")
    armed = true
  end),
  H.driveUntil(function() return #bounds >= PICKS or not H.battleLoadStarted() end, 90000, {
    H.call(function()
      if H.battleActive() and not muddled() and (H.readByte(0x3EE4 + cyanSlot * 2) & 0xC2) == 0 then
        H.writeByte(0x3EE5 + cyanSlot * 2, H.readByte(0x3EE5 + cyanSlot * 2) | 0x20)
      end
      H.setPad(H.frame % 8 < 4 and { a = true } or {})   -- the menus Muddle leaves him: none; dialogs: A
    end),
  }, "PICKS random SwdTechs"),
  H.call(function()
    H.setPad({})
    H.log(string.format("[crand] %d random SwdTech(s), bounds %s; %d Cleave(s)", #bounds,
      table.concat(bounds, ","), cleaves))
    H.assertEq(#bounds >= PICKS, true, string.format("%d random SwdTechs were picked", PICKS))
    for i, n in ipairs(bounds) do
      H.assertEq(n, 7, string.format("random SwdTech %d ranged over techs 0..6 (Cleave, tech 7, out of reach)", i))
    end
    H.assertEq(cleaves, 0, "no Cleave executed")
    H.log("[crand] PASS: a random SwdTech never reaches Cleave")
  end),
})

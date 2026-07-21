-- @suite slow
-- battle_reveal_poweron.lua -- the dirty-RAM, fresh-battle reveal gate.
-- Reproduces the USER'S condition (RamPowerOnState != AllZeros) that a
-- savestate-loading test structurally cannot: it boots from POWER-ON -- no
-- state load, because a state restores the RAM it was minted with (AllZeros)
-- and the fill never reaches battle init -- into the intro Guard fight, and
-- asserts a fresh, never-chipped enemy shows '?'.
--
-- suite.sh runs this under OT6_RAM_POWERON=AllOnes (deterministic AND dirty).
-- The codex is WIPED here so it cannot be a reveal source: this isolates the
-- RAM/clear path. (A POPULATED codex legitimately pre-reveals learned
-- weaknesses on any battle including the first -- that persistence is by
-- design, covered by battle_codex; it is NOT what this gate is about.)
--
-- Complements battle_reveal, which pokes the masks at SEED entry (AFTER
-- InitBattle's clear) to exercise the seed's own zeroing / Cmd_20 reload path.
-- THIS test lets the power-on fill flow through InitBattle's clear untouched:
-- the seed-entry snapshot reads 0 because InitBattle cleared the dirt (a live
-- write-trace showed its clear storing $00 to these bytes before the seed),
-- and the fresh enemy draws '?'.
--
-- Monster slot s -> entity $08+2s: revealed elems $3e91+2s, revealed classes
-- $3ea5+2s, broken timer $3e90+2s, class-weak $3ea4+2s. HUD row s at $5762+14s,
-- weakness cells low byte +6/+8/+10/+12 ('?' = $BF, blank = $FF/$00).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function present(slot) return (H.readByte(0x3aa8 + slot * 2) & 1) == 1 end
local function wcell(slot, k) return H.readByte(H.shadowLine(slot) + 6 + k * 2) end

-- Snapshot every monster reveal mask at the FIRST seed entry ($F00000): AFTER
-- InitBattle's clear, BEFORE any seed zeroing. Under the AllOnes fill these
-- read 0 iff InitBattle's clear actually covers the mask bytes.
local seedRef, snap = nil, nil
local function armSeedSnapshot()
  seedRef = emu.addMemoryCallback(function()
    if snap then return end
    snap = { e = {}, c = {} }
    for slot = 0, 5 do
      snap.e[slot] = emu.read(0x3e91 + slot * 2, emu.memType.snesWorkRam)
      snap.c[slot] = emu.read(0x3ea5 + slot * 2, emu.memType.snesWorkRam)
    end
    emu.removeMemoryCallback(seedRef, emu.callbackType.exec, 0xF00000, 0xF00000)
  end, emu.callbackType.exec, 0xF00000, 0xF00000)
end

H.run({ maxFrames = 70000 }, {
  H.call(function()
    armSeedSnapshot()
    emu.write(0x316000, 0, emu.memType.snesMemory)   -- wipe codex magic:
    emu.write(0x316001, 0, emu.memType.snesMemory)   --   no learned reveals
  end),

  H.waitFrames(355),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.logStep("title handled; waiting out the opening..."),
  H.waitUntil(function() return H.frame >= 15400 end, 16000, "intro to finish"),
  H.call(function()   -- re-wipe just before the fight, in case boot touched sram
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),

  H.driveUntil(function() return H.battleLoadStarted() end, 24000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "first battle load"),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    -- 1. InitBattle's clear zeroed the dirty masks before the seed ran.
    H.assertEq(snap ~= nil, true, "seed entry fired (a monster was seeded)")
    for slot = 0, 5 do
      H.assertEq(snap.e[slot], 0,
        "seed-entry revealed-elements 0 (InitBattle cleared dirty RAM), slot "..slot)
      H.assertEq(snap.c[slot], 0,
        "seed-entry revealed-classes 0 (InitBattle cleared dirty RAM), slot "..slot)
    end

    -- 2. A fresh, never-chipped, not-in-codex enemy draws '?', not a glyph.
    local checked = 0
    for slot = 0, 5 do
      if present(slot) then
        local relm = H.readByte(0x3e91 + slot * 2)
        local rcls = H.readByte(0x3ea5 + slot * 2)
        H.log(string.format("slot%d sp=%04X revE=%02X revC=%02X cells=%02X,%02X,%02X,%02X",
          slot, H.readWord(0x57c0 + slot * 2), relm, rcls,
          wcell(slot, 0), wcell(slot, 1), wcell(slot, 2), wcell(slot, 3)))
        H.assertEq(relm, 0, "slot "..slot.." revealed-elements hidden on fresh dirty-RAM battle")
        H.assertEq(rcls, 0, "slot "..slot.." revealed-classes hidden on fresh dirty-RAM battle")
        for k = 0, 3 do
          local g = wcell(slot, k)
          H.assertEq(g == 0xBF or g == 0xFF or g == 0x00, true,
            string.format("slot %d cell %d is '?'/blank, not a leaked glyph (got %02X)", slot, k, g))
        end
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one fresh enemy on screen")
    H.screenshot("reveal_poweron_hidden")
  end),
})

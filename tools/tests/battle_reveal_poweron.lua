-- @suite slow
-- battle_reveal_poweron.lua -- the dirty-RAM, fresh-battle reveal test.
-- Reproduces the user's condition (RamPowerOnState != AllZeros) that a
-- savestate-loading test cannot: it boots from power-on, with no state load,
-- because a state restores the RAM it was generated with (AllZeros) and the
-- fill never reaches battle init.  It boots into the intro Guard fight and
-- asserts a fresh, never-chipped enemy shows '?'.
--
-- suite.sh runs this under OT6_RAM_POWERON=AllOnes (deterministic and dirty)
-- and OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1.  Issue #75
-- conversion: the SRAM save used to be forged, with slot 1's codex hand-stamped
-- 'O8' so all 384 species knew everything, and the transient page's
-- magic zeroed to force the invalid path.  It is now a tracked
-- checkpoint (an SRAM save written by the game's own Save UI on
-- the input-driven chain, provenance in its manifest), whose slot 3 carries an
-- earned codex page and whose transient page arrives valid with the
-- pre-save chain's knowledge still in it.  That valid stale transient is
-- the closer match to the real-world hazard: it is what a cartridge holds after
-- someone plays a New Game without saving and powers off.  New Game must
-- (a) leave the saved slot's knowledge untouched, and (b) wipe the stale
-- transient page (Ot6CodexNewGame, ot6_codex.asm) so an unsaved game
-- cannot inherit knowledge from either source.  Both are asserted against
-- byte-level snapshots of the checkpoint's content, using reads rather than
-- writes.
--
-- (The old staging populated slot 1 specifically.  Nothing in the claim
-- needs slot 1: "the persistent page survives and is not consulted" is
-- slot-agnostic, and the checkpoint's slot 3 pins it against real bytes.)
--
-- Which checkpoint is not free, and post-opera-v1 was the wrong one.  Both
-- positive controls below need a page with something in it, and measured
-- 2026-08-13 post-opera-v1's slot-3 and transient pages hold the 'O8' magic
-- and nothing else: 0 knowledge bytes in each, against 2 to 13 in every
-- other tracked battery.  That is not a codex that fails to record --
-- blackjack.mss, the state post-opera-v1 was cut from, carries 48 knowledge
-- bytes in its own transient page today -- it is a battery cut on
-- 2026-08-10 from an older blackjack whose page was empty, and whose
-- manifest still binds an ancestor hash the tree no longer has.  Nothing in
-- `make test` checks a checkpoint's ancestor binding, so it went unreported.
-- terra-returned-v1 carries 11 bytes in slot 3 and 2 in the transient page,
-- is the same slot and the same persistent_layout, and is already
-- cold-booted by battle_slots and battle_slotsboot.
--
-- This complements battle_reveal, which pokes the masks at seed entry, after
-- InitBattle's clear, to exercise the seed's own zeroing and the Cmd_20 reload
-- path.  This test lets the power-on fill flow through InitBattle's clear
-- untouched: the seed-entry snapshot reads 0 because InitBattle cleared
-- the dirt (a live write-trace showed its clear storing $00 to these bytes
-- before the seed), and the fresh enemy draws '?'.
--
-- Boot drive, measured: with a valid SRAM save the title no longer skips the
-- select screen, and Start lands on the load menu (ZMENUSTATE $21, cursor
-- $4b) showing New Game / Empty / Empty / the checkpoint's slot-3 save, with
-- the cursor preselecting the saved slot (row 3).  Up edges walk it to
-- row 0 = New Game, A commits, and Ot6CodexNewGame's wipe is observable
-- in SRAM as soon as it runs.
--
-- Monster slot s -> entity $08+2s: revealed elems $3e91+2s, revealed classes
-- $3ea5+2s, broken timer $3e90+2s, class-weak $3ea4+2s. HUD row s at $5762+14s,
-- weakness cells low byte +6/+8/+10/+12 ('?' = $BF, blank = $FF/$00).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local SLOT3, TEMP = 0x316800, 0x316C00  -- codex pages (root $316000 + $400*n)
local PAGE_USED = 0x310                 -- magic + elem@$10 + class@$190

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function present(slot) return (H.readByte(0x3aa8 + slot * 2) & 1) == 1 end
local function wcell(slot, k) return H.readByte(H.shadowLine(slot) + 6 + k * 2) end

-- Snapshot every monster reveal mask at the first seed entry, after
-- InitBattle's clear and before any seed zeroing. Under the AllOnes fill these
-- read 0 iff InitBattle's clear covers the mask bytes.
local SEED = H.sym("Ot6SeedShields")
local seedRef, snap = nil, nil
local function armSeedSnapshot()
  seedRef = emu.addMemoryCallback(function()
    if snap then return end
    snap = { e = {}, c = {} }
    for slot = 0, 5 do
      snap.e[slot] = emu.read(0x3e91 + slot * 2, emu.memType.snesWorkRam)
      snap.c[slot] = emu.read(0x3ea5 + slot * 2, emu.memType.snesWorkRam)
    end
    emu.removeMemoryCallback(seedRef, emu.callbackType.exec, SEED, SEED)
  end, emu.callbackType.exec, SEED, SEED)
end

local slot3Boot = nil                   -- the checkpoint page, byte for byte

H.run({ maxFrames = 70000 }, {
  H.call(function()
    armSeedSnapshot()
    -- The checkpoint's content, read and latched.  The forged staging this
    -- replaces could not fail; these positive controls can.
    H.assertEq(sram(SLOT3), 0x4f, "checkpoint slot-3 codex magic 'O'")
    H.assertEq(sram(SLOT3 + 1), 0x38, "checkpoint slot-3 codex magic '8'")
    H.assertEq(sram(TEMP), 0x4f, "checkpoint transient codex magic 'O' (VALID)")
    H.assertEq(sram(TEMP + 1), 0x38, "checkpoint transient codex magic '8'")
    local s3n, tn = 0, 0
    slot3Boot = {}
    for off = 0, PAGE_USED - 1 do
      slot3Boot[off] = sram(SLOT3 + off)
      if off >= 0x10 and slot3Boot[off] ~= 0 then s3n = s3n + 1 end
      if off >= 0x10 and sram(TEMP + off) ~= 0 then tn = tn + 1 end
    end
    H.log(string.format("[poweron] checkpoint knowledge: slot3 %d byte(s), " ..
      "stale transient %d byte(s)", s3n, tn))
    H.assertEq(s3n > 0, true,
      "positive control: the checkpoint's slot-3 page carries earned knowledge")
    H.assertEq(tn > 0, true,
      "positive control: the checkpoint's STALE transient page carries " ..
      "knowledge for New Game to wipe (the real-world unsaved-reset case)")
  end),

  H.waitFrames(355),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  -- with an SRAM save present the title leads to the load menu, but only
  -- an A press brings it up once the title settles (measured three ways:
  -- the menu reaches ZMENUSTATE $21 ~366 frames after an A; five Starts
  -- plus 1800 idle frames never reach it; Start edges every 128 frames
  -- never reach it either).  Press A edges, spaced so at most one
  -- stray lands in the menu fade; the cursor walk below asserts $21 in
  -- its own predicate, so a stray press that confirmed the saved slot
  -- fails instead of continuing into a Continue.
  H.driveUntil(function() return H.readByte(0x26) == 0x21 end, 3600, {
    H.pressButtons({ "a" }, 8), H.waitFrames(160),
  }, "load menu (ZMENUSTATE $21)"),
  -- walk the cursor to row 0 = New Game (measured: it preselects the
  -- checkpoint's saved slot, row 3) and commit
  H.driveUntil(function()
    return H.readByte(0x26) == 0x21 and H.readByte(0x4b) == 0
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "load-menu cursor on New Game"),
  H.pressButtons({ "a" }, 6),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0x021f), 0, "New Game selected transient codex")
    -- (a) the saved slot's page survives New Game untouched, byte for byte
    for off = 0, PAGE_USED - 1 do
      H.assertEq(sram(SLOT3 + off), slot3Boot[off],
        string.format("New Game preserved the checkpoint's slot-3 page (+%03X)",
          off))
    end
    -- (b) the stale valid transient page was wiped rather than inherited:
    -- Ot6CodexNewGame's signature is magic 'O8' over all-zero content
    H.assertEq(sram(TEMP), 0x4f, "New Game re-stamped transient magic 'O'")
    H.assertEq(sram(TEMP + 1), 0x38, "New Game re-stamped transient magic '8'")
    for off = 0x10, PAGE_USED - 1 do
      H.assertEq(sram(TEMP + off), 0, string.format(
        "New Game WIPED the stale transient knowledge (+%03X)", off))
    end
  end),

  H.logStep("New Game committed; waiting out the opening..."),
  H.waitUntil(function() return H.frame >= 16800 end, 18000, "intro to finish"),
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

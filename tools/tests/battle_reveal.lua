-- battle_reveal.lua -- the reveal-gate regression test. Guards against the
-- GUI bug where every enemy weakness icon showed REVEALED from battle start
-- instead of '?'.
--
-- Root cause: Ot6SeedShields OR's the persistent codex into the reveal masks
-- $3e89 (elements) / $3e9d (classes) but relied on the CALLER having zeroed
-- them. InitBattle's $3a20-$3ed3 clear does that for a normal battle, so the
-- AllZeros harness (and any normal fight) never saw the leak -- but the Cmd_20
-- scene-change reload (multi-phase bosses / reinforcements, AI cmd $f2) re-runs
-- the seed with NO such clear, and real uninitialized RAM would too. The seed
-- now zeroes the masks itself before the codex merge.
--
-- This test EXERCISES that exact dirty condition regardless of RAM power-on
-- state: a one-shot exec callback at Ot6SeedShields ($F00000) re-dirties every
-- monster reveal mask to $FF the instant the seed starts, AFTER InitBattle's
-- clear -- the same bytes the Cmd_20 reload hands over stale. The assertion is
-- deterministic (it holds for ANY garbage): a virgin-codex, un-chipped enemy
-- must show '?'. Then a real fire chip must still reveal, proving the fix
-- didn't just blanket-hide everything.
--
-- Guards sit in monster slots 2/3 -> entity $0C/$0E. revealed elems
-- $3E95/$3E97, weak elems $3BEC/$3BEE, HP $3C00/$3C02, party levels $3B18+2i,
-- mag.pwr $3B41+2i. HUD shadow line for slot s is at $5762 + s*14; the four
-- weakness cells are the low bytes at +6/+8/+10/+12 ('?' = $BF, fire = $EB).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function present(slot) return (H.readByte(0x3aa8 + slot * 2) & 1) == 1 end
local function wcell(slot, k) return H.readByte(0x5762 + slot * 14 + 6 + k * 2) end  -- k=0..3

-- One-shot: the instant the seed begins, re-dirty every monster reveal mask.
-- This is the state the Cmd_20 reload (and uninitialized RAM) hands the seed;
-- InitBattle's clear has already run, so a correct seed must re-hide these.
local seedRef
local function armSeedDirtier()
  local fired = false
  seedRef = emu.addMemoryCallback(function()
    if fired then return end
    fired = true
    for slot = 0, 5 do
      emu.write(0x3e91 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- revealed elems
      emu.write(0x3ea5 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- revealed classes
      emu.write(0x3e90 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- broken timer
      emu.write(0x3ea4 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- class-weak mask
    end
    emu.removeMemoryCallback(seedRef, emu.callbackType.exec, 0xF00000, 0xF00000)
  end, emu.callbackType.exec, 0xF00000, 0xF00000)
end

H.run({ maxFrames = 45000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() armSeedDirtier(); H.log("armed seed-entry mask dirtier at $F00000") end),

  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  -- 1. THE GATE: garbage was handed to the seed and the codex is virgin, so
  -- every un-chipped weakness must still read hidden and draw '?'.
  H.call(function()
    local checked = 0
    for slot = 0, 5 do
      if present(slot) then
        local sp   = H.readWord(0x57c0 + slot * 2)
        local relm = H.readByte(0x3e91 + slot * 2)
        local rcls = H.readByte(0x3ea5 + slot * 2)
        local brk  = H.readByte(0x3e90 + slot * 2)  -- broken timer ($3e88+8)
        local clsW = H.readByte(0x3ea4 + slot * 2)  -- class-weak mask ($3e9c+8)
        H.log(string.format("slot%d sp=%d revE=%02X revC=%02X brk=%02X clsW=%02X cells=%02X,%02X,%02X,%02X",
          slot, sp, relm, rcls, brk, clsW,
          wcell(slot, 0), wcell(slot, 1), wcell(slot, 2), wcell(slot, 3)))
        H.assertEq(relm, 0, "slot "..slot.." revealed-elements hidden despite seed garbage")
        H.assertEq(rcls, 0, "slot "..slot.." revealed-classes hidden despite seed garbage")
        -- broken timer ($3e88): the seed now clears it, so a monster handed
        -- $FF at seed (as a Cmd_20 reload would) must NOT start BROKEN.
        H.assertEq(brk, 0, "slot "..slot.." broken timer cleared (not broken) despite seed garbage")
        -- class-weak mask ($3e9c): the $FF must be REPLACED, never OR'd, by the
        -- seed's authoritative value -- else the hud draws phantom class cells.
        -- The doorstep Guards are AUTHORED (species 0, class PIERCE $02): the
        -- @hit path OVERWRITES, so it lands exactly $02 over the $FF (confirming
        -- overwrite-not-OR). A formula species would land 0 via the @formula
        -- clear; no formula species is reachable in this fixture, but the clear
        -- is the same lda#0/sta idiom the reveal masks above exercise.
        H.assertEq(clsW ~= 0xFF, true, "slot "..slot.." class-weak mask replaced, not OR'd (got FF)")
        if sp == 0 then
          H.assertEq(clsW, 0x02, "slot "..slot.." authored Guard class-weak overwritten to PIERCE $02")
        end
        for k = 0, 3 do
          local g = wcell(slot, k)
          -- a drawn weakness cell must be '?' ($BF) or blank ($FF/$00); a real
          -- element/class glyph here would be a leaked reveal
          H.assertEq(g == 0xBF or g == 0xFF or g == 0x00, true,
            string.format("slot %d weakness cell %d shows '?'/blank (got %02X)", slot, k, g))
        end
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one monster on screen to check")
    H.screenshot("reveal_gate_hidden")
  end),

  -- 2. THE REVEAL still works: fire-chip a guard and watch its fire weakness
  -- flip from '?' to the fire glyph. Guards carry no natural fire weak, so poke
  -- one; equalize casters + toughen HP like battle_break for a clean chip.
  H.call(function()
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    H.writeWord(0x3C00, 4000); H.writeWord(0x3C02, 4000)
    for c = 0, 2 do
      H.writeByte(0x3B18 + c * 2, 5)
      H.writeByte(0x3B41 + c * 2, 10)
    end
    H.log("lab: guards fire-weak + tough, casters equalized")
  end),
  H.driveUntil(function()
    return (H.readByte(0x3E95) & 1) == 1 or (H.readByte(0x3E97) & 1) == 1
  end, 30000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "a fire chip to reveal fire"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local r2, r3 = H.readByte(0x3E95), H.readByte(0x3E97)
    H.assertEq((r2 | r3) & 0x01, 0x01, "fire weakness revealed after the chip")
    local guard = ((r2 & 1) == 1) and 2 or 3
    local drewFire = false
    for k = 0, 3 do if wcell(guard, k) == 0xEB then drewFire = true end end
    H.assertEq(drewFire, true, "chipped guard's HUD row shows the fire glyph, not '?'")
    H.screenshot("reveal_gate_chipped")
  end),
})

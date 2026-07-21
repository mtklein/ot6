-- @suite slow
-- battle_break.lua -- THE M1 acceptance test: chip -> break -> recover, live.
--
--   tools/tests/run.sh tools/tests/battle_break.lua
--
-- Guards have no natural elemental weakness, so this test makes its own
-- laboratory: walk into the first guard battle fresh, then poke both guards
-- fire-weak ($3BE0|=$01) and tough (HP 4000) so they survive chipping. The
-- party's casting stats are pinned equal so every Fire Beam carries the
-- same base damage no matter whose menu fired it. Terra then spams Fire
-- Beam at the default target until a break is observed, while a per-frame
-- HP watcher records every discrete drop with the target's broken state.
--
-- Asserts, in order:
--   1. shields seed at 2/2 (from monster level)
--   2. a fire hit chips the target's shield and reveals the fire weakness
--      (mask $01 in $3E95/$3E97)
--   3. shields reach 0 -> broken timer nonzero
--   3b. THE BROKEN X2 FOR A FLAGS3-$20 ATTACK: Fire Beam carries flags3
--      $20 (can't dodge), and the old whole-byte $f2 gate silently denied
--      it the broken double. The breaking hit lands with the timer already
--      set, so its recorded drop must be ~4x the first (unbroken) chip's
--      drop on the same guard: the first chip is elemental-weak x2 THEN
--      shielded-resistance x0.5 (guards are authored 2-shield species, so
--      Ot6ShieldedDmg attenuates while their shields hold) = ~1x base,
--      while the breaking hit's chip empties the shields BEFORE the damage
--      tail runs, so it collects weak x2 AND broken x2 unattenuated = ~4x
--      base. Bounded 3x-6x (vanilla's 224..255/256 damage spread keeps the
--      true ratio inside [3.51, 4.55]; measured live: 134 -> 536B).
--   4. the broken timer expires -> shields restore to max, revealed mask
--      SURVIVES recovery
--
-- Entity map for this fight: guards in monster slots 2/3 -> entity offsets
-- $0C/$0E. shields $3E44/$3E46 - timers $3E94/$3E96 - revealed $3E95/$3E97
-- - weak elems $3BEC/$3BEE - HP $3C00/$3C02. party levels $3B18+2i,
-- mag.pwr $3B41+2i.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function shields() return H.readByte(0x3E44), H.readByte(0x3E46) end
local function timers() return H.readByte(0x3E94), H.readByte(0x3E96) end
local function revealed() return H.readByte(0x3E95), H.readByte(0x3E97) end

local function report(tag)
  return H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local r1, r2 = revealed()
    H.log(string.format(
      "%s shields=%d,%d timers=%02X,%02X revealed=%02X,%02X hp=%04X,%04X",
      tag, s1, s2, t1, t2, r1, r2,
      H.readWord(0x3C00), H.readWord(0x3C02)))
  end)
end

-- per-frame HP watcher: every discrete drop on a guard is recorded with
-- that guard's broken-timer state at observation time. the breaking hit's
-- damage is computed in the same CalcTargetDmg call that sets the timer
-- (chip runs before the broken-double join), and the HP write lands
-- frames later during the animation -- so a drop observed with the timer
-- up IS a hit that ran the broken-double path.
local drops = { [1] = {}, [2] = {} }
local prevHp = {}
local function sampleDrops()
  local hp = { H.readWord(0x3C00), H.readWord(0x3C02) }
  local t = { H.readByte(0x3E94), H.readByte(0x3E96) }
  for g = 1, 2 do
    if prevHp[g] ~= nil and hp[g] < prevHp[g] then
      local d = prevHp[g] - hp[g]
      drops[g][#drops[g] + 1] = { d = d, broken = t[g] ~= 0 }
      H.log(string.format("hp drop: guard %d -%d (timer %02X)", g, d, t[g]))
    end
    prevHp[g] = hp[g]
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),

  H.waitUntil(function() return H.battleActive() end, 900,
    "battle active", 30),
  -- input during the first window-open animation wedges the battle menu
  -- (reproduced on a pristine vanilla-hooks build): settle well past it
  H.waitFrames(240),

  -- 1. seeding
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1, 2, "guard 1 shields seeded")
    H.assertEq(s2, 2, "guard 2 shields seeded")
  end),
  report("seeded"),

  -- lab setup: fire-weak, tough guards, uniform casters. 4000 hp because
  -- the breaking hit now carries elemental x2 AND broken x2; equalized
  -- level/mag.pwr make the drop-ratio assert caster-independent.
  H.call(function()
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    H.writeWord(0x3C00, 4000)
    H.writeWord(0x3C02, 4000)
    for c = 0, 2 do
      H.writeByte(0x3B18 + c * 2, 5)   -- level
      H.writeByte(0x3B41 + c * 2, 10)  -- mag.pwr
    end
    H.log("lab: guards fire-weak, hp 4000, party level 5 / mag 10")
  end),

  -- 2+3. spam Fire Beam until something breaks (watcher rides the pred)
  H.driveUntil(function()
    sampleDrops()
    local t1, t2 = timers()
    return t1 > 0 or t2 > 0
  end, 30000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "a guard to break"),
  H.release(),
  -- keep sampling: the breaking hit's HP write lands frames after the
  -- timer went up (pred stopped the drive at the timer write)
  H.repeatN(240, { H.call(sampleDrops), H.waitFrames(1) }),
  -- the beams that broke the guard went through the magitek list, whose
  -- rendered rows persist in the menu map: assert the colored element
  -- icon right of "Fire Beam" (a blank icon here = the pre-render only,
  -- meaning the real list draw lost its icon column)
  H.call(function()
    local vr = emu.memType.snesVideoRam
    local best = nil
    for w = 0x6000, 0x7FF0 do
      if (emu.readWord(w*2, vr) & 0xFF) == 0x85
        and (emu.readWord(w*2+2, vr) & 0xFF) == 0xA2
        and (emu.readWord(w*2+4, vr) & 0xFF) == 0xAB then
        local icon = emu.readWord((w + 10) * 2, vr)
        if best == nil or icon == 0x3DEB then best = icon end
      end
    end
    H.assertEq(best, 0x3DEB, "fire icon glyph + red palette in the rendered list")
  end),
  report("broken"),
  H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local r1, r2 = revealed()
    local broke = (t1 > 0) and 1 or 2
    H.assertEq(broke == 1 and s1 or s2, 0, "broken guard shields at 0")
    H.assertEq((broke == 1 and r1 or r2) & 0x01, 0x01,
      "fire weakness revealed on the broken guard")
    -- 3b. broken x2 for a flags3-$20 beam: the broken guard's drop record
    -- is [unbroken chip(s)..., the breaking hit]; the breaking hit ran
    -- with the timer up and must be ~2x the first unbroken chip.
    local seq = drops[broke]
    local parts = {}
    for _, e in ipairs(seq) do
      parts[#parts + 1] = string.format("%d%s", e.d, e.broken and "B" or "")
    end
    H.log(string.format("guard %d drop record: %s", broke,
      table.concat(parts, " ")))
    H.assertEq(#seq >= 2, true, "two chip hits recorded on the broken guard")
    local first, last = seq[1], seq[#seq]
    H.assertEq(first.broken, false, "first chip landed unbroken")
    H.assertEq(last.broken, true, "breaking hit landed with the timer up")
    -- shielded resistance moved these bounds deliberately (measurement
    -- #5): unbroken chip = weak x2 * shielded x0.5 = ~1x base; breaking
    -- hit = weak x2 * broken x2, unattenuated (its chip zeroed the
    -- shields before the damage tail) = ~4x base. ratio ~4x, true range
    -- [3.51, 4.55] under vanilla's 224..255/256 spread.
    H.assertEq(last.d > first.d * 3, true,
      "broken beam hit > 3x the shielded chip (0.5x lifted, x2 collected)")
    H.assertEq(last.d < first.d * 6, true,
      "and < 6x (weak x2 * broken x2, not something wilder)")
    H.screenshot("break_broken")
  end),

  -- 4. recovery: timer expires, shields restore, reveal persists
  H.waitUntil(function()
    local t1, t2 = timers()
    local s1, s2 = shields()
    return t1 == 0 and t2 == 0 and (s1 == 2 or s2 == 2)
  end, 12000, "broken guard to recover", 60),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    local s1, s2 = shields()
    local r1, r2 = revealed()
    H.assertEq(s1 == 2 or s2 == 2, true, "shields restored to max")
    H.assertEq((r1 | r2) & 0x01, 0x01, "revealed weakness survives recovery")
    H.screenshot("break_recovered")
  end),
})

-- @suite slow
-- battle_class.lua -- M3 acceptance: weapon-class chip -> reveal -> break.
--
--   tools/tests/run.sh tools/tests/battle_class.lua
--
-- The doorstep guards are AUTHORED piercing-weak (Ot6ShieldTbl now carries
-- a class byte), so the seed itself is under test before any pokes. The
-- magitek party has no Fight command, so this borrows battle_hits's
-- driver: rewrite the live command lists to Fight-only and berserk the
-- party (RandCharAction -> Cmd_00 -> FightAttack, no menus). The class
-- read is the LIVE $3ca8 hand item, so poking a hand mid-battle swaps the
-- probe class without touching damage stats -- each phase re-arms the
-- party with a different weapon and watches the shield counter:
--
--   0. seed: shields 2/2, class-weak $02 (authored), revealed-class 0,
--      codex magic re-signed 'O7' (fresh init after self-clean)
--   1. slash phase (MithrilBlade $0a): swings land, nothing chips
--   2. pierce phase (Dirk $00): chip + reveal ($3ea9 bit $02) + class
--      codex byte learned
--   3. keep swinging: shields 0 -> broken timer
--   4. recovery: shields restore, revealed class SURVIVES
--   5. null-break phase (Fixed Dice $52 = class $88, guards re-poked
--      ¤-weak): swings land, nothing chips, nothing revealed
--   6. ¤ phase (Dice $51 = class $08): the chip fires
--   7. heal-reversal phase: slash-weak guards ABSORB fire, swings carry
--      fire (hand element poked) -- every hit resolves as a heal, and a
--      resolved heal must chip NOTHING (the $f2 bit-0 gate; per-frame HP
--      watcher proves heals actually landed, so the assert is not vacuous)
--   8. flagged-skill phase (TekMissile $8a, flags3 $20 "can't dodge"):
--      terra is un-berserked, her real commands restored, and her menu
--      driven to TekMissile -- a flags3-nonzero classed skill MUST chip a
--      pierce-weak guard (the whole-byte $f2 gate silently blocked every
--      such chip; this is the regression gate for the bit-0 narrowing).
--      the drive traverses terra's magitek list, so its rendered rows
--      also carry the v0.2 ability-list assert: TekMissile (elementless,
--      Ot6SkillClassTbl pierce) wears the pierce class icon after its
--      name, where elemental abilities wear their element icon
--   9. tools-list phase (STAGED -- no fixture reaches a Tools user):
--      three tool items are poked into the battle inventory ($2686
--      stride 5: id / usage flags, bit $40 = the tools-window scan bit /
--      targeting / qty) and terra's command slot 0 becomes Tools ($09).
--      opening it renders the tools list through ListTextCmd_0e +
--      Ot6ToolListIcon_ext: Chain Saw wears slash, Drill wears pierce
--      (each replacing the name field's trailing blank), NoiseBlaster
--      (classless, and a full-width 13-char name) keeps its last letter
--
-- The under-enemy HUD is asserted around phases 0-2: an authored-pierce
-- guard with no element weakness shows [shield]['?'] before any probe,
-- and the '?' becomes the pierce class icon ($da, white like the '?')
-- once the class is revealed -- the class slots ride the exact
-- revealed-vs-'?' machinery the element slots use.
--
-- Element weaknesses are zeroed on both guards at setup so the magitek
-- holder's stale beams (and poison DoT) can't move shields: every shield
-- transition below is the CLASS path or a bug.
--
-- Guesses pending a real run (marked GUESS below):
--   - GUESS(seed-2): guards still seed 2/2 with the extended 4-byte
--     records (battle_break asserts the same; if this fails the record
--     stride is wrong and everything after is noise)
--   - swing-cadence (RESOLVED): the no-chip phases no longer wait a fixed
--     1500-frame budget. The berserk gauge is accelerated (bumpAtb pokes the
--     ATB fill constant $3ac8) and each no-chip phase now DRIVES UNTIL it has
--     watched two probe-class Fights actually resolve ($57b8 write counter),
--     then asserts nothing chipped -- so a slow cadence fails the driveUntil
--     loudly instead of passing the negative vacuously. Measured cadence:
--     ~700 frozen frames of gauge spin-up at each phase entry ($3aa0.3 held),
--     then swings land every few dozen frames.
--   - GUESS(dice): poking $3ca8 to dice ids swaps the CLASS lookup but
--     not the init-time special-effect bytes, so dice phases swing like
--     normal weapons here; real equipped-dice behavior (the dice damage
--     effect reaching the join hook) still wants a manual phase-2 look.
--
-- Entity map (same fight as battle_break): guards in monster slots 2/3
-- -> entities $0c/$0e. shields $3E44/$3E46 - timers $3E94/$3E96 -
-- revealed classes $3EA9/$3EAB - class weak $3EA8/$3EAA - weak elems
-- $3BEC/$3BEE - absorbed elems $3BD8/$3BDA - HP $3C00/$3C02. party
-- entities 0/2/4: right-hand item $3CA8/$3CAA/$3CAC, right-hand element
-- $3B90/$3B92/$3B94. species stash $57C4 (slot 2). class codex sram
-- $316190+species. live attack class byte $57B8 (logged, not asserted:
-- monster actions legitimately zero it).

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end
local function shields() return H.readByte(0x3E44), H.readByte(0x3E46) end
local function timers() return H.readByte(0x3E94), H.readByte(0x3E96) end
local function classWeak() return H.readByte(0x3EA8), H.readByte(0x3EAA) end
local function classRev() return H.readByte(0x3EA9), H.readByte(0x3EAB) end

local function report(tag)
  return H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local w1, w2 = classWeak()
    local r1, r2 = classRev()
    H.log(string.format(
      "%s shields=%d,%d timers=%02X,%02X cweak=%02X,%02X crev=%02X,%02X " ..
      "atkclass=%02X hp=%04X,%04X",
      tag, s1, s2, t1, t2, w1, w2, r1, r2,
      H.readByte(0x57B8), H.readWord(0x3C00), H.readWord(0x3C02)))
  end)
end

-- arm every party right hand with one item id (class probe swap); left
-- hands stay untouched -- a single swing always picks the right hand
local function armRightHands(item)
  return H.call(function()
    for _, a in ipairs({ 0x3CA8, 0x3CAA, 0x3CAC }) do H.writeByte(a, item) end
    H.log(string.format("armed right hands with item %02x", item))
  end)
end

-- 5000 hp: a break window's x2 fights (~100/hit) can't wound a guard
-- between re-pokes; a wounded guard would never chip again (by design)
-- and starve the later phases
-- Bump the berserk party's ATB fill constant ($3ac8,x, 16-bit, stride 2,
-- normally set by CalcSpeed from Speed) so a gauge that is ALLOWED to run
-- tops off in ~16 frames instead of ~770. This is engine-native: the engine
-- still runs the overflow -> queue-action -> reset cycle and a character still
-- only acts when idle (the swing animation gates the real rate), so every
-- counted swing is a genuine resolved Fight -- we just stop waiting on a slow
-- gauge. (Forcibly clearing $3aa0.3, the gauge-stop bit, to skip the ~700f
-- per-phase spin-up does NOT work: it races the action-commit cycle and no
-- Fight ever resolves, so that spin-up is left intact.)
local ATB_FAST = 0x1000
local function bumpAtb()
  for slot = 0, 3 do H.writeWord(0x3AC8 + slot * 2, ATB_FAST) end
end

local function repokeHp()
  H.writeWord(0x3C00, 5000)
  H.writeWord(0x3C02, 5000)
  bumpAtb()
end

-- one berserk-driven step: keep the guards alive, let time pass
local driveStep = {
  H.call(repokeHp),
  H.waitFrames(30),
}

-- party keepalive for the long late phases: top anyone low BEFORE the
-- wound bit can land (re-poking hp does not revive the dead)
local function pinParty()
  for c = 0, 2 do
    local a = 0x3BF4 + c * 2
    if H.readWord(a) < 100 then H.writeWord(a, 300) end
  end
  bumpAtb()
end

local s1c, s2c -- shield snapshot for the no-chip phases
local terra    -- terra's party slot (char id 0)
local terraCmds, terraSt1 = {}, nil  -- her pre-lab commands + status 1

-- under-enemy HUD: the first weakness-slot word after each shield glyph
-- on the bg3 field map (one per live hud line)
local SHIELDG = {[0x65]=1,[0x66]=1,[0x67]=1,[0x69]=1,[0x6a]=1,[0x6b]=1,[0x71]=1}
local function hudSlotWords()
  local vr = emu.memType.snesVideoRam
  local reg = H.readByte(0x897b)
  local base = ((reg - (reg % 4)) * 256) * 2
  local t = {}
  for off = 0, 0x7FC, 2 do
    if emu.read(base + off + 1, vr) == 0x21 and SHIELDG[emu.read(base + off, vr)] then
      t[#t + 1] = emu.readWord(base + off + 2, vr)
    end
  end
  return t
end

-- battle menu map: word address of a rendered glyph sequence (or nil)
local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then
        hit = false
        break
      end
    end
    if hit then return w end
  end
  return nil
end

-- non-vacuity watcher: record every value the attack-class byte ($57b8)
-- is loaded with, so the no-chip phases can PROVE swings of the expected
-- class actually resolved while they ran
local classWrites, classRef = {}, nil
local function watchClasses(on)
  return H.call(function()
    if on then
      classWrites = {}
      classRef = emu.addMemoryCallback(function(addr, value)
        classWrites[value] = (classWrites[value] or 0) + 1
      end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
    else
      emu.removeMemoryCallback(classRef, emu.callbackType.write,
        0x7E57B8, 0x7E57B8)
      local parts = {}
      for v, n in pairs(classWrites) do
        parts[#parts + 1] = string.format("%02x:%d", v, n)
      end
      table.sort(parts)
      H.log("class byte writes seen: " .. table.concat(parts, " "))
    end
  end)
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.call(function()
    -- self-cleaning: invalidate the codex so this run proves the v2
    -- (elements + classes) init -> learn cycle from scratch
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle active", 30),
  H.waitFrames(240),

  -- 0. seeding: authored shields AND the authored class row
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1, 2, "guard 1 shields seeded")           -- GUESS(seed-2)
    H.assertEq(s2, 2, "guard 2 shields seeded")
    local w1, w2 = classWeak()
    H.assertEq(w1, 0x02, "guard 1 authored piercing-weak")
    H.assertEq(w2, 0x02, "guard 2 authored piercing-weak")
    local r1, r2 = classRev()
    H.assertEq(r1, 0, "guard 1 opens with no class revealed")
    H.assertEq(r2, 0, "guard 2 opens with no class revealed")
    H.assertEq(sram(0x316000), 0x4f, "codex magic 'O' after v2 re-init")
    H.assertEq(sram(0x316001), 0x37, "codex magic '7' after v2 re-init")
  end),
  report("seeded"),

  -- hud: guards carry no element weakness, so each line's first slot is
  -- the CLASS slot -- '?' until a probe reveals it (codex was wiped)
  H.waitUntil(function() return #hudSlotWords() >= 2 end, 300,
    "both guard hud lines up", 10),
  H.call(function()
    local slots = hudSlotWords()
    for i, w in ipairs(slots) do
      H.assertEq(w, 0x21BF,
        string.format("hud line %d: unprobed class shows the '?' slot", i))
    end
    H.screenshot("class_hud_qmark")
  end),

  -- lab setup: no element chip possible, tough guards, berserk Fight.
  -- terra's real commands + status are saved first: phase 8 restores
  -- them to drive her menu to TekMissile.
  H.call(function()
    H.writeByte(0x3BEC, 0)                 -- guards lose their element
    H.writeByte(0x3BEE, 0)                 -- weaknesses: class only below
    repokeHp()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot * 2) == 0 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "terra found in the party")
    for i = 0, 3 do
      terraCmds[i] = H.readByte(0x202E + terra * 12 + i * 3)
    end
    terraSt1 = H.readByte(0x3EE4 + terra * 2)
    local holder = H.readByte(0x62CA)      -- slot with the open menu
    for slot = 0, 3 do                     -- entries are [cmd,d,d] x4
      H.writeByte(0x202E + slot * 12, 0x00)
      H.writeByte(0x2031 + slot * 12, 0xFF)
      H.writeByte(0x2034 + slot * 12, 0xFF)
      H.writeByte(0x2037 + slot * 12, 0xFF)
      local st2 = 0x3EE5 + slot * 2
      H.writeByte(st2, H.readByte(st2) | 0x10)          -- berserk
      if slot ~= holder then
        -- magitek status routes berserk to random beams; clear it so
        -- berserk picks Fight (the holder keeps replaying its stale
        -- staged beam -- battle_hits's C1-staging wart -- which is
        -- harmless here: beams have no class and no element weakness)
        local st1 = 0x3EE4 + slot * 2
        H.writeByte(st1, H.readByte(st1) & 0xF7)
      end
    end
    H.log(string.format("berserk fight party, terra slot %d, menu holder slot %d",
      terra, holder))
  end),

  -- 1. slash phase: wrong class, no chip
  armRightHands(0x0A),                     -- MithrilBlade: slashing
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  -- Drive until TWO slashing Fights have actually RESOLVED (not a fixed
  -- padded budget): the negative "nothing chips" below is only meaningful if
  -- swings of the probe class landed, so we make that a hard precondition --
  -- if two do not resolve within the cap this driveUntil FAILS LOUDLY instead
  -- of the old fixed wait passing vacuously. (Measured swing cadence with the
  -- accelerated gauge: ~700f cold-start spin-up, then swings land fast.)
  H.driveUntil(function() return (classWrites[0x01] or 0) >= 2 end,
    2000, driveStep, "two slashing swings to resolve"),
  watchClasses(false),
  report("slash-phase"),
  H.call(function()
    H.assertEq((classWrites[0x01] or 0) >= 2, true,
      "two slashing swings actually resolved during the phase")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "slash swings never chip a pierce-weak guard")
    H.assertEq(s2, s2c, "slash swings never chip a pierce-weak guard (2)")
    local r1, r2 = classRev()
    H.assertEq(r1 | r2, 0, "and reveal nothing")
  end),

  -- 2. pierce phase: chip + reveal + codex
  armRightHands(0x00),                     -- Dirk: piercing
  H.driveUntil(function()
    local r1, r2 = classRev()
    return ((r1 | r2) & 0x02) == 0x02
  end, 15000, driveStep, "a piercing chip to reveal the class"),
  report("pierce-chip"),
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1 < 2 or s2 < 2, true, "the revealing hit also chipped")
    local species = H.readWord(0x57C4)
    H.log(string.format("guard species=%d", species))
    H.assertEq(sram(0x316190 + species) & 0x02, 0x02,
      "class codex learned piercing")
  end),

  -- hud: the revealed class replaces its '?' with the pierce icon ($da,
  -- white -- the same glyph the menus use for piercing weapons). waitUntil:
  -- the revealing swing's animation can contest bg3 for a few dozen frames.
  H.waitUntil(function()
    for _, w in ipairs(hudSlotWords()) do
      if w == 0x21DA then return true end
    end
    return false
  end, 600, "revealed pierce icon in the hud row", 10),
  H.call(function() H.screenshot("class_hud_pierce") end),

  -- 3. keep swinging until a break
  H.driveUntil(function()
    local t1, t2 = timers()
    return t1 > 0 or t2 > 0
  end, 15000, driveStep, "a guard to break on class chip"),
  H.release(),
  report("broken"),
  H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local broke = (t1 > 0) and 1 or 2
    H.assertEq(broke == 1 and s1 or s2, 0, "broken guard shields at 0")
    H.screenshot("class_broken")
  end),

  -- 4. recovery: shields restore, the revealed class survives.
  -- (driveUntil, not waitUntil: the re-pokes must keep running or the
  -- x2 break window kills the guards and wound-dead monsters never
  -- chip again -- exactly what the first live run demonstrated)
  H.driveUntil(function()
    local t1, t2 = timers()
    local s1, s2 = shields()
    return t1 == 0 and t2 == 0 and (s1 == 2 or s2 == 2)
  end, 15000, driveStep, "broken guard to recover"),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    local s1, s2 = shields()
    local r1, r2 = classRev()
    H.assertEq(s1 == 2 or s2 == 2, true, "shields restored to max")
    H.assertEq((r1 | r2) & 0x02, 0x02, "revealed class survives recovery")
  end),

  -- 5. null-break phase: ¤-weak guards, Fixed Dice teach nothing
  H.call(function()
    H.writeByte(0x3EA8, 0x08)              -- guards now ¤-weak only
    H.writeByte(0x3EAA, 0x08)
  end),
  armRightHands(0x52),                     -- Fixed Dice: ¤ + null-break
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  -- Same non-vacuity guard as the slash phase: require two null-break ¤ Fights
  -- to actually resolve before trusting "nothing chips", or fail loudly.
  H.driveUntil(function() return (classWrites[0x88] or 0) >= 2 end,
    2000, driveStep, "two null-break ¤ swings to resolve"),
  watchClasses(false),
  report("nullbreak-phase"),
  H.call(function()                        -- GUESS(dice)
    H.assertEq((classWrites[0x88] or 0) >= 2, true,
      "two null-break ¤ swings actually resolved during the phase")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "fixed dice never chip")
    H.assertEq(s2, s2c, "fixed dice never chip (2)")
    local r1, r2 = classRev()
    H.assertEq((r1 | r2) & 0x08, 0, "and never reveal ¤")
  end),

  -- 6. ¤ phase: ordinary dice chip the special class
  armRightHands(0x51),                     -- Dice: ¤, chips
  H.driveUntil(function()
    local r1, r2 = classRev()
    return ((r1 | r2) & 0x08) == 0x08
  end, 15000, driveStep, "a ¤ chip to reveal the class"),  -- GUESS(dice)
  report("special-chip"),
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1 < s1c or s2 < s2c, true, "the ¤ reveal also chipped")
    H.screenshot("class_special")
  end),

  -- 7. heal-reversal phase: a hit that RESOLVES as a heal must not chip.
  -- slash-weak guards absorb fire; the right hands are slash blades whose
  -- pre-baked hand element ($3b90) is poked to fire. every landed swing
  -- heals the guard (CalcTargetDmg's absorb path flips $f2 bit 0) and the
  -- class gate must skip it. the per-frame HP watcher proves heals landed:
  -- a heal clamps the poked 5000 hp down to the guard's natural max.
  H.call(function()
    H.writeByte(0x3E44, 2); H.writeByte(0x3E46, 2)   -- stage shields clean
    H.writeByte(0x3E94, 0); H.writeByte(0x3E96, 0)   -- no timers running
    H.writeByte(0x3EA8, 0x01)              -- guards slash-weak
    H.writeByte(0x3EAA, 0x01)
    H.writeByte(0x3BD8, 0x01)              -- and fire-ABSORBING
    H.writeByte(0x3BDA, 0x01)
    for _, a in ipairs({ 0x3B90, 0x3B92, 0x3B94 }) do
      H.writeByte(a, 0x01)                 -- right-hand element: fire
    end
    repokeHp()
    H.vars.healSeen = false
    H.log("heal-reversal lab: slash-weak fire-absorbing guards, fire slashes")
  end),
  armRightHands(0x0A),                     -- MithrilBlade: slashing
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  -- Drive until at least one swing has resolved as a HEAL *and* two slashing
  -- Fights have resolved -- both are hard preconditions for the "no chip"
  -- negative below, so a too-short window can no longer pass vacuously (it
  -- times out and fails). Replaces a flat 1500-frame budget.
  H.driveUntil(function()
    return H.vars.healSeen and (classWrites[0x01] or 0) >= 2
  end, 2500, {
    H.call(function()
      pinParty()
      for _, a in ipairs({ 0x3C00, 0x3C02 }) do
        local hp = H.readWord(a)
        if hp ~= 5000 then
          -- a heal clamps 5000 down to natural max (tiny); a stray
          -- damage hit only nibbles. either way, re-pin.
          if hp < 1000 or hp > 5000 then H.vars.healSeen = true end
          H.writeWord(a, 5000)
        end
      end
    end),
    H.waitFrames(1),
  }, "a heal to land and two slashing swings to resolve"),
  watchClasses(false),
  report("heal-reversal"),
  H.call(function()
    H.assertEq((classWrites[0x01] or 0) >= 2, true,
      "two slashing swings actually resolved during the phase")
    H.assertEq(H.vars.healSeen, true,
      "at least one swing resolved as a heal (absorb reversal ran)")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "healing hits never chip a slash-weak guard")
    H.assertEq(s2, s2c, "healing hits never chip a slash-weak guard (2)")
    local r1, r2 = classRev()
    H.assertEq((r1 | r2) & 0x01, 0, "and reveal nothing")
  end),

  -- 7b. edge: a resolved HEAL is never scaled by the shielded-resistance
  -- multiplier. Ot6ShieldedDmg gates on $f2 bit 0 exactly as the chip
  -- procs do, so an absorbed hit (which flips that bit) must add the SAME
  -- hp whether the target still holds shields or not. same-guard proof
  -- (guard 1 is the reliably-swung target; berserk rarely picks guard 2):
  -- two windows on guard 1, shielded then shieldless, both fire-absorbing
  -- from phase 7 so every fire slash heals it. a roomy max hp keeps the
  -- heal off the clamp. while shielded the heal survives ONLY via the
  -- $f2 gate -- if that gate were broken the shielded window's heal would
  -- come back ~half the shieldless window's, far under the 0.75x floor.
  -- (the shieldless-DAMAGE half of the edge -- 0 shields takes full,
  -- unattenuated damage -- is proven in battle_break: the breaking hit
  -- lands at broken x2 with the shields already at 0, and its ~4x ratio
  -- only holds because that 0-shield hit is NOT attenuated.)
  -- the metric is the AVERAGE hp per absorbed hit, not the single biggest:
  -- the vanilla heal roll (224..255/256 of the formula) makes the max a
  -- noisy one-sample estimator, but the per-hit mean over a window
  -- converges to the same value regardless of shield state -- unless the
  -- shielded window's heals were scaled, which would halve its mean.
  H.call(function()
    H.writeByte(0x3E94, 0)                        -- guard 1 not broken
    H.writeByte(0x3EA8, 0)                         -- no class weak: shields stay put
    H.writeWord(0x3C28, 10000)                    -- guard 1 max hp: heal headroom
    H.vars.sumsh, H.vars.cntsh = 0, 0
    H.vars.sumno, H.vars.cntno = 0, 0
  end),
  -- adaptive windows: drive each state until it has banked enough heals
  -- (guard 1's berserk hit-rate drifts across the fight, so a fixed frame
  -- count under-samples one window). 12 heals each keeps the mean stable.
  -- window 1: SHIELDED (the heal survives whole ONLY via the $f2 gate)
  H.call(function()
    H.writeByte(0x3E44, 2)
    H.writeWord(0x3C00, 3000); H.vars.ph = 3000
  end),
  H.driveUntil(function() return H.vars.cntsh >= 12 end, 15000, {
    H.call(function()
      pinParty()
      local h = H.readWord(0x3C00)
      if h > H.vars.ph then
        H.vars.sumsh = H.vars.sumsh + (h - H.vars.ph)
        H.vars.cntsh = H.vars.cntsh + 1
      end
      if h > 8000 or h < 1000 then h = 3000; H.writeWord(0x3C00, 3000) end
      H.vars.ph = h
    end),
    H.waitFrames(1),
  }, "12 heals on the shielded guard"),
  -- window 2: SHIELDLESS (heal passes the $3e38==0 gate instead)
  H.call(function()
    H.writeByte(0x3E44, 0)
    H.writeWord(0x3C00, 3000); H.vars.ph = 3000
  end),
  H.driveUntil(function() return H.vars.cntno >= 12 end, 15000, {
    H.call(function()
      pinParty()
      local h = H.readWord(0x3C00)
      if h > H.vars.ph then
        H.vars.sumno = H.vars.sumno + (h - H.vars.ph)
        H.vars.cntno = H.vars.cntno + 1
      end
      if h > 8000 or h < 1000 then h = 3000; H.writeWord(0x3C00, 3000) end
      H.vars.ph = h
    end),
    H.waitFrames(1),
  }, "12 heals on the shieldless guard"),
  H.call(function()
    local avgsh = H.vars.sumsh / H.vars.cntsh
    local avgno = H.vars.sumno / H.vars.cntno
    H.log(string.format("guard 1 mean heal/hit: shielded=%.1f (n=%d) shieldless=%.1f (n=%d)",
      avgsh, H.vars.cntsh, avgno, H.vars.cntno))
    -- unattenuated: the means match within the roll spread. an 0.5x
    -- attenuation of the shielded window would drop its mean to ~half,
    -- far under this floor (0.8x).
    H.assertEq(avgsh * 5 >= avgno * 4, true,
      "mean heal while shielded is NOT attenuated (>= 0.8x the shieldless mean)")
  end),

  -- 8. flagged-skill phase: TekMissile (flags3 $20) must chip. restore
  -- the lab to pierce-weak, hand terra her real menu back, and walk it:
  -- MagiTek -> down x3, right (her 2x4 grid's bottom-right cell) -> fire
  -- at the default target. the drive retries the lap until the skill
  -- loader's $02 lands and a shield moves.
  H.call(function()
    H.writeByte(0x3EA8, 0x02); H.writeByte(0x3EAA, 0x02)  -- pierce-weak
    H.writeByte(0x3BD8, 0); H.writeByte(0x3BDA, 0)        -- absorb off
    H.writeByte(0x3E44, 2); H.writeByte(0x3E46, 2)        -- shields staged
    H.writeByte(0x3E94, 0); H.writeByte(0x3E96, 0)
    repokeHp()
    for i = 0, 3 do
      H.writeByte(0x202E + terra * 12 + i * 3, terraCmds[i])
    end
    H.writeByte(0x3EE4 + terra * 2, terraSt1)             -- magitek back
    local st2 = 0x3EE5 + terra * 2
    H.writeByte(st2, H.readByte(st2) & 0xEF)              -- un-berserk
    H.vars.tplan, H.vars.tpf = nil, 1
    H.log("tek lab: terra's menu restored; berserkers keep slashing air")
  end),
  watchClasses(true),
  H.driveUntil(function()
    local s1, s2 = shields()
    return s1 < 2 or s2 < 2
  end, 25000, {
    H.call(function()
      repokeHp()
      pinParty()
      local menu = H.readByte(0x7bca)
      if menu == 0 or H.readByte(0x62CA) ~= terra then
        H.vars.tplan = nil
        H.setPad({})
        return
      end
      local p = H.vars.tplan
      if p == nil or H.vars.tpf > #p then
        p = {}
        local function tap(btn, on, off)
          for _ = 1, on do p[#p + 1] = { btn } end
          for _ = 1, off do p[#p + 1] = {} end
        end
        tap("b", 6, 16); tap("b", 6, 16)   -- converge to the root menu
        tap("a", 6, 40)                    -- MagiTek -> list (long settle:
                                           --   input during window-open
                                           --   wedges the staged rows)
        for _ = 1, 3 do tap("down", 6, 16) end
        tap("right", 6, 16)                -- bottom-right: TekMissile
        tap("a", 6, 20)                    -- pick the cell
        tap("a", 6, 60)                    -- confirm the default target
        for _ = 1, 90 do p[#p + 1] = {} end
        H.vars.tplan, H.vars.tpf = p, 1
      end
      H.setPad(p[H.vars.tpf])
      H.vars.tpf = H.vars.tpf + 1
    end),
  }, "a TekMissile chip moves a guard's shields"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),
  watchClasses(false),
  report("tek-chip"),
  H.call(function()
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "a piercing skill load resolved -- with slash blades in every hand, " ..
      "only TekMissile ($8a) stores $02")
    local s1, s2 = shields()
    H.assertEq(s1 < 2 or s2 < 2, true,
      "the flags3-$20 skill chipped a pierce-weak guard")
    local species = H.readWord(0x57C4)
    H.assertEq(sram(0x316190 + species) & 0x02, 0x02,
      "class codex holds piercing after the skill chip")
    -- ability list: the drive rendered terra's magitek list on the way
    -- to TekMissile, and rendered rows persist in the menu map (the
    -- battle_break precedent). TekMissile is elementless, so its icon
    -- column must carry the Ot6SkillClassTbl pierce glyph in white --
    -- exactly where Fire Beam carries its red element icon.
    local tek = findName({0x93,0x9e,0xa4,0x8c,0xa2,0xac,0xac,0xa2,0xa5,0x9e})
    H.assertEq(tek ~= nil, true, "TekMissile row rendered in the menu map")
    H.assertEq(emu.readWord((tek + 10) * 2, emu.memType.snesVideoRam), 0x21DA,
      "pierce class icon right of TekMissile in the magitek list")
    H.screenshot("class_tek")
  end),

  -- 9. tools-list phase: stage the cheapest reachable Tools render.
  -- no fixture carries a Tools user (magitek intro party), so the
  -- inventory and command list are poked: battle items $2686 stride 5
  -- gain Chain Saw / Drill / NoiseBlaster with the $40 tools-scan flag
  -- (LoadItemProp derives it from item type 0; poked directly), and ALL
  -- of terra's command slots become Tools ($09). the in-battle command
  -- cursor persists across turns (phase 8 left it on the MagiTek cell),
  -- so poking only slot 0 would let the drive's 'a' open the wrong
  -- window -- with every slot Tools, whatever cell the cursor rests on
  -- opens the tools window (menu state $2e), whose rows render through
  -- ListTextCmd_0e + Ot6ToolListIcon_ext.
  --
  -- The battle tools window is a TWO-COLUMN grid and only its first row
  -- is on-screen (verified live: a third tool lands in an unrendered
  -- second row). So the two asserted tools ride slots 0/1 -- Chain Saw
  -- (col 0, slashing) and Drill (col 1, piercing) -- and both wear their
  -- class icon after the name, exactly where a magitek skill wears its
  -- element icon. NoiseBlaster fills slot 2 (the hidden row) purely so
  -- the list has the 3-entry shape that renders cleanly.
  H.call(function()
    local inv = { 0xa6, 0xa8, 0xa3 }   -- Chain Saw, Drill, NoiseBlaster
    for i, id in ipairs(inv) do
      local a = 0x2686 + (i - 1) * 5
      H.writeByte(a, id)
      H.writeByte(a + 1, 0x40)         -- tools flag
      H.writeByte(a + 2, 0x01)         -- targeting (render-only phase)
      H.writeByte(a + 3, 1)            -- qty
    end
    for i = 0, 3 do H.writeByte(0x202E + terra * 12 + i * 3, 0x09) end
    H.vars.tplan, H.vars.tpf = nil, 1
    H.log("tools lab: inventory staged, terra commands = Tools")
  end),
  H.driveUntil(function()
    -- the first row is drawn once Chain Saw (col 0) renders
    return findName({0x82,0xa1,0x9a,0xa2,0xa7}) ~= nil   -- "Chain"
  end, 20000, {
    -- same scripted-lap discipline the TekMissile drive (phase 8) proved:
    -- when terra holds the menu, converge to the root command list, then
    -- one 'a' opens Tools (every slot is Tools). the long idle tail lets
    -- the rows render before the predicate fires; input mid window-open
    -- wedges the staged rows, so the settle after 'a' is generous.
    H.call(function()
      repokeHp()
      pinParty()
      if H.readByte(0x7bca) == 0 or H.readByte(0x62CA) ~= terra then
        H.vars.tplan = nil
        H.setPad({})
        return
      end
      local p = H.vars.tplan
      if p == nil or H.vars.tpf > #p then
        p = {}
        local function tap(btn, on, off)
          for _ = 1, on do p[#p + 1] = { btn } end
          for _ = 1, off do p[#p + 1] = {} end
        end
        tap("b", 6, 16); tap("b", 6, 16)   -- converge to the root menu
        tap("a", 6, 60)                    -- open Tools (any slot -> $2e)
        for _ = 1, 120 do p[#p + 1] = {} end
        H.vars.tplan, H.vars.tpf = p, 1
      end
      H.setPad(p[H.vars.tpf])
      H.vars.tpf = H.vars.tpf + 1
    end),
  }, "the tools window renders its rows"),
  H.release(),
  H.waitFrames(20),
  H.call(function()
    -- both first-row tools wear their class glyph in the name field's
    -- last column ({tool} leading icon + name, then the class icon), so
    -- findName lands on the letters and the glyph rides at +11 -- the
    -- same column the '{tool}Chain Saw' / '{tool}Drill' names leave blank.
    -- Chain Saw (col 0): slashing -> the slash icon $d9.
    local saw = findName({0x82,0xa1,0x9a,0xa2,0xa7})       -- "Chain"
    H.assertEq(saw ~= nil, true, "Chain Saw row rendered")
    H.assertEq(emu.readWord((saw + 11) * 2, emu.memType.snesVideoRam), 0x21D9,
      "slash class icon after Chain Saw in the tools list")
    -- Drill (col 1): piercing -> the spear icon $da, exactly as TekMissile
    -- wears it in the magitek list above.
    local drill = findName({0x83,0xab,0xa2,0xa5,0xa5})     -- "Drill"
    H.assertEq(drill ~= nil, true, "Drill row rendered")
    H.assertEq(emu.readWord((drill + 11) * 2, emu.memType.snesVideoRam), 0x21DA,
      "pierce class icon after Drill in the tools list")
    H.screenshot("class_tools")
  end),

  -- LIVENESS, and it is not decoration. Every assertion in this phase reads
  -- a tilemap the window already drew -- which a FROZEN machine satisfies
  -- just as well as a running one, and did: Ot6ToolListIcon_ext (ot6.asm)
  -- spun the battle NMI forever on a CLASSLESS tool row, and this test came
  -- back green straight through it. MEASURED, by reverting that fix and
  -- re-running: all 40 assertions above pass -- both tools rows, both class
  -- icons -- with $98 not advancing at all. The fixture is why it never
  -- showed: its only classless tool (NoiseBlaster) sits in the list's
  -- unrendered second row while the two asserted tools ride the first, so
  -- the lock lands after the last thing this test looks at. It surfaced in
  -- battle_vargas instead, where the BioBlaster is list entry 0. $98 is the
  -- battle NMI's own frame counter (btlgfx_main.asm:1783), so a stall now
  -- fails here rather than passing on stale VRAM.
  H.call(function() H.vars.nmi0 = H.readByte(0x0098) end),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(0x0098) ~= H.vars.nmi0, true,
      "the battle NMI is still running after the tools window rendered")
  end),
})

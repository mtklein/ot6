-- @suite slow
-- battle_runicmonster.lua -- RunicBlade sends a monster's spell back at the
-- monster (#378, #424).
--
-- kits.md: a 3-BP Runic (RunicBlade, once CELES has learned it) sends every
-- player-magic spell it absorbs back at its caster as her own free cast of
-- it (Ot6BladeAbsorb banks it, Ot6BladeBounce queues it through vanilla's
-- counterattack queue).  battle_runicblade's caster is always EDGAR; here
-- the caster is a monster.
--
-- Played: Continue the wor-narshe-cliffs-v1 battery (CELES L41, the factory
-- long behind her), pace below the save point on the cliffs (map 34) into
-- random battles, and in one that fields a Wizard (its script is nothing
-- but player magic: Mute, Osmose, Rasp, Stop, Muddle, Sleep; formations 276
-- and 277, 160/256 of this map's battles, route_data.py pool field 34)
-- CELES raises Runic at 3 BP through the real menu (H.kitBattle; Defends
-- bank the points); everyone Defends.  A battle with no Wizard, or one that
-- ends first, is fought out and the next taken; a stance that runs out
-- without catching a Wizard's spell is raised again.  Nothing is written.
--
-- Recorded: every absorb by a RunicBlade stance (Ot6BladeAbsorb: the caster
-- and the spell), and every $3410 write (the spell an attack pass uses)
-- with the counter flag ($b1 bit 0), the command and the target masks.
-- Asserted, for the first absorb of a Wizard's spell:
--   1. the absorb banked a bounce for that monster (OT6_BLADEPEND valid,
--      OT6_BLADECASTER = its entity, OT6_BLADESPELL = the spell);
--   2. a counter came: Magic, that spell, at that monster alone ($b9 = its
--      bit, $b8 = 0).  (Its price, none, is battle_runicblade's.)
-- Old-ROM red and mutants: build/attempts/wt/v031-cleanup/ (#424).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, RUNIC, CMD_MAGIC, WIZARD = 0x06, 0x0B, 0x02, 0x0C4
-- the pace: two tiles of the maze's ledge below the save point (25,5),
-- whose own neighbours two and three tiles out are rock (route_data.py
-- field-path 34 25 5 23 8: 5 steps)
local PACE = { { 23, 6 }, { 23, 8 } }
local RUNICBLADE, BLADEPEND, BLADECASTER, BLADESPELL = 0xEDD4, 0xEDD5, 0xEDD6, 0xEDD7

local celes = nil
local absorbs, passes = {}, {}
local function arm()
  local ab = H.sym("Ot6BladeAbsorb")
  -- Ot6BladeAbsorb's tail: the bank is written (or not) by its rtl; read it
  -- at the next $3410 write or Ot6ActionEnd instead, from this record
  emu.addMemoryCallback(function()
    if celes == nil then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if y ~= celes * 2 or x < 8 then return end
    if (H.readByte(RUNICBLADE) & H.readByte(0x3018 + y)) == 0 then return end
    local a = { caster = x, spell = H.readByte(0xB6), species = H.monsterIds()[(x - 8) // 2 + 1], f = H.frame,
      mp = H.readWord(0x3C08 + y) }
    absorbs[#absorbs + 1] = a
    H.log(string.format("[rbm] f%d CELES's RunicBlade absorbs spell $%02X from monster slot %d (species $%03X)", a.f,
      a.spell, (x - 8) // 2, a.species or 0))
  end, emu.callbackType.exec, ab, ab)
  -- the bank, as CheckRetal's head finds it (Ot6BladeBounce consumes it)
  local bb = H.sym("Ot6BladeBounce")
  emu.addMemoryCallback(function()
    local a = absorbs[#absorbs]
    if a ~= nil and a.pend == nil then
      a.pend, a.bcaster, a.bspell = H.readByte(BLADEPEND), H.readByte(BLADECASTER), H.readByte(BLADESPELL)
    end
  end, emu.callbackType.exec, bb, bb)
  emu.addMemoryCallback(function(_, v)
    if celes == nil then return end
    local p = { spell = v, counter = (H.readByte(0xB1) & 1) == 1, cmd = H.readByte(0x3A7C), b8 = H.readByte(0xB8),
      b9 = H.readByte(0xB9), celesMp = H.readWord(0x3C08 + celes * 2), f = H.frame }
    passes[#passes + 1] = p
    if p.counter then
      H.log(string.format("[rbm] f%d counter pass: spell $%02X, command $%02X, targets chars $%02X mons $%02X, CELES "
        .. "MP %d", p.f, p.spell, p.cmd, p.b8, p.b9, p.celesMp))
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end

local function wizardSlots()
  local ids, t = H.monsterIds(), {}
  for s = 0, 5 do
    if ids[s + 1] == WIZARD and (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 then
      t[#t + 1] = s
    end
  end
  return t
end

-- BATTLES: a battle fields a Wizard 160/256 of the time, so none in ten is
-- 0.375^10 = 5.5e-5; a stance raised in a Wizard battle catches its spell
-- unless CELES is stopped or the Wizards turn elsewhere, so RAISES = 8
-- stances in all.
local BATTLES, RAISES = 14, 8
local battles, raises, ok, mode, nAbs, nPass, raisedF, fresh = 0, 0, false, nil, 0, 0, 0, true
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

local function verdict()
  for i = nAbs + 1, #absorbs do
    local a = absorbs[i]
    if a.species == WIZARD then
      H.assertEq(a.pend, 0x80 | (celes * 2), string.format("the absorb banked a bounce for CELES (OT6_BLADEPEND "
        .. "$%02X)", a.pend or 0))
      H.assertEq(a.bcaster, a.caster, "the bounce's caster is the Wizard that cast it (OT6_BLADECASTER)")
      H.assertEq(a.bspell, a.spell, "the bounce is the absorbed spell (OT6_BLADESPELL)")
      local back = nil
      for j = nPass + 1, #passes do
        local p = passes[j]
        if back == nil and p.counter and p.f >= a.f and p.spell == a.spell and p.b8 == 0
            and p.b9 == (1 << ((a.caster - 8) // 2)) then
          back = p
        end
      end
      H.assertEq(back ~= nil, true, string.format("a counter sent spell $%02X back at the Wizard in slot %d", a.spell,
        (a.caster - 8) // 2))
      H.assertEq(back.cmd, CMD_MAGIC, "the bounce is a Magic cast")
      H.log(string.format("[rbm] the bounce at f%d: spell $%02X at monster mask $%02X; CELES MP %d before it",
        back.f, back.spell, back.b9, back.celesMp))
      ok = true
      return
    end
  end
end

local steps = {
  H.bootCheckpoint("wor-narshe-cliffs-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (RunicBlade learned)")
  end),
  H.paceToEncounter("rbm", nil, PACE),
  H.driveUntil(function() return ok end, 800000, {
    H.cond(function() return not H.battleLoadStarted() end,
      { H.paceToEncounter("rbm", 0, PACE), H.call(function() fresh = true end) }, {}),
    H.call(function()
      if fresh then
        fresh = false
        battles = battles + 1
        H.assertEq(battles <= BATTLES, true, string.format("a Wizard's spell sent back within %d battles", BATTLES))
      end
      celes = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CELES then celes = s end end
      H.assertEq(celes ~= nil, true, "CELES is seated")
      local e, w = celes * 2, wizardSlots()
      plan, mode = {}, "stance"
      if #w == 0 or H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0
          or (H.readByte(0x3EE5 + e) & 0x90) ~= 0 then
        mode = "fightout"
        H.log(string.format("[rbm] battle %d: %d Wizard(s); CELES status %02X %02X: this battle is fought out",
          battles, #w, H.readByte(0x3EE4 + e), H.readByte(0x3EE5 + e)))
        return
      end
      raises = raises + 1
      H.assertEq(raises <= RAISES, true, string.format("a Wizard's spell caught within %d stances", RAISES))
      nAbs, nPass = #absorbs, #passes
      H.log(string.format("[rbm] battle %d: %d Wizard(s) (slots %s); CELES seat %d raises Runic at 3 BP (stance %d)",
        battles, #w, table.concat(w, ","), celes, raises))
      plan = { { who = CELES, cmd = RUNIC, boost = 3, self = true } }
    end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function()
          local k = H.vars.kit[#H.vars.kit]
          if k == nil then return false end
          if raisedF < k.frame then raisedF = k.frame end
          -- a Wizard's spell caught and its bounce come (or 1500 frames for
          -- it), or the stance ran out, or no Wizard is left
          for i = nAbs + 1, #absorbs do
            if absorbs[i].species == WIZARD then
              for j = nPass + 1, #passes do
                if passes[j].counter and passes[j].f >= absorbs[i].f then return true end
              end
              return H.frame > absorbs[i].f + 1500
            end
          end
          local stance = (H.readByte(RUNICBLADE) & H.readByte(0x3018 + celes * 2)) ~= 0
          return (H.frame > raisedF + 600 and not stance) or #wizardSlots() == 0
        end }),
      H.call(verdict),
    }),
  }, "a Wizard's spell sent back"),
  H.call(function()
    H.log(string.format("[rbm] PASS: CELES's RunicBlade sent a Wizard's spell back at it (battle %d, stance %d)",
      battles, raises))
  end),
}
H.run({ maxFrames = 900000 }, steps)

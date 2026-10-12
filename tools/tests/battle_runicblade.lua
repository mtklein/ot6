-- @suite slow
-- battle_runicblade.lua -- Celes's RunicBlade: a 3-BP Runic sends back what it
-- absorbs (#378).
--
-- kits.md "Divines": a divine's one gate is a full 3-BP boost.  RunicBlade is
-- CELES's, learned at the Magitek factory (event switch $0068): a Runic she
-- raises with all three points stands for three of her turns, as any 3-BP
-- Runic, absorbs as Runic does (the MP, the once-a-round BP), and every
-- spell it absorbs goes back at its caster as her own free cast of it
-- (Ot6BladeRaise / Ot6BladeAbsorb / Ot6BladeBounce, through vanilla's
-- counterattack queue).  A Runic raised under three points absorbs only.
--
-- Played: Continue the wor-tomb-v1 battery (EDGAR wears Ramuh: Bolt; CELES
-- L33; the factory long behind them), walk Darill's Tomb's east room into
-- a random battle, and play through the real menu (H.kitBattle); everyone
-- else Defends.  Nothing is written.  In one battle (one that ends before
-- all three is left, and the next starts them over, up to six):
--   1. CELES raises Runic at 2 BP; EDGAR casts Bolt at a monster: CELES
--      absorbs it (RunicEffect enrols her: Ot6RunicBP runs for her) and
--      nothing comes back;
--   2. CELES raises Runic at 3 BP; EDGAR casts Bolt: absorbed, and CELES
--      casts Bolt at EDGAR as a counter ($b1 bit 0) at no MP, which no
--      Runic stance absorbs (her own stands: Ot6BladeNoRunic) and which
--      lands on him;
--   3. EDGAR casts Bolt again inside the same stance: absorbed and sent back
--      again.
-- Recorded at every $3410 write (the spell an attack pass is using) with
-- the command, the counter flag and the target mask, and the two MP pools
-- around each cast.  Old-ROM red and mutants:
-- build/attempts/wt/v027-kits/final-matrix/ (<rom>__battle_runicblade.out).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, EDGAR, RUNIC, CMD_MAGIC, BOLT = 0x06, 0x04, 0x0B, 0x02, 0x02

local celes, edgar = nil, nil
local casts = {}   -- every $3410 <- Bolt: { counter, b8, cmd, celesMp, f }
local absorbs = 0  -- Ot6RunicBP entered for CELES: RunicEffect enrolled her as absorbing
local absorbF = 0  -- the frame of the last such entry
local function arm()
  local rb = H.sym("Ot6RunicBP")
  emu.addMemoryCallback(function()
    if celes ~= nil and (emu.getState()["cpu.y"] & 0xff) == celes * 2 then
      absorbs, absorbF = absorbs + 1, H.frame
      if casts[#casts] then casts[#casts].absorbed = true end
      H.log(string.format("[blade] f%d CELES absorbs (%d)", H.frame, absorbs))
    end
  end, emu.callbackType.exec, rb, rb)
  emu.addMemoryCallback(function(_, v)
    if v ~= BOLT or celes == nil or H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    casts[#casts + 1] = { counter = (H.readByte(0xB1) & 1) == 1, b8 = H.readByte(0xB8), b9 = H.readByte(0xB9),
      cmd = H.readByte(0x3A7C), celesMp = H.readWord(0x3C08 + celes * 2), edgarMp = H.readWord(0x3C08 + edgar * 2),
      edgarHp = H.readWord(0x3BF4 + edgar * 2), f = H.frame }
    local c = casts[#casts]
    H.log(string.format("[blade] f%d Bolt: counter=%s targets chars $%02X mons $%02X, cmd $%02X, CELES MP %d, "
      .. "EDGAR MP %d", c.f, tostring(c.counter), c.b8, c.b9, c.cmd, c.celesMp, c.edgarMp))
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end
local function bounces(from)
  local n = 0
  for i = from, #casts do
    local c = casts[i]
    if c.counter and c.b8 == (1 << edgar) and c.b9 == 0 then n = n + 1 end
  end
  return n
end
-- every bounce reached EDGAR: no stance absorbed it, and his HP fell.  A
-- bounce that finds him already fallen (the monsters' turns go on between
-- the absorb and the bounce) has nothing to land on: the step is not
-- counted, and the battle is fought out and the next one taken.
local function landed(from)
  for i = from, #casts do
    local c = casts[i]
    if c.counter and c.edgarHp == 0 then
      H.log(string.format("[blade] the bounce at f%d found EDGAR fallen: not counted", c.f))
      return false
    end
  end
  for i = from, #casts do
    local c = casts[i]
    if c.counter then
      local after = casts[i + 1] and casts[i + 1].edgarHp or H.readWord(0x3BF4 + edgar * 2)
      H.log(string.format("[blade] the bounce at f%d: absorbed=%s, EDGAR HP %d -> %d", c.f, tostring(c.absorbed),
        c.edgarHp, after))
      H.assertEq(c.absorbed, nil, "the bounce was not absorbed by a Runic stance (Ot6BladeNoRunic)")
      H.assertEq(after < c.edgarHp, true, "the bounced Bolt landed on EDGAR")
      local mpAfter = casts[i + 1] and casts[i + 1].celesMp or H.readWord(0x3C08 + celes * 2)
      H.assertEq(mpAfter >= c.celesMp, true, string.format("the bounce cost CELES no MP (%d -> %d)", c.celesMp,
        mpAfter))
    end
  end
  return true
end

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local mark = {}
local function inBattle() return H.battleLoadStarted() end
-- EDGAR's own Bolt: a Magic cast at the monsters, not a counter (a monster's
-- Bolt aims at the party)
local function ownBolt(from)
  for i = from, #casts do
    local c = casts[i]
    if not c.counter and c.b9 ~= 0 and c.b8 == 0 then return c end
  end
end
-- a step whose Bolt is never cast (EDGAR made an Imp or muted before his
-- turn came) ends 1500 frames after its last pick; the battle is fought out
-- and the next starts the steps over
local function step(n, plan, doneFn)
  return {
    H.call(function() mark[n] = { casts = #casts, absorbs = absorbs } end),
    H.kitBattle(plan, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = function()
      if doneFn() then return true end
      local last = H.vars.kit[#H.vars.kit]
      if last ~= nil and ownBolt(mark[n].casts + 1) == nil and H.frame > last.frame + 1500 then
        H.log(string.format("[blade] f%d step %d: no Bolt of EDGAR's in 1500 frames since the last pick", H.frame, n))
        return true
      end
      return false
    end }),
  }
end

-- the three steps, in one battle; a battle that ends before them is left and
-- the next starts them over, up to BATTLES.  Measured at 1a22db99 on this
-- branch's own wor-tomb-v1, over 0-15 encounters used up first
-- (PACE_BURN): 16 successes in 34 battles, the battle counts 1, 2, 1, 5, 3,
-- 1, 3, 3, 3, 1, 4, 1, 1, 1, 3, 1 for burns 0-15
-- (build/attempts/wt/v027-kits/budgets/battle_runicblade_*.out).  The rate
-- is 0.47; its one-sided 95% lower bound is 0.32, and at it BATTLES = 24
-- misses with 0.678^24 = 8.9e-5, under 1e-4 (at the measured rate,
-- 0.53^24 = 2.3e-7).
local BATTLES = 24
local battles, ok = 0, false
local body = {
  H.cond(function() return not inBattle() end, {
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control before the walk", 5),
    H.fieldCare({ tag = "blade: care before the walk", threshold = 0.95 }),
    walkToBattle(),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.waitFrames(30),
  }, {}),
  H.call(function()
    battles = battles + 1
    H.assertEq(battles <= BATTLES, true, string.format("the three steps within %d battles", BATTLES))
    celes, edgar = nil, nil
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == CELES then celes = s elseif id == EDGAR then edgar = s end
    end
    H.assertEq(celes ~= nil and edgar ~= nil, true, "CELES and EDGAR are seated")
    for _, e2 in ipairs({ celes, edgar }) do
      H.assertEq(H.readWord(0x3BF4 + e2 * 2) > 0 and (H.readByte(0x3EE4 + e2 * 2) & 0xC2) == 0, true,
        string.format("seat %d stands (no Wound, Petrify or Zombie: the care before the walk saw to it)", e2))
    end
    H.log(string.format("[blade] battle %d: CELES seat %d (MP %d), EDGAR seat %d (MP %d)", battles, celes,
      H.readWord(0x3C08 + celes * 2), edgar, H.readWord(0x3C08 + edgar * 2)))
  end),
}
local function add(t) for _, s in ipairs(t) do body[#body + 1] = s end end
-- a step's checks run only while the battle is up and CELES stands (a
-- fallen CELES holds no stance: the step is not counted, and the battle is
-- fought out and the next one taken)
local function live(fn)
  return H.call(function()
    if not inBattle() then return end
    if H.readWord(0x3BF4 + celes * 2) == 0 then
      H.log("[blade] CELES has fallen: this step is not counted")
      return
    end
    fn()
  end)
end
-- 1. the control: Runic at 2 BP absorbs and sends nothing back
add(step(1, { { who = CELES, cmd = RUNIC, boost = 2, self = true }, { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function() return ownBolt(mark[1].casts + 1) ~= nil and H.readByte(0x7BCA) ~= 0 end))
add({ H.waitFrames(120), live(function()
  if ownBolt(mark[1].casts + 1) == nil then return end
  H.assertEq(absorbs > mark[1].absorbs, true, "1. CELES absorbed it (RunicEffect enrolled her: Ot6RunicBP)")
  H.assertEq(bounces(mark[1].casts + 1), 0, "1. a Runic raised at 2 BP sends nothing back")
  mark.one = true
end) })
-- 2. the divine: Runic at 3 BP absorbs and sends the Bolt back at EDGAR
add(step(2, { { who = CELES, cmd = RUNIC, boost = 3, self = true }, { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function()
    -- EDGAR's Bolt has been absorbed, and its bounce has come or 900
    -- frames have passed since the absorb (the bounce is CELES's counter,
    -- queued behind the turns already waiting: 556 frames after the absorb
    -- in one run)
    local c = ownBolt(mark[2].casts + 1)
    if c ~= nil and absorbs == mark[2].absorbs then return H.frame > c.f + 1500 end   -- never absorbed
    return c ~= nil and (bounces(mark[2].casts + 1) >= 1 or H.frame > absorbF + 900)
  end))
add({ H.waitFrames(120), live(function()
  if ownBolt(mark[2].casts + 1) == nil then return end
  H.assertEq(absorbs > mark[2].absorbs, true, "2. CELES absorbed EDGAR's Bolt")
  H.assertEq(bounces(mark[2].casts + 1), 1, "2. the 3-BP Runic (RunicBlade) sent EDGAR's Bolt back at him, as "
    .. "CELES's counter")
  if landed(mark[2].casts + 1) then mark.two = true end
end) })
-- 3. again, inside the same stance
add(step(3, { { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function()
    -- EDGAR's Bolt has been absorbed, and its bounce has come or 900
    -- frames have passed since the absorb (the bounce is CELES's counter,
    -- queued behind the turns already waiting: 556 frames after the absorb
    -- in one run)
    local c = ownBolt(mark[3].casts + 1)
    if c ~= nil and absorbs == mark[3].absorbs then return H.frame > c.f + 1500 end   -- never absorbed
    return c ~= nil and (bounces(mark[3].casts + 1) >= 1 or H.frame > absorbF + 900)
  end))
add({ H.waitFrames(120), live(function()
  if ownBolt(mark[3].casts + 1) == nil then return end
  H.assertEq(absorbs > mark[3].absorbs, true, "3. CELES absorbed the second Bolt")
  H.assertEq(bounces(mark[3].casts + 1), 1, "3. a second Bolt inside the stance went back too")
  if landed(mark[3].casts + 1) and mark.one and mark.two then ok = true end
end) })
add({
  H.call(function()
    if ok then
      H.log(string.format("[blade] PASS: a 2-BP Runic absorbs only; a 3-BP Runic absorbs and sends the spell back, "
        .. "again (battle %d)", battles))
    else
      H.log(string.format("[blade] battle %d ended before the three steps: the next", battles))
      mark.one, mark.two = nil, nil
    end
  end),
  H.cond(function() return not ok and inBattle() end, { H.kitBattle({}, {}) }, {}),
})

local steps = {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (RunicBlade learned)")
  end),
  -- PACE_BURN (a lab's global, 0 here): flee that many encounters first, to
  -- vary the encounter history (lib's M.paceToEncounter has the same lever)
  (function()
    local burned, burn = 0, type(PACE_BURN) == "number" and PACE_BURN or 0
    return H.driveUntil(function() return burned >= burn end, 400000, {
      walkToBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "a battle to burn is up", 2),
      H.fleeBattle(9000, { onCantRun = "fight" }),
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control after the burn", 5),
      H.fieldCare({ tag = "blade: care after a burned encounter", threshold = 0.95 }),
      H.call(function() burned = burned + 1; H.log(string.format("[blade] burned encounter %d of %d", burned, burn)) end),
    }, "the encounters PACE_BURN uses up")
  end)(),
  H.driveUntil(function() return ok end, 500000, body, "the three steps in one battle"),
}
H.run({ maxFrames = 600000 }, steps)

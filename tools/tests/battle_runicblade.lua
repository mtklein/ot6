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
-- else Defends.  Nothing is written.  In order:
--   1. CELES raises Runic at 2 BP; EDGAR casts Bolt at a monster: CELES
--      absorbs it (her MP rises) and nothing comes back;
--   2. CELES raises Runic at 3 BP; EDGAR casts Bolt: absorbed, and CELES
--      casts Bolt at EDGAR as a counter ($b1 bit 0) at no MP;
--   3. EDGAR casts Bolt again inside the same stance: absorbed and sent back
--      again.
-- Recorded at every $3410 write (the spell an attack pass is using) with
-- the command, the counter flag and the target mask, and the two MP pools
-- around each cast.  Old-ROM red and mutants:
-- build/attempts/wt/v027-kits/runicblade/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, EDGAR, RUNIC, CMD_MAGIC, BOLT = 0x06, 0x04, 0x0B, 0x02, 0x02

local celes, edgar = nil, nil
local casts = {}   -- every $3410 <- Bolt: { counter, b8, cmd, celesMp, f }
local function arm()
  emu.addMemoryCallback(function(_, v)
    if v ~= BOLT or celes == nil then return end
    casts[#casts + 1] = { counter = (H.readByte(0xB1) & 1) == 1, b8 = H.readByte(0xB8), b9 = H.readByte(0xB9),
      cmd = H.readByte(0x3A7C), celesMp = H.readWord(0x3C08 + celes * 2), edgarMp = H.readWord(0x3C08 + edgar * 2),
      f = H.frame }
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
local function step(n, plan, done)
  return {
    H.call(function() mark[n] = { casts = #casts, celesMp = H.readWord(0x3C08 + celes * 2) } end),
    H.kitBattle(plan, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = done }),
  }
end

local steps = {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    arm()
    H.assertEq((H.readByte(0x1E80 + (0x68 >> 3)) >> (0x68 & 7)) & 1, 1,
      "switch $0068 is set: the Magitek factory's way out has opened (RunicBlade learned)")
  end),
  walkToBattle(),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.waitFrames(30),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == CELES then celes = s elseif id == EDGAR then edgar = s end
    end
    H.assertEq(celes ~= nil and edgar ~= nil, true, "CELES and EDGAR are seated")
    H.log(string.format("[blade] CELES seat %d (MP %d), EDGAR seat %d (MP %d)", celes,
      H.readWord(0x3C08 + celes * 2), edgar, H.readWord(0x3C08 + edgar * 2)))
  end),
}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end
-- 1. the control: Runic at 2 BP absorbs and sends nothing back
add(step(1, { { who = CELES, cmd = RUNIC, boost = 2, self = true }, { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function() return #casts > mark[1].casts and H.readByte(0x3E9D + edgar * 2) == 0 and H.readByte(0x7BCA) ~= 0 end))
add({
  H.waitFrames(120),
  H.call(function()
    local c = casts[mark[1].casts + 1]
    H.assertEq(c ~= nil and not c.counter, true, "1. EDGAR's own Bolt was cast")
    H.assertEq(H.readWord(0x3C08 + celes * 2) > mark[1].celesMp, true, string.format("1. CELES absorbed it: MP %d "
      .. "-> %d", mark[1].celesMp, H.readWord(0x3C08 + celes * 2)))
    H.assertEq(bounces(mark[1].casts + 1), 0, "1. a Runic raised at 2 BP sends nothing back")
  end),
})
-- 2. the divine: Runic at 3 BP absorbs and sends the Bolt back at EDGAR
add(step(2, { { who = CELES, cmd = RUNIC, boost = 3, self = true }, { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function() return bounces(mark[2].casts + 1) >= 1 end))
add({
  H.call(function()
    local n = bounces(mark[2].casts + 1)
    H.assertEq(n, 1, "2. the 3-BP Runic (RunicBlade) sent EDGAR's Bolt back at him, as CELES's counter")
    local c
    for i = mark[2].casts + 1, #casts do if casts[i].counter then c = casts[i] end end
    H.assertEq(c.cmd, CMD_MAGIC, "2. the bounce is a Magic cast")
  end),
})
-- 3. again, inside the same stance
add(step(3, { { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT } },
  function() return bounces(mark[3].casts + 1) >= 1 end))
add({
  H.call(function()
    H.assertEq(bounces(mark[3].casts + 1), 1, "3. a second Bolt inside the stance went back too")
    H.log("[blade] PASS: a 2-BP Runic absorbs only; a 3-BP Runic absorbs and sends the spell back, again and again")
  end),
})
H.run({ maxFrames = 200000 }, steps)

-- @suite slow
-- battle_esperconductorfight.lua -- Conductor's command gate (#328 review): a lightning hit that is not a Magic or
-- X-Magic cast takes no extra shield, even from a character who holds Ramuh's signature (ot6_esper.asm
-- Ot6Conductor).  battle_esperconductor is the positive (EDGAR's Bolt takes two).
--
-- Continue fire-out-v1 (TERRA, LOCKE, STRAGO; LOCKE wields the ThunderBlade, a lightning weapon).  Staged
-- (declared in state_write_waivers.txt): LOCKE's Ramuh count at 500 on the live esper page.  Random battles on the
-- plain outside Thamasa until one holds a standing, unbroken monster weak to lightning with two shields or more;
-- there LOCKE Fights it (unboosted, through the real menu) while the others Defend.  Every write to that monster's
-- shield count during the Fight takes exactly one shield: the weakness's chip, a class chip, never a chip and
-- Conductor's extra together (the mutant without the gate takes two in the element chip's one write).  A battle
-- with no such monster is fought out and the next taken, within the battles that meet every slot of the zone's
-- pool at 99%.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, THUNDERBLADE, CMD_FIGHT = 1, 0x0F, 0x00
local LIVE = 0x317C00
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local A, B, tries, done, BUDGET = nil, nil, 0, false, nil
local tgt, writes, last, plan = nil, {}, nil, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

local function pick()
  tgt, writes, plan = nil, {}, {}
  for s = 0, 5 do
    local e = 8 + s * 2
    local hp = H.readWord(0x3BF4 + e)
    if tgt == nil and hp > 0 and hp < 0xFFFF and (H.readByte(0x3BE0 + e) & 0x04) ~= 0
        and H.readByte(0x3E38 + e) >= 2 and H.readByte(0x3E88 + e) == 0 then
      tgt = { slot = s, ent = e }
      last = H.readByte(0x3E38 + e)
    end
  end
  H.log(string.format("[cfight] battle %d: formation $%03X, %s", tries, H.readWord(0x3ED4),
    tgt and string.format("slot %d is weak to lightning with %d shields", tgt.slot, last) or "none: fought out"))
  if tgt then plan = { { who = LOCKE, cmd = CMD_FIGHT, boost = 0, slot = tgt.slot } } end
end

H.run({ maxFrames = 700000 }, {
  -- the cold Continue battle_lockekit uses for this save
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and bright() >= 15 and H.worldHasControl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    H.assertEq(H.readByte(0x1600 + 37 * LOCKE + 0x1F), THUNDERBLADE, "LOCKE wields the ThunderBlade")
    local a = LIVE + 0x10 + (LOCKE * 26 + 0) * 2
    emu.write(a, 500 & 0xFF, emu.memType.snesMemory)
    emu.write(a + 1, 500 >> 8, emu.memType.snesMemory)
    emu.addMemoryCallback(function(addr, v)
      if tgt and (addr & 0xFFFF) == 0x3E38 + tgt.ent then writes[#writes + 1] = { from = last, to = v }; last = v end
    end, emu.callbackType.write, 0x7E3E38, 0x7E3E38 + 0x14)
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
    local pool = H.encounterPool(H.worldEncounterGroup(B[1], B[2]))
    local pmin = 1
    for slot = 1, 4 do local sl = pool[slot]; if sl and sl.odds and sl.odds > 0 then pmin = math.min(pmin, sl.odds / 256) end end
    BUDGET = math.ceil(math.log(0.01) / math.log(1 - pmin))
    H.log(string.format("[cfight] the rarest slot %.3f: budget %d battles", pmin, BUDGET))
  end),
  H.driveUntil(function() return done end, 650000, {
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, "a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.waitFrames(30),
    H.call(function()
      tries = tries + 1
      H.assertEq(tries <= BUDGET, true, string.format("a shielded lightning-weak monster within %d battles", BUDGET))
      pick()
    end),
    H.cond(function() return tgt ~= nil end, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000 }),
      H.waitUntilSoft(function() return #writes > 0 or not H.battleLoadStarted() end, 2400, "the Fight lands"),
      H.waitFrames(40),
      H.call(function()
        local t = {}
        for _, w in ipairs(writes) do t[#t + 1] = string.format("%d->%d", w.from, w.to) end
        H.log(string.format("[cfight] slot %d's shield writes during the Fight: %s", tgt.slot, table.concat(t, ", ")))
        if #writes == 0 then H.log("[cfight] the Fight took no shield (missed): the next battle"); tgt = nil; return end
        for _, w in ipairs(writes) do
          H.assertEq(w.from - w.to, 1, "a ThunderBlade Fight's shield write takes one (no Conductor extra off Magic)")
        end
        done, tgt = true, nil
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    }, { H.fightBattleByMenu(40000) }),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.fieldCare({ tag = "care between battles" }),
  }, "a lightning-weak monster takes LOCKE's ThunderBlade"),
  H.logStep("[cfight] PASS: a lightning Fight from the signature's holder takes one shield a write"),
})

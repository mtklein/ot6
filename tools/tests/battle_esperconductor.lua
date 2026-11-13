-- @suite slow
-- battle_esperconductor.lua -- Ramuh's signature, Conductor (#328, plan A: docs/design/esper-rework.md;
-- ot6_esper.asm Ot6Conductor): the wearer's lightning spell takes one more shield from a monster weak to lightning.
--
-- Continue post-opera-v1 (LOCKE, EDGAR, SABIN, CELES; Ramuh owned).  Ramuh goes on EDGAR through the Skills menu
-- when nobody seated wears it (the stone grants Bolt).  Staged (declared in state_write_waivers.txt, a mechanism
-- expedient: a signature takes 500 Magic Points in one stone): EDGAR's Ramuh count at 500 on the live esper page.
-- Then random battles by the opera house until one holds a standing, unbroken monster weak to lightning with two
-- shields or more; there EDGAR casts Bolt (unboosted) at it through the real menu (H.kitBattle) while the others
-- Defend.  The property, read from every write to that monster's shield count ($3E38 + entity) during EDGAR's
-- cast: the Bolt takes two shields where an unboosted weakness hit takes one.  A battle with no such monster is
-- fought out and the next taken, up to twelve.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, RAMUH, BOLT, CMD_MAGIC = 4, 0, 0x02, 0x02
local LIVE = 0x317C00
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function pos(c) return (H.readByte(0x1850 + c) >> 3) & 3 end

local A, B, tries, done = nil, nil, 0, false
local tgt, writes, plan = nil, {}, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

local function arm()
  emu.addMemoryCallback(function(addr, v)
    if tgt and addr == 0x7E3E38 + tgt.ent then writes[#writes + 1] = v end
  end, emu.callbackType.write, 0x7E3E38, 0x7E3E38 + 0x14)
end

local function pick()
  tgt, writes, plan = nil, {}, {}
  for s = 0, 5 do
    local e = 8 + s * 2
    local hp = H.readWord(0x3BF4 + e)
    local weak = H.readByte(0x3BE0 + e)
    local sh = H.readByte(0x3E38 + e)
    if tgt == nil and hp > 0 and hp < 0xFFFF and (weak & 0x04) ~= 0 and sh >= 2 and H.readByte(0x3E88 + e) == 0 then
      tgt = { slot = s, ent = e, sh0 = sh }
    end
  end
  H.log(string.format("[conductor] battle %d: formation $%03X, %s", tries, H.readWord(0x3ED4),
    tgt and string.format("slot %d is weak to lightning with %d shields", tgt.slot, tgt.sh0) or "no shielded "
      .. "lightning-weak monster: fought out"))
  if tgt then plan = { { who = EDGAR, cmd = CMD_MAGIC, spell = BOLT, boost = 0, slot = tgt.slot } } end
end

H.run({ maxFrames = 700000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.lazy(function()
    for c = 0, 13 do if seated(c) and H.readByte(0x1600 + 37 * c + 0x1E) == RAMUH then
      H.assertEq(c, EDGAR, "Ramuh is EDGAR's, or nobody's")
      return H.logStep("[conductor] EDGAR wears Ramuh")
    end end
    H.assertEq(seated(EDGAR), true, "EDGAR is seated")
    return H.equipEsper(function() return pos(EDGAR) end, RAMUH, { tag = "Ramuh -> EDGAR" })
  end),
  H.call(function()
    arm()
    local a = LIVE + 0x10 + (EDGAR * 26 + 0) * 2
    emu.write(a, 500 & 0xFF, emu.memType.snesMemory)
    emu.write(a + 1, 500 >> 8, emu.memType.snesMemory)
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
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
      H.assertEq(tries <= 12, true, "a shielded lightning-weak monster within twelve battles")
      pick()
    end),
    H.cond(function() return tgt ~= nil end,
      { H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000 }),
        H.call(function()
          H.log(string.format("[conductor] slot %d's shield writes during the cast: %s", tgt.slot,
            table.concat(writes, ",")))
          if #writes == 0 then
            H.log("[conductor] the Bolt took no shield (it did not land on the target): the next battle")
            return
          end
          H.assertEq(tgt.sh0 - writes[#writes], 2, "EDGAR's Bolt on a lightning-weak monster took two shields "
            .. "(one for the weakness, one for Conductor)")
          done, tgt = true, nil
        end),
        H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}) },
      { H.kitBattle({}, {}) }),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
  }, "a lightning-weak monster takes EDGAR's Bolt"),
  H.logStep("[conductor] PASS: the signature's Bolt takes two shields from a lightning-weak monster"),
})

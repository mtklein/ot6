-- @suite slow
-- battle_espersigs.lua -- three esper signatures that are new code reach the battle (#328, plan A:
-- docs/design/esper-rework.md; ot6_esper.asm Ot6EsperBattleInit / Ot6EsperImmune): Carbunkl's Facet (the boost
-- bank opens at two points), Phoenix's Rebirth (the battle opens under Life 3) and Fenrir's immunity to Stop
-- and Slow (UpdateImmuneStatus's status-3 mask, $3330, loses those bits, and keeps Haste's).
--
-- Continue post-opera-v1 (LOCKE, EDGAR, SABIN, CELES seated).  Staged (declared in state_write_waivers.txt, a
-- mechanism expedient: a signature takes 500 Magic Points in one stone, most of a World of Ruin): on the live
-- esper page ($317C00), the first seated member holds Carbunkl's signature, the second Phoenix's, the third
-- Fenrir's, and the fourth none (the control).  Then pace into a random battle on the world map and read, at
-- the first frame the battle is up and before anyone acts, against battle A, fought first with nothing staged:
--   Facet:   the first member's bank (OT6_BP_CLASS, $3E9C + seat*2) is 2; every other member's is 1;
--   Rebirth: the second member's status 4 ($3EF9 + seat*2) carries Life 3 ($04); nobody else's does;
--   Fenrir:  the third member's $3330 (a set bit lets the status land) has Stop ($10) and Slow ($04) clear and
--            Haste ($08) set; every other member's has all three set.
-- The battle is then fought out by the driver.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local LIVE = 0x317C00
local CARBUNKL, PHOENIX, FENRIR = 18, 25, 23        -- counter slots
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function stage(a, slot, n)
  local addr = LIVE + 0x10 + (a * 26 + slot) * 2
  emu.write(addr, n & 0xFF, emu.memType.snesMemory)
  emu.write(addr + 1, n >> 8, emu.memType.snesMemory)
end

local who, base = {}, nil
local A, B = nil, nil
local function open(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 1),
  })
end
local function read(tag)
  local t = {}
  for s = 0, 3 do
    local a = H.readByte(0x3ED8 + s * 2)
    if a < 12 then
      local o = s * 2
      t[a] = { bp = H.readByte(0x3E9C + o), st4 = H.readByte(0x3EF9 + o), mask = H.readByte(0x3330 + o) }
      H.log(string.format("[sigs] %s: seat %d %s: bank %d, status 4 $%02X, status-3 mask $%02X", tag, s, NAMES[a],
        t[a].bp, t[a].st4, t[a].mask))
    end
  end
  return t
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    local m = {}
    for c = 0, 11 do if seated(c) then m[#m + 1] = c end end
    H.assertEq(#m >= 4, true, "four seated members")
    who = { facet = m[1], rebirth = m[2], fenrir = m[3], none = m[4] }
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
  end),
  -- battle A: nobody holds a signature (the baseline every member's own gear sets)
  open("A"),
  H.call(function() base = read("A") end),
  H.fightBattleByMenu(40000),
  H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
  H.call(function()
    stage(who.facet, CARBUNKL, 500)
    stage(who.rebirth, PHOENIX, 500)
    stage(who.fenrir, FENRIR, 500)
    H.log(string.format("[sigs] staged: Facet %s, Rebirth %s, Fenrir %s; control %s", NAMES[who.facet],
      NAMES[who.rebirth], NAMES[who.fenrir], NAMES[who.none]))
  end),
  open("B"),
  H.call(function()
    local t = read("B")
    for a, r in pairs(t) do
      local b = base[a]
      H.assertEq(b ~= nil, true, NAMES[a] .. " was in battle A too")
      H.assertEq(b.bp, 1, NAMES[a] .. "'s bank opened at 1 in battle A")
      H.assertEq(r.bp, a == who.facet and 2 or 1, NAMES[a] .. "'s bank at the open of B (Facet: 2, else 1)")
      H.assertEq(b.st4 & 0x04, 0, NAMES[a] .. " opened battle A without Life 3")
      H.assertEq(r.st4 & 0x04, a == who.rebirth and 0x04 or 0, NAMES[a] .. "'s Life 3 at the open of B (Rebirth)")
      H.assertEq(r.mask, a == who.fenrir and (b.mask & ~0x14 & 0xFF) or b.mask, NAMES[a] .. "'s status-3 mask in B: "
        .. (a == who.fenrir and "battle A's less Stop and Slow, Haste as it was" or "battle A's"))
    end
    H.assertEq(t[who.fenrir] ~= nil and (base[who.fenrir].mask & 0x14) ~= 0, true,
      "the Fenrir holder could be stopped or slowed in battle A (the property is not vacuous)")
  end),
  H.fightBattleByMenu(40000),
  H.logStep("[sigs] PASS: Facet, Rebirth and Fenrir's immunity at the battle's open, against a baseline battle"),
})

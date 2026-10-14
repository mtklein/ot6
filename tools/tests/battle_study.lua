-- @suite slow
-- battle_study.lua -- Strago's full boost: his Scan at 3 BP learns every lore
-- the monsters on the field could cast (#432).
--
-- ot6_analyze.asm (Ot6StudyOne): with all three points pending, Strago's
-- Scan ORs each present body's Ot6StudyTbl row (the lores its AI script
-- names; tools/check_study_table.py holds the table to the scripts) into
-- $3A84, vanilla's "lores learned this battle", less what $1D29 knows, and
-- the victory screen teaches them.  It costs 99 MP (Ot6MagicPrice).  Under
-- three points it is Scan (battle_analyze).
--
-- Played: Continue fire-out-v1 (STRAGO seated) and walk the plain east of
-- Thamasa, where world group 25 deals the Chimera (its script casts Aqua
-- Rake, lore 3).  STRAGO knows Aqua Rake here, so before the first battle
-- one declared write clears that bit of $1D29 (state_write_waivers.txt): no
-- fixture seats STRAGO beside a lore caster whose lore he lacks.  Then, each
-- in a battle that fields a Chimera, through the real menu (H.kitBattle):
--   1. STRAGO's Scan at 2 BP: Ot6StudyOne writes nothing; the battle is
--      fought out;
--   2. STRAGO's Scan at 3 BP: Ot6StudyOne's writes to $3A84 add exactly the
--      present species' lores he lacks (Aqua Rake), the cast costs 99 MP,
--      and after the victory $1D29 holds Aqua Rake again.
-- Everyone else Defends until the cast resolves.  A battle without a
-- Chimera, or where STRAGO cannot cast, is fought out and the next taken.
-- Old-ROM red and mutants: build/attempts/wt/v030-plan-kits/study/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local STRAGO, SCAN, CMD_MAGIC, CHIMERA = 0x07, 0x18, 0x02, 0x01F
local STUDY_MP = 99

local function present(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 end
local function species(s) return H.readWord(0x57C0 + s * 2) end
local function lores()
  return H.readByte(0x1D29) | H.readByte(0x1D2A) << 8 | H.readByte(0x1D2B) << 16
end
local function pending()
  return H.readByte(0x3A84) | H.readByte(0x3A85) << 8 | H.readByte(0x3A86) << 16
end
-- a species' row of Ot6StudyTbl, read out of the built ROM
local function row(sp)
  local a = H.sym("Ot6StudyTbl") & 0x3FFFFF
  while true do
    local s = H.readRomByte(a) | H.readRomByte(a + 1) << 8
    if s == 0xFFFF then return 0 end
    if s == sp then
      return H.readRomByte(a + 2) | H.readRomByte(a + 3) << 8 | H.readRomByte(a + 4) << 16
    end
    a = a + 5
  end
end

local seat, rec, stage, battles, mode, plan = nil, nil, 1, 0, nil, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function inStudy(st)
  local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
  local a = H.sym("Ot6StudyOne")
  return pc >= a and pc < a + 96
end
local function arm()
  emu.addMemoryCallback(function(addr, v)
    if rec == nil or rec.ended or not inStudy(emu.getState()) then return end
    rec.studied = rec.studied | (v << (8 * (addr - 0x7E3A84)))
  end, emu.callbackType.write, 0x7E3A84, 0x7E3A86)
  emu.addMemoryCallback(function(_, v)
    if v ~= SCAN or seat == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    local e = seat * 2
    local want = 0
    for s = 0, 5 do if present(s) then want = want | row(species(s)) end end
    rec = { pend = H.readByte(0x3E9D + e), mp0 = H.readWord(0x3C08 + e), known = lores(), pend0 = pending(),
      want = want & ~lores() & 0xFFFFFF, studied = 0, f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then
      rec.ended, rec.mp1, rec.pend1 = H.frame, H.readWord(0x3C08 + seat * 2), pending()
    end
  end, emu.callbackType.exec, ae, ae)
end
local function closed() return rec ~= nil and rec.ended ~= nil and H.frame > rec.ended + 30 end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= 16, true, "the two counted casts within 16 battles")
  seat, plan, mode, rec = nil, {}, "cast", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == STRAGO then seat = s end end
  H.assertEq(seat ~= nil, true, "STRAGO is seated")
  local chim, ids = false, {}
  for s = 0, 5 do
    if present(s) then
      ids[#ids + 1] = string.format("%d:$%03X", s, species(s))
      if species(s) == CHIMERA then chim = true end
    end
  end
  local e = seat * 2
  local can = H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0 and H.readWord(0x3C08 + e) >= STUDY_MP
  H.log(string.format("[study] battle %d, stage %d: %s; STRAGO seat %d MP %d; lores $%06X", battles, stage,
    table.concat(ids, " "), seat, H.readWord(0x3C08 + e), lores()))
  if not chim or not can then
    mode = "fightout"
    H.log("[study] no Chimera here, or STRAGO cannot cast: fought out, the next battle taken")
    return
  end
  plan = { { who = STRAGO, cmd = CMD_MAGIC, spell = SCAN, boost = stage == 1 and 2 or 3 } }
end

local home, away
local function lap()
  local goal, wplan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then wplan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if wplan == nil or idx > #wplan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        wplan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not wplan or #wplan == 0 then wplan = nil; H.setPad({}) return end
      end
      local dir = wplan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

H.run({ maxFrames = 900000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.worldMode() and bright() >= 15 and H.worldHasControl()
    end, 6000, {
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
    H.assertEq((H.readByte(0x1850 + STRAGO) & 7) ~= 0, true, "STRAGO is in the party")
    H.assertEq(row(CHIMERA), 0x000008, "Ot6StudyTbl's Chimera row is Aqua Rake alone (its script's one lore)")
    H.assertEq(lores() & 0x08, 0x08, "STRAGO knows Aqua Rake as saved")
    -- the one declared write: Aqua Rake unlearned, so the Chimera has a lore to teach
    H.writeByte(0x1D29, H.readByte(0x1D29) & 0xF7)
    H.log(string.format("[study] staged: Aqua Rake cleared from $1D29 -> lores $%06X", lores()))
    arm()
  end),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    -- world group 25 (the Chimera's) east of the Continue tile is the four
    -- tiles (250-251, 126-127) (build/attempts/wt/v030-plan-kits/study/
    -- g25.txt, route_data's world_group over world 0's tile props): the lap
    -- runs between two of them
    home, away = { 250, 126 }, { 251, 127 }
    H.assertEq(H.worldBfs(home[1], home[2]) ~= nil, true, "the lap's tiles are reachable")
  end),
  H.driveUntil(function() return stage > 2 end, 850000, {
    -- field care between battles, as a player heals (guidelines.md): the
    -- first run walked TERRA in at 60 HP, poisoned, and lost the fight-out
    H.cond(function() return not H.battleLoadStarted() end,
      { H.fieldCare({ tag = "study" }), lap(), H.release() }, {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = closed }),
      H.call(function()
        if not closed() then
          H.log("[study] the battle ended before the cast resolved: not counted")
          mode = "skip"
          return
        end
        H.log(string.format("[study] cast at %d BP (f%d): MP %d -> %d; want $%06X; Ot6StudyOne wrote $%06X; "
          .. "$3A84 $%06X -> $%06X", rec.pend, rec.f, rec.mp0, rec.mp1, rec.want, rec.studied, rec.pend0, rec.pend1))
        if stage == 1 then
          H.assertEq(rec.pend, 2, "the cast ran at the 2 BP planned")
          H.assertEq(rec.studied, 0, "at 2 BP the study wrote nothing (the full boost is its one gate)")
          H.assertEq(rec.mp0 - rec.mp1, H.battleSpellPrice(seat, SCAN, 2), "at 2 BP Scan pays its boosted price")
        else
          H.assertEq(rec.pend, 3, "the cast ran at the 3 BP planned")
          H.assertEq(rec.want ~= 0, true, "precondition: a present species can teach a lore STRAGO lacks")
          H.assertEq(rec.studied & ~rec.pend0 & 0xFFFFFF, rec.want & ~rec.pend0 & 0xFFFFFF,
            "at 3 BP the study added exactly the present species' lores he lacks")
          H.assertEq(rec.pend1 & rec.want, rec.want, "$3A84 holds them at the action's end")
          H.assertEq(rec.mp0 - rec.mp1, STUDY_MP, "the study cost the shared ceiling, 99 MP")
        end
      end),
      H.cond(function() return mode == "cast" and H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
      H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
        "back on the world map", 5),
      H.call(function()
        if mode ~= "cast" or rec == nil or not rec.ended then return end
        local k = lores()
        H.log(string.format("[study] after the battle: lores $%06X", k))
        if stage == 1 then
          if k & 0x08 ~= 0 then
            H.log("[study] the Chimera taught Aqua Rake the vanilla way: cleared again for stage 2")
            H.writeByte(0x1D29, H.readByte(0x1D29) & 0xF7)
          end
        else
          H.assertEq(k & rec.want, rec.want, "the victory taught the studied lores ($1D29)")
        end
        stage = stage + 1
      end),
    }),
  }, "the two counted casts"),
  H.call(function()
    H.log("[study] PASS: at 2 BP Scan studies nothing; at 3 BP it learns exactly the present species' lores, "
      .. "99 MP, taught at the victory")
  end),
})

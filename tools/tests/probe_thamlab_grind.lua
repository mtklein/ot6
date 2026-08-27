-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- probe_thamlab_grind.lua -- Thamasa fire lab, HEALTHY-LEVEL fixture baker.
--
-- Hand-run instrument (probe_): probe_thamlab_bake.lua's route with one
-- big insertion -- a world-map XP grind on Crescent Island before the inn
-- fire -- so the two lab fixtures are banked at the route research's
-- "healthy" levels (L22-24) instead of the routed L15-17.  The confirm
-- step of the level-gap hypothesis chain: at healthy levels, does the
-- FlameEater fight become comfortable rather than a seed lottery?
--
-- Flow (the bake's own step list, reordered around the grind):
--   1. cold Continue the thamasa-night-v1 checkpoint -> world (249,128)
--   2. into town, PREP (gear + SHIVA/MADUIN espers + rows), shop trip #1
--      (supplies for the grind)
--   3. back OUT to the world map; GRIND: pace two tiles, fight every
--      random encounter with the lib fight driver's nuke repertoire
--      (nuke={Ice2,Ice}, nukeLore={Aqua Rake}), care stop after every
--      battle (M.newCareDriver, worldNavTo's own care contract), until
--      TERRA and LOCKE both reach GRIND_MIN (default 22).  STRAGO's join
--      level follows: char_prop at the fire join sets his level to the
--      AVERAGE of the available characters (field/event.asm EventCmd_40 ->
--      CalcAverageLevel; measured join at 16 == avg(15,17) on the routed
--      bake), so leveling TERRA/LOCKE lifts him too.
--   4. shop trip #2 (top the bag back up to the bake's own 30/15/20)
--   5. the bake's route verbatim: inn -> fire -> STRAGO joins -> burning
--      house -> pre-ambush top-off -> bank thamlab_ambush_healthy.mss ->
--      ambush ladder (with the POSITIONAL lore-row fix measured in
--      probe_thamlab_ambush_fix.lua: row == loreId, not the compacted
--      model) -> corridors/rods -> bank thamlab_flame_healthy.mss.
--
-- Crescent Island world pool at sector 156 (X 224-255, Y 128-159), from
-- world_battle_group.dat / rand_battle_group.dat / battle_monsters.dat /
-- monster_prop.dat (+12 XP, +16 level):
--   grass (bg0, group 24): Baskervor L22 465xp/750hp -- forms 160 (x1,
--     31.25%), 191 (x2, 31.25%), 162 (Cephaler+Baskervor 679xp, 37.5%);
--     NO pincers.  Expected ~690 xp/fight raw.
--   forest (bg1, group 25): Chimera L22 1144xp/2237hp forms; richer but
--     Chimera is a wipe risk at L15.
--   desert (bg2, group 26): FossilFang/Bug, pincer-capable.
-- OT6 pays random battles x2 xp/gil (Ot6RewardMulW $20/16) and runs the
-- danger counter at 0.5x (Ot6DangerMulW $08/16).  XP splits over the 3
-- live allies (TERRA/LOCKE/SHADOW).  L15->L22 is ~20.4k xp/char
-- (LevelUpExp entries 16..22 x8), so expect ~45 grass fights; the log
-- reports what the pool actually pays.
--
-- Run (LONG -- the grind alone is ~45 fights; owner has made time a
-- non-factor):
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/thamasa-night-v1 \
--   OT6_TIMEOUT=7200 tools/tests/run.sh tools/tests/probe_thamlab_grind.lua \
--   build/thamlab/grind_bake.log
--
-- Smoke form (sed): @GRINDMIN@ -> a low level, @SUF@ -> _smoke so the
-- banked fixtures don't collide with the real ones.

local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, STRAGO, SHADOW = 0, 1, 7, 3
local FIRE_ROD, ICE_ROD = 0x35, 0x36
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL, ICE2_SPELL = 0x01, 0x06
local AQUA_RAKE_LORE_ID = 3

local GRIND_MIN = tonumber("@GRINDMIN@") or 22
local SUF = ("@SUF@"):find("@") and "" or "@SUF@"

-- Same PREP as the bake: 4-piece loadouts and Ice-granting espers.
local TERRA_GEAR = { { 0, 0x0E }, { 1, 0x5C }, { 2, 0x6E }, { 3, 0x89 } }
  -- Blizzard(w) / Mithril Shld(sh) / Bandana(he) / Mithril Vest(ar)
local LOCKE_GEAR = { { 0, 0x0F }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } }
  -- ThunderBlade(w) / Buckler(sh) / Head Band(he) / Kung Fu Suit(ar)
local SHIVA_ESPER, MADUIN_ESPER, BISMARK_ESPER = 2, 6, 7
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- 37-byte character record (ff6/notes/field-ram.txt:885+): +$08 level,
-- +$11 experience (3 bytes)
local function lvl(c) return H.readByte(0x1600 + 37 * c + 0x08) end
local function xpOf(c)
  local b = 0x1600 + 37 * c + 0x11
  return H.readByte(b) + H.readByte(b + 1) * 256 + H.readByte(b + 2) * 65536
end
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- gen_thamasa_arrive's crossDoor, unchanged (via the bake)
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, avoid = opts.avoid,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Live NPC lookup (the bake's findNpc/objAt/chaseTalkLazy, unchanged)
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local function findNpc(x, y, fallback)
  local best, bestD = nil, nil
  for i = 16, 31 do
    local ox, oy = objAt(i)
    local d = math.abs(ox - x) + math.abs(oy - y)
    if (ox ~= 0 or oy ~= 0) and (not bestD or d < bestD) then
      best, bestD = i, d
    end
  end
  H.log(string.format(
    "[npc] nearest object to (%d,%d): slot $%02X at distance %d (fallback $%02X)",
    x, y, best or 0, bestD or -1, fallback))
  return best or fallback
end
local function chaseTalkLazy(idxFn, maxFrames, what, opts)
  opts = opts or {}
  local ph, hb = 0, 0
  local done = opts.done or function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end
  return H.driveUntil(done, maxFrames or 9000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then H.killbit(s) end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local objIdx = idxFn()
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best, bestC
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best, bestC = p, c end
      end
      if hb % 300 == 0 then
        H.log(string.format(
          "[chaseTalkLazy dbg] %s: f%d party=(%d,%d) obj$%02X=(%d,%d) " ..
          "best=%s bestLen=%s", what, H.frame, px, py, objIdx, ox, oy,
          bestC and string.format("(%d,%d)", bestC[1], bestC[2]) or "NONE",
          best and tostring(#best) or "-"))
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what or "chaseTalkLazy")
end

local function creepXY(tx, ty, step)
  step = step or 14
  local function pt()
    local px, py = H.fieldX(), H.fieldY()
    local dx, dy = tx - px, ty - py
    local dist = math.abs(dx) + math.abs(dy)
    if dist <= step or dist == 0 then return tx, ty end
    return px + math.floor(dx * step / dist), py + math.floor(dy * step / dist)
  end
  return function() return (pt()) end,
         function() local _, y = pt(); return y end
end
local function creepNav(tx, ty, opts, step)
  local fx, fy = creepXY(tx, ty, step)
  return H.navTo(fx, fy, opts)
end

local function care(what)
  return seq({
    H.waitUntilSoft(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 1200, "care " .. what),
    H.cond(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end, {
      H.waitFrames(60),
      H.fieldCare({ tag = "care " .. what, threshold = 1.0 }),
    }, {
      H.logStep(function()
        return string.format("[care %s] SKIPPED -- not settled at (%d,%d) map %d",
          what, H.fieldX(), H.fieldY(), map())
      end),
    }),
  })
end

-- the bake's chestAuto, unchanged
local CHEST_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function chestAuto(cx, cy, bit, what, item)
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(CHEST_CAND) do
        local sx, sy = cx + c[1], cy + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { cx, cy + 1, "up" }
      H.log(string.format("[chest] (%d,%d) %s: staging (%d,%d) face %s",
        cx, cy, what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local tag = string.format("chest bit %d (%s)", bit, what)
  local before
  local aPh = 0
  return H.cond(function() return not H.chestOpen(bit) end, {
    H.call(function() pick = nil end),
    H.navTo(
      function() local p = stage(); local fx = creepXY(p[1], p[2]); return fx() end,
      function() local p = stage(); local _, fy = creepXY(p[1], p[2]); return fy() end,
      { maxFrames = 40000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, healPercent = 85,
        magic = { [TERRA] = { spell = ICE_SPELL, boost = false },
                [LOCKE] = { spell = ICE_SPELL, boost = false } } }),
    H.call(function() before = item and H.invCountOf(item) or nil end),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, tag .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.dialogWaiting() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": the chest answered"),
    H.driveUntil(function() return not H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": dialog dismissed"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.chestOpen(bit), true, tag .. ": treasure bit set")
      if item then
        local now = H.invCountOf(item)
        H.assertEq(now, before + 1,
          string.format("%s: bag %d -> %d of item $%02X", tag, before, now, item))
      end
      H.log("[chest] " .. tag .. ": OPENED")
    end),
  }, {
    H.call(function()
      H.log(string.format("[chest] %s: already open (rerun), skipping", tag))
    end),
  })
end

-- the bake's shop steps, wrapped so the trip can run twice (pre- and
-- post-grind top-up; H.buyItem's qty functions are count-based, so the
-- second trip only buys what the grind consumed)
local SHOP_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { 0, 2, "up" }, { 0, -2, "down" }, { -2, 0, "right" }, { 2, 0, "left" },
}
local function shopTalk(nx, ny, what)
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(SHOP_CAND) do
        local sx, sy = nx + c[1], ny + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { nx, ny + 1, "up" }
      H.log(string.format("[shop] %s: staging (%d,%d) face %s",
        what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local aPh = 0
  return seq({
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true }),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, what .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.readByte(0x0026) == 0x25 end, 3000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true, [stage()[3]] = true } or {})
      end),
    }, what .. ": shop opens"),
    H.call(function()
      H.log(string.format("[shop] %s: open at f%d, gil=%d", what, H.frame, gil()))
    end),
  })
end
local function shopClose(what)
  local ph = 0
  return seq({
    H.driveUntil(function()
      return H.hasControl() and H.readByte(0x0026) ~= 0x25
         and H.readByte(0x0026) ~= 0x26 and H.readByte(0x0026) ~= 0x27
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { b = true } or {})
      end),
    }, what .. ": shop closed"),
    H.release(),
    H.waitFrames(30),
  })
end
local function shopTrip(tag)
  local what = "Thamasa item shop (" .. tag .. ")"
  return seq({
    crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44) " .. tag),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
      "shop interior settled before pathfinding"),
    H.waitFrames(150),
    shopTalk(36, 39, what),
    H.buyItem(TONIC, 0, function() return 30 - H.invCountOf(TONIC) end, "TONIC to 30"),
    H.buyItem(POTION, 1, function() return 15 - H.invCountOf(POTION) end, "POTION to 15"),
    H.buyItem(FENIX_DOWN, 6, function() return 20 - H.invCountOf(FENIX_DOWN) end,
      "FENIX DOWN to 20"),
    H.call(function()
      H.log(string.format(
        "[shop] %s done: tonic=%d potion=%d fenix=%d gil=%d f%d",
        what, H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
        gil(), H.frame))
    end),
    shopClose(what),
    crossDoor(36, 45, 343, 26, 39, "item shop door 347(36,45)->343(26,39), return " .. tag),
  })
end

-- --------------------------------------------------------------- GRIND --
-- One self-contained per-frame kernel (worldNavTo's shape, simplified to
-- a two-tile pace): walk home<->away on the world map outside Thamasa,
-- fight every random encounter with the lib fight driver's nuke
-- repertoire, run a care stop after every battle, and stop once TERRA and
-- LOCKE both read >= GRIND_MIN and the party is settled back on the home
-- tile.  All input-driven; no state writes.
local grindStats = {
  fights = 0, bframes = 0, careN = 0, legs = 0,
  f0 = nil, xp0 = nil, gil0 = nil, bag0 = nil,
}
local function grindStep()
  local F = H.newFightDriver("grind", {
    tactical = true, boost = true, bank = 3, items = true, cure = true,
    healer = TERRA, healPercent = 60,
    nuke = { ICE2_SPELL, ICE_SPELL }, nukeLore = { AQUA_RAKE_LORE_ID },
  })
  local CAND = {
    { name = "left",  dx = -1, dy = 0, opp = "right" },
    { name = "down",  dx = 0,  dy = 1, opp = "up" },
    { name = "up",    dx = 0,  dy = -1, opp = "down" },
  }
  local dirIdx = 1
  local home, away = nil, nil
  local pend = nil
  local battN, sawBattle = 0, false
  local careD = nil
  local fightXp0, fightForm, fightF0 = 0, -1, 0
  local lastHb = -100000
  local wrapN, stallN, stallSig = 0, 0, ""
  local function anyMonsterAlive()
    for i = 0, 5 do
      if H.readByte(0x3AA8 + i * 2) % 2 == 1
         and H.readWord(0x3BFC + i * 2) > 0 then return true end
    end
    return false
  end
  local function grindDone()
    return lvl(TERRA) >= GRIND_MIN and lvl(LOCKE) >= GRIND_MIN
  end
  local function kernel()
    -- boot-frame bookkeeping
    if not grindStats.f0 then
      grindStats.f0 = H.frame
      grindStats.xp0 = { xpOf(TERRA), xpOf(LOCKE), xpOf(SHADOW) }
      grindStats.gil0 = gil()
      grindStats.bag0 = { H.invCountOf(FENIX_DOWN), H.invCountOf(TONIC),
                          H.invCountOf(POTION) }
      H.log(string.format(
        "[grind] START f%d world=(%d,%d) target=L%d levels T/L/Sh=%d/%d/%d "
        .. "xp=%d/%d/%d gil=%d bag f/t/p=%d/%d/%d",
        H.frame, H.worldX(), H.worldY(), GRIND_MIN,
        lvl(TERRA), lvl(LOCKE), lvl(SHADOW),
        xpOf(TERRA), xpOf(LOCKE), xpOf(SHADOW), gil(),
        grindStats.bag0[1], grindStats.bag0[2], grindStats.bag0[3]))
    end
    -- heartbeat: levels + xp every ~3600 frames, whatever else is going on
    if H.frame - lastHb >= 3600 then
      lastHb = H.frame
      H.log(string.format(
        "[grind hb] f%d fights=%d bframes=%d levels T/L/Sh=%d/%d/%d "
        .. "xp=%d/%d/%d hp T=%d/%d L=%d/%d mp=%d,%d danger=$%04X",
        H.frame, grindStats.fights, grindStats.bframes,
        lvl(TERRA), lvl(LOCKE), lvl(SHADOW),
        xpOf(TERRA), xpOf(LOCKE), xpOf(SHADOW),
        H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE),
        H.charMp(TERRA), H.charMp(LOCKE), H.readWord(0x1F6E)))
    end
    -- 1. battle: the nuke driver owns the pad
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN > 0 then
      if H.gameOverFired > 0 then
        error(string.format(
          "[grind] party WIPED in grind fight %d (GameOver read-fired) f%d",
          grindStats.fights, H.frame), 0)
      end
      if battN == 3 then
        sawBattle = true
        pend = nil
        grindStats.fights = grindStats.fights + 1
        fightXp0 = xpOf(TERRA)
        fightForm = H.readWord(0x11E0) & 0x3FF
        fightF0 = H.frame
        wrapN, stallN, stallSig = 0, 0, ""
        H.log(string.format(
          "[grind] fight %d START f%d formation=%d levels T/L/Sh=%d/%d/%d",
          grindStats.fights, H.frame, fightForm,
          lvl(TERRA), lvl(LOCKE), lvl(SHADOW)))
      end
      if battN >= 3 then
        grindStats.bframes = grindStats.bframes + 1
        -- VICTORY-DEADLOCK guard (measured, fight 37 of the first real
        -- bake): the kill can land while an actor's spell window is still
        -- open; in Wait mode the open window freezes the battle clock, and
        -- newFightDriver only plans at ST_CMD, so battle f+100k+ sat at
        -- state $0E with every monster at 0 hp.  When no monster is alive
        -- and a battle menu window is still up, tap B to close it so the
        -- battle can end.
        if battN > 600 and not anyMonsterAlive()
           and H.readByte(0x7BCA) ~= 0 then
          wrapN = wrapN + 1
          if wrapN == 1 then
            H.log(string.format(
              "[grind] fight %d: all monsters down with a battle window "
              .. "open (state=$%02X actor=%d) -- tapping B to let the "
              .. "battle end, f%d", grindStats.fights,
              H.readByte(0x7BC2), H.readByte(0x62CA) & 3, H.frame))
          end
          H.setPad(wrapN % 8 < 4 and { b = true } or {})
          return
        end
        -- generic no-progress watchdog: if nothing observable moves for
        -- 2400 battle frames, alternate B/A bursts to shake the state
        -- machine loose rather than hang the bake.
        local sig = string.format("%d:%d:%d:%d:%d",
          H.readByte(0x7BCA), H.readByte(0x7BC2), H.readByte(0x62CA) & 3,
          (function() local s = 0
             for i = 0, 5 do s = s + H.readWord(0x3BFC + i * 2) end
             return s end)(),
          (function() local s = 0
             for e = 0, 3 do s = s + H.readWord(0x3BF4 + e * 2) end
             return s end)())
        if sig == stallSig then stallN = stallN + 1
        else stallSig, stallN = sig, 0 end
        if stallN > 2400 then
          if stallN == 2401 then
            H.log(string.format(
              "[grind] fight %d STALLED 2400 battle frames with no state "
              .. "change (sig=%s) -- B/A recovery bursts engaged, f%d",
              grindStats.fights, sig, H.frame))
          end
          local burst = (stallN // 240) % 2
          H.setPad(stallN % 8 < 4
            and (burst == 0 and { b = true } or { a = true }) or {})
          return
        end
        F.frame()
      else
        H.setPad({})
      end
      return
    end
    F.idle()
    -- 2. a care stop in progress owns the pad, control or not: the open
    -- menu drops worldHasControl, so this must run BEFORE the control
    -- gate (worldNavTo runs its careD at the top of its kernel for the
    -- same reason; the first smoke starved the care stop here and froze)
    if careD then
      if careD.done() then careD = nil
      else careD.frame(); return end
    end
    -- 3. anything that is not plain walkable world control: no input
    if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
    if not H.worldAligned() then return end       -- mid-step: keep the pad
    if bright() < 15 then H.setPad({}); return end
    -- 4. a battle just resolved and the reload settled: tally + care
    if sawBattle then
      sawBattle = false
      H.log(string.format(
        "[grind] fight %d DONE f%d (%d bframes) formation=%d "
        .. "xp/char +%d -> T/L/Sh=%d/%d/%d levels=%d/%d/%d "
        .. "hp T=%d/%d L=%d/%d Sh=%d/%d bag f/t/p=%d/%d/%d gil=%d",
        grindStats.fights, H.frame, H.frame - fightF0, fightForm,
        xpOf(TERRA) - fightXp0,
        xpOf(TERRA), xpOf(LOCKE), xpOf(SHADOW),
        lvl(TERRA), lvl(LOCKE), lvl(SHADOW),
        H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
        H.charMaxHp(LOCKE), H.charHp(SHADOW), H.charMaxHp(SHADOW),
        H.invCountOf(FENIX_DOWN), H.invCountOf(TONIC), H.invCountOf(POTION),
        gil()))
      if not H.eventTimerLive() then
        careD = H.newCareDriver({ threshold = 0.9,
          tag = "care after grind fight " .. grindStats.fights })
        grindStats.careN = grindStats.careN + 1
      end
    end
    if careD then
      if careD.done() then careD = nil
      else careD.frame(); return end
    end
    -- 4. position bookkeeping
    local x, y = H.worldX(), H.worldY()
    if not home then home = { x = x, y = y } end
    if pend then
      if x == pend.tx and y == pend.ty then
        if not away and pend.fromHome then
          away = { x = x, y = y }
          H.log(string.format("[grind] pace pair: home=(%d,%d) away=(%d,%d) dir=%s",
            home.x, home.y, away.x, away.y, CAND[dirIdx].name))
        end
        grindStats.legs = grindStats.legs + 1
        pend = nil
      elseif x == pend.x and y == pend.y then
        pend.stall = pend.stall + 1
        if pend.stall > 10 then
          if not away and pend.fromHome then
            dirIdx = dirIdx + 1
            if dirIdx > #CAND then
              error("[grind] no walkable pace neighbor at home ("
                .. home.x .. "," .. home.y .. ")", 0)
            end
            H.log(string.format("[grind] %s blocked at home; trying %s",
              pend.dir, CAND[dirIdx].name))
          else
            H.log(string.format("[grind] step (%d,%d)->%s refused; re-picking",
              pend.x, pend.y, pend.dir))
          end
          pend = nil
          H.setPad({})
          return
        end
        H.setPad({ [pend.dir] = true })
        return
      else
        H.log(string.format("[grind] step (%d,%d)->%s landed (%d,%d); re-picking",
          pend.x, pend.y, pend.dir, x, y))
        pend = nil
      end
    end
    -- 5. done?  settle on the home tile and let the outer pred fire
    if grindDone() then
      if x == home.x and y == home.y then H.setPad({}); return end
      -- walk back toward home, one axis at a time
      local dir
      if x < home.x then dir = "right" elseif x > home.x then dir = "left"
      elseif y < home.y then dir = "down" else dir = "up" end
      local d = ({ right = { 1, 0 }, left = { -1, 0 },
                   down = { 0, 1 }, up = { 0, -1 } })[dir]
      pend = { x = x, y = y, dir = dir, tx = (x + d[1]) & 0xFF,
               ty = (y + d[2]) & 0xFF, stall = 0 }
      H.setPad({ [dir] = true })
      return
    end
    -- 6. launch the next pace step
    local d = CAND[dirIdx]
    if x == home.x and y == home.y then
      pend = { x = x, y = y, dir = d.name, tx = (x + d.dx) & 0xFF,
               ty = (y + d.dy) & 0xFF, stall = 0, fromHome = true }
      H.setPad({ [d.name] = true })
    elseif away and x == away.x and y == away.y then
      pend = { x = x, y = y, dir = d.opp, tx = home.x, ty = home.y, stall = 0 }
      H.setPad({ [d.opp] = true })
    else
      -- displaced (post-battle oddity): walk back toward home
      local dir
      if x < home.x then dir = "right" elseif x > home.x then dir = "left"
      elseif y < home.y then dir = "down" else dir = "up" end
      local dd = ({ right = { 1, 0 }, left = { -1, 0 },
                    down = { 0, 1 }, up = { 0, -1 } })[dir]
      pend = { x = x, y = y, dir = dir, tx = (x + dd[1]) & 0xFF,
               ty = (y + dd[2]) & 0xFF, stall = 0 }
      H.setPad({ [dir] = true })
    end
  end
  return seq({
    H.driveUntil(function()
      return grindStats.f0 ~= nil
         and lvl(TERRA) >= GRIND_MIN and lvl(LOCKE) >= GRIND_MIN
         and careD == nil and not H.battleLoadStarted()
         and H.worldMode() and H.worldHasControl() and H.worldAligned()
         and home ~= nil and H.worldX() == home.x and H.worldY() == home.y
    end, 3500000, { H.call(kernel) }, "grind to L" .. GRIND_MIN),
    H.release(),
    H.call(function()
      local s = grindStats
      H.log(string.format(
        "[grind] COMPLETE f%d: %d fights, %d battle frames, %d care stops, "
        .. "%d pace legs, %d total frames; levels T/L/Sh=%d/%d/%d; "
        .. "xp gained T/L/Sh=%d/%d/%d (%.0f xp/char/fight over %d fights); "
        .. "gil %d -> %d; bag f/t/p %d/%d/%d -> %d/%d/%d "
        .. "(consumed %d/%d/%d)",
        H.frame, s.fights, s.bframes, s.careN, s.legs, H.frame - s.f0,
        lvl(TERRA), lvl(LOCKE), lvl(SHADOW),
        xpOf(TERRA) - s.xp0[1], xpOf(LOCKE) - s.xp0[2], xpOf(SHADOW) - s.xp0[3],
        s.fights > 0 and (xpOf(TERRA) - s.xp0[1]) / s.fights or 0, s.fights,
        s.gil0, gil(),
        s.bag0[1], s.bag0[2], s.bag0[3],
        H.invCountOf(FENIX_DOWN), H.invCountOf(TONIC), H.invCountOf(POTION),
        s.bag0[1] - H.invCountOf(FENIX_DOWN), s.bag0[2] - H.invCountOf(TONIC),
        s.bag0[3] - H.invCountOf(POTION)))
    end),
  })
end

-- ------------------------------------------------------- walk profiles --
local WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
               items = true, maxFrames = 20000, healPercent = 85,
               magic = { [TERRA] = { spell = ICE_SPELL, boost = false },
                [LOCKE] = { spell = ICE_SPELL, boost = false } } }
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false },
                [LOCKE] = { spell = ICE_SPELL, boost = false } } }

local function houseWarp(sx, sy, dx, dy, what, playBattles)
  return seq({
    creepNav(sx, sy, { playBattles = playBattles or "tactical", healer = TERRA,
      bank = 3, items = true, maxFrames = 20000, healPercent = 85,
      magic = { [TERRA] = { spell = ICE_SPELL, boost = false },
                [LOCKE] = { spell = ICE_SPELL, boost = false } },
      arrive = function() return H.fieldX() == dx and H.fieldY() == dy end }),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, what .. ": settled", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at the right x")
      H.assertEq(H.fieldY(), dy, what .. ": landed at the right y")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

local function lossReload(blobFn, tag)
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blobFn()) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, tag .. ": loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[%s] loss-reload done, GameOver counter cleared, f%d",
        tag, H.frame))
    end),
    H.waitFrames(90),
  })
end

-- ------------------------------------------------ the ambush battle 45 --
-- The bake's bespoke per-turn plan with ONE change: the POSITIONAL
-- lore-row model (row == loreId), the fix probe_thamlab_ambush_fix.lua
-- measured correct (the compacted model held the cursor on the wrong row
-- and stalled).
local L45 = H.newSeedLadder("ambush (battle 45)", { attempts = 5 })
local ambBlob, ambWon = nil, false
local CONFIRM_BATTLE_GONE = 90

local MENU_A, ACTOR_A, MSTATE_A = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL_A, CMDROW_A = 0x202E, 0x890F
local BCHID_A, BCHP_A, BCMAXHP_A = 0x3ED8, 0x3BF4, 0x3C1C
local BP_A = 0x3E9C
local ST_CMD_A, ST_TGT_A, ST_ITEM_A, ST_THIEF_A = 0x05, 0x38, 0x0A, 0x30
local KCOL_A, KROW_A = 0x8963, 0x8967
local ST_LORE_OPEN_A, ST_LORE_A = 0x19, 0x1B
local LROW_A = 0x8927
local TBL_306A_A = 0x306A
local CMD_FIGHT_A, CMD_ITEM_A, CMD_STEAL_A, CMD_LORE_A = 0x00, 0x01, 0x05, 0x0C
local ITEMSCR_A, ITEMROW_A, BATTINV_A = 0x8947, 0x894F, 0x2686
local CMD_MAGIC_A, ST_MAGIC_A = 0x02, 0x0E
local MLISTPTR_A = 0x302C
local MSCROLL_A, MCOL_A, MROW_A = 0x8913, 0x8917, 0x891B
local CURMP_A = 0x3C08
local function spellCellA(actor, id, strict)
  local base = H.readWord(MLISTPTR_A + actor * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    local a = base + (cell + 1) * 4
    if H.readByte(a) == id then
      local cost = H.readByte(a + 3)
      if H.readWord(CURMP_A + actor * 2) < cost then return nil end
      if strict and (H.readByte(a + 1) & 0x80) ~= 0 then return nil end
      return cell, cost
    end
  end
  return nil
end
local function monHpA(i) return H.readWord(0x3BFC + i * 2) end
local function monShieldsA(i) return H.readByte(0x3E40 + i * 2) end
local function monPresentA(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function cmdRowA(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL_A + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOfA(ids)
  for i = 0, 251 do
    local id = H.readByte(BATTINV_A + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(BATTINV_A + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
-- POSITIONAL lore-row model (the ambush-fix measurement): the battle lore
-- window renders one row per lore id, empty rows included.
local function loreRowForA(targetId) return targetId end
local ambushCharTC = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })

local function newAmbushPlan(tag)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local aqCasts, filchCasts, fightBursts, iceCasts = 0, 0, 0, 0
  local openerLogged = false
  local function partyCounts()
    local balloonsAlive = 0
    for s = 0, 5 do if monPresentA(s) and monHpA(s) > 0 then balloonsAlive = balloonsAlive + 1 end end
    local stragoSlot, downSlots, anyAlive = nil, {}, false
    for e = 0, 3 do
      if H.readWord(BCMAXHP_A + e * 2) > 0 then
        local cid = H.readByte(BCHID_A + e * 2)
        if cid == STRAGO then stragoSlot = e end
        if H.readWord(BCHP_A + e * 2) > 0 then anyAlive = true
        else downSlots[#downSlots + 1] = e end
      end
    end
    return balloonsAlive, stragoSlot, downSlots, anyAlive
  end
  local function anyShielded()
    for s = 0, 5 do
      if monPresentA(s) and monHpA(s) > 0 and monShieldsA(s) > 0 then return true end
    end
    return false
  end
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
      for e = 0, 3 do
        if H.readWord(BCMAXHP_A + e * 2) > 0 then
          H.log(string.format(
            "[%s] opener dbg: slot %d char $%02X hp=%d/%d (missing=%d)",
            tag, e, H.readByte(BCHID_A + e * 2), H.readWord(BCHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2) - H.readWord(BCHP_A + e * 2)))
        end
      end
    end
    local charId = H.readByte(BCHID_A + actor * 2)
    local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
    local balloonsAlive, stragoSlot, downSlots = partyCounts()
    if mx > 0 and hp > 0 and hp < mx * 0.40 then
      local idx = bagIdxOfA({ TONIC, POTION })
      if idx then return { kind = "item", ids = { TONIC, POTION }, target = actor } end
    end
    if balloonsAlive <= 1 and #downSlots > 0 then
      local idx = bagIdxOfA({ FENIX_DOWN })
      if idx then
        local tgt = downSlots[1]
        if stragoSlot then
          for _, s in ipairs(downSlots) do if s == stragoSlot then tgt = s end end
        end
        return { kind = "item", ids = { FENIX_DOWN }, target = tgt }
      end
    end
    if charId == STRAGO then
      return { kind = "lore", loreId = AQUA_RAKE_LORE_ID }
    end
    if charId == TERRA or charId == LOCKE then
      if spellCellA(actor, ICE_SPELL, true) then
        return { kind = "magic", spell = ICE_SPELL }
      end
    end
    if charId == LOCKE then
      if anyShielded() then return { kind = "filch" } end
      return { kind = "fight", boost = true }
    end
    return { kind = "fight", boost = true }
  end
  local function buttonFor(actor, st)
    local plan = turnPlan
    if plan.kind == "item" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_ITEM_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_ITEM_A then
        local want = bagIdxOfA(plan.ids)
        if want == nil then return "b" end
        local cur = H.readByte(ITEMSCR_A + actor) + H.readByte(ITEMROW_A + actor)
        if cur < want then return "down" end
        if cur > want then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        plan.tgtSpin = (plan.tgtSpin or 0) + 1
        if plan.tgtSpin > 240 then return "a" end
        ambushCharTC.observe()
        return ambushCharTC.steer(plan.target, mf)
      end
      return "b"
    end
    if plan.kind == "filch" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_STEAL_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_THIEF_A then
        local cur = H.readByte(KROW_A + actor)
        if H.readByte(KCOL_A + actor) ~= 0 then return "left" end
        if cur < 1 then return "down" end
        if cur > 1 then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"
      end
      return "b"
    end
    if plan.kind == "lore" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_LORE_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_LORE_OPEN_A then
        return nil                       -- transitional DMA fill, just wait
      elseif st == ST_LORE_A then
        local want = loreRowForA(plan.loreId)
        local cur = H.readByte(LROW_A + actor)
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    if plan.kind == "magic" then
      if st == ST_CMD_A then
        if not plan.boosted then
          local bp = H.readByte(BP_A + actor * 2)
          local want = (bp >= 2) and math.min(bp, 3) or 0
          plan.boostLeft = plan.boostLeft or want
          if plan.boostLeft > 0 then
            plan.boostLeft = plan.boostLeft - 1
            return "r"
          end
          plan.boosted = true
        end
        local want = cmdRowA(actor, CMD_MAGIC_A)
        if want == nil then return "b" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_MAGIC_A then
        local cell = spellCellA(actor, plan.spell, false)
        if cell == nil then return "b" end
        local wr, wc = cell // 2, cell % 2
        local ar = H.readByte(MSCROLL_A + actor) + H.readByte(MROW_A + actor)
        local col = H.readByte(MCOL_A + actor)
        if ar < wr then return "down" end
        if ar > wr then return "up" end
        if col < wc then return "right" end
        if col > wc then return "left" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    -- fight (default/fallback)
    if st == ST_CMD_A then
      if plan.boost and not plan.boosted then
        local bp = H.readByte(BP_A + actor * 2)
        local want = (bp >= 2) and math.min(bp, 3) or 0
        plan.boostLeft = plan.boostLeft or want
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return "r"
        end
        plan.boosted = true
      end
      local want = cmdRowA(actor, CMD_FIGHT_A)
      local cur = H.readByte(CMDROW_A + actor) & 3
      if want == nil then return "a" end
      if cur == want then return "a" end
      return cur < want and "down" or "up"
    elseif st == ST_TGT_A then
      return "a"
    end
    return "b"
  end
  function F.frame()
    phase = (phase + 1) % 8
    if H.readByte(MENU_A) == 0 then
      turnActor, turnPlan = nil, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mf = mf + 1
    -- victory-deadlock guard (same as the grind kernel's): every monster
    -- down but a battle window still open freezes the Wait-mode clock
    local anyMon = false
    for s = 0, 5 do
      if monPresentA(s) and monHpA(s) > 0 then anyMon = true; break end
    end
    if mf > 600 and not anyMon then
      H.setPad(phase < 4 and { b = true } or {})
      return
    end
    local actor = H.readByte(ACTOR_A) & 3
    local st = H.readByte(MSTATE_A)
    if st == 0x01 then H.setPad({}); return end   -- ST_TRANS
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_A then
      H.setPad({})
      return
    end
    if turnPlan == nil or turnActor ~= actor then
      turnActor = actor
      turnPlan = decideTurn(actor)
      H.log(string.format("[%s] f%d slot=%d char=$%02X plan=%s%s", tag,
        H.frame, actor, H.readByte(BCHID_A + actor * 2), turnPlan.kind,
        turnPlan.kind == "item" and (" tgt=" .. turnPlan.target) or ""))
    end
    -- LORE-STALL watchdog kept as a safety net (should never fire with the
    -- positional model; if it does, that's a headline finding)
    if turnPlan.kind == "lore" and st == ST_LORE_A then
      turnPlan.loreStall = (turnPlan.loreStall or 0) + 1
      if turnPlan.loreStall == 600 then
        H.log(string.format(
          "[%s] LORE-STALL WITH POSITIONAL FIX f%d: actor=%d loreId=%d " ..
          "cursor(8927+a)=%d want=%d offered=%s -- falling back to Fight",
          tag, H.frame, actor, turnPlan.loreId,
          H.readByte(LROW_A + actor), loreRowForA(turnPlan.loreId),
          tostring(loreOfferedA(turnPlan.loreId))))
        turnPlan = { kind = "fight", boost = true }
      end
    end
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    if st == ST_TGT_A and btn == "a" then
      if turnPlan.kind == "lore" and not turnPlan.counted then
        turnPlan.counted = true; aqCasts = aqCasts + 1
        H.log(string.format("[%s] Aqua Rake cast #%d confirmed f%d", tag, aqCasts, H.frame))
      elseif turnPlan.kind == "filch" and not turnPlan.counted then
        turnPlan.counted = true; filchCasts = filchCasts + 1
        H.log(string.format("[%s] Filch #%d confirmed f%d", tag, filchCasts, H.frame))
      elseif turnPlan.kind == "fight" and turnPlan.boost and not turnPlan.counted then
        turnPlan.counted = true; fightBursts = fightBursts + 1
        H.log(string.format("[%s] boosted burst Fight #%d confirmed f%d", tag, fightBursts, H.frame))
      elseif turnPlan.kind == "magic" and not turnPlan.counted then
        turnPlan.counted = true; iceCasts = iceCasts + 1
        H.log(string.format("[%s] Ice cast #%d confirmed f%d", tag, iceCasts, H.frame))
      end
    end
    H.setPad(btn and { [btn] = true } or {})
  end
  function F.idle()
    turnActor, turnPlan = nil, nil
    H.log(string.format(
      "[%s] tally: Aqua Rake x%d, Ice x%d, Filch x%d, boosted burst x%d",
      tag, aqCasts, iceCasts, filchCasts, fightBursts))
  end
  return F
end

local function ambushAttempt(n)
  local F = newAmbushPlan("ambush-plan-" .. n)
  local notBattle, giveUp = 0, 0
  local loadReq
  return H.cond(function() return ambWon end, {}, {
    H.logStep(function()
      return string.format("ambush attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(ambBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "ambush entry-point reload") end),
      H.waitFrames(90),
    }) or seq({}),
    L45.spread(n),
    H.call(function() H.log(string.format(
      "[ambush] approaching (21,22), attempt %d", n)) end),
    creepNav(21, 23, FLEE_WALK),
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 1800000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "ambush fight (attempt " .. n .. ")"),
    H.call(function()
      F.idle()
      H.log(string.format(
        "[ambush] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
    end),
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return (map() == 351 and H.hasControl() and H.tileAligned())
         or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "ambush win-tail settle (or a real GameOver shows itself)"),
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and map() == 351
         and partyOf(STRAGO) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "ambush attempt %d LOST -- GameOver read-fired (event GameOver, " ..
          "$CC/E568), f%d", n, H.frame))
      elseif realWin then
        ambWon = true
        H.log(string.format(
          "ambush BEATEN on attempt %d, f%d, map=%d pos=(%d,%d) partyOf(STRAGO)=%d",
          n, H.frame, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO)))
      else
        H.log(string.format(
          "ambush attempt %d LOST -- win verification failed (map=%d " ..
          "pos=(%d,%d) partyOf(STRAGO)=%d gameOverFired=%d), f%d",
          n, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO),
          H.gameOverFired, H.frame))
      end
    end),
    H.cond(function() return not ambWon end, {
      lossReload(function() return ambBlob end, "ambush"),
    }, {}),
  })
end

-- ------------------------------------------------------------------------
local steps = {
  -- ---- 1. cold Continue the thamasa-night-v1 checkpoint -----------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the L tile (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the L tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] boot f%d world=(%d,%d) party0=%02X party1=%02X party3=%02X " ..
      "levels T/L/Sh=%d/%d/%d xp=%d/%d/%d",
      H.frame, H.worldX(), H.worldY(), H.readByte(0x1850) & 7,
      H.readByte(0x1851) & 7, H.readByte(0x1853) & 7,
      lvl(TERRA), lvl(LOCKE), lvl(SHADOW),
      xpOf(TERRA), xpOf(LOCKE), xpOf(SHADOW)))
    H.assertEntryContract("thamasa-night-v1")
  end),

  -- ---- 2. care, into town, PREP, shop trip #1 ---------------------------
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),

  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded", 5),
  H.call(function()
    H.log(string.format("[ot6] town re-entry f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  H.call(function()
    H.log(string.format(
      "[prep] gearing TERRA/LOCKE at f%d map=%d (%d,%d): TERRA %d/%dhp, " ..
      "LOCKE %d/%dhp (pre-gear)", H.frame, map(), H.fieldX(), H.fieldY(),
      H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE)))
  end),
  H.equipLoadout(TERRA, TERRA_GEAR, { tag = "TERRA loadout" }),
  H.equipLoadout(LOCKE, LOCKE_GEAR, { tag = "LOCKE loadout" }),
  H.equipEsper(charPos(TERRA), SHIVA_ESPER, { tag = "SHIVA -> TERRA (Ice)" }),
  H.equipEsper(charPos(LOCKE), MADUIN_ESPER, { tag = "MADUIN -> LOCKE (Ice)" }),
  H.setRows({ [TERRA] = true, [LOCKE] = true }, { tag = "TERRA/LOCKE back row" }),
  H.call(function()
    H.log(string.format(
      "[prep] TERRA/LOCKE geared f%d: TERRA %d/%dhp, LOCKE %d/%dhp (post-gear)",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE)))
  end),

  shopTrip("pre-grind"),

  -- ---- 3. back out to the world map and GRIND ---------------------------
  H.call(function() H.log("[grind] leaving town for the Crescent Island grind") end),
  H.navTo(21, 47, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true, avoid = { { 35, 15 }, { 25, 12 } } }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world (249,128)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa (grind start)", 5),
  H.waitFrames(60),

  grindStep(),

  H.fieldCare({ tag = "post-grind top-off", threshold = 1.0 }),

  -- ---- 4. back into town; shop trip #2 (top-up) -------------------------
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (post-grind)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded (post-grind)", 5),
  H.call(function()
    H.log(string.format("[ot6] post-grind town re-entry f%d map=%d (%d,%d) " ..
      "levels T/L/Sh=%d/%d/%d", H.frame, map(), H.fieldX(), H.fieldY(),
      lvl(TERRA), lvl(LOCKE), lvl(SHADOW)))
  end),

  shopTrip("post-grind"),

  -- ---- 5. the inn: door, innkeeper, the whole fire scene ----------------
  crossDoor(12, 19, 346, 23, 23, "inn door 343(12,19)->346(23,23)"),
  H.call(function()
    H.log(string.format("[ot6] inn interior f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),
  H.navTo(24, 17, { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 0  -- facing UP
  end, 300, {
    H.call(function() H.setPad({ up = true }) end),
  }, "face up at the inn counter"),
  H.release(), H.waitFrames(4),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { a = true, up = true } or {})
      end),
    }, "talk-across-the-counter -> innkeeper's 1 GP choice")
  end)(),
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control back on Thamasa town map after the fire")
    H.assertEq(H.fieldX(), 12, "fire scene end x (12,21)")
    H.assertEq(H.fieldY(), 21, "fire scene end y")
    H.assertEq(sw(0x008E), 1, "$008E SET -- the fire has started")
    H.assertEq(sw(0x0190), 1, "$0190 SET (the fire's companion switch)")
    H.assertEq(sw(0x0090), 0, "$0090 CLEAR -- FlameEater not fought yet")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW left the party at the inn night")
    H.log(string.format(
      "[ot6] FIRE STARTED f%d map=%d (%d,%d) party[TERRA LOCKE]=%d %d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7))
  end),

  -- ---- 6. talk to Strago at the house door -> STRAGO joins -> map 351 ---
  (function()
    local idxCell = { v = 0x14 }
    return seq({
      H.call(function()
        idxCell.v = findNpc(39, 24, 0x14)
        H.log(string.format("[ot6] chasing Strago's door NPC at slot $%02X, f%d",
          idxCell.v, H.frame))
      end),
      chaseTalkLazy(function() return idxCell.v end, 9000,
        "chase+talk Strago's door NPC",
        { done = function() return H.eventRunning() or H.dialogWaiting() end }),
    })
  end)(),
  H.advanceStory(function() return map() == 351 and H.hasControl() end,
    40000, { playBattles = "tactical" }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 351, "loaded into the burning house (map 351)")
    H.assertEq(sw(0x02E7), 1, "$02E7 -- STRAGO joined")
    H.assertEq(sw(0x02F7), 1, "$02F7 -- STRAGO available")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO is in party 1")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA is in party 1")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE is in party 1")
    do
      local slvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
      local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
      local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
      local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
      local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
      H.log(string.format(
        "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d " ..
        "(char_prop join level = avg of available chars, $1EDE=$%04X; " ..
        "TERRA=%d LOCKE=%d after the grind)", slvl, hp, mhp, mp, mmp,
        H.readWord(0x1EDE), lvl(TERRA), lvl(LOCKE)))
      if slvl < GRIND_MIN then
        H.log(string.format(
          "[P3] WARNING: STRAGO joined at L%d, below the L%d healthy floor " ..
          "-- the join-average model missed; report this",
          slvl, GRIND_MIN))
      end
    end
    H.log(string.format("[ot6] map 351 entry f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),

  H.equipEsper(charPos(STRAGO), BISMARK_ESPER, { tag = "BISMARK -> STRAGO" }),
  H.setRows({ [STRAGO] = true }, { tag = "STRAGO back row" }),

  H.navTo(4, 10, WALK),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and sw(0x0190) == 0
  end, 12000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] map 351 opening scene settled f%d (%d,%d) $0190=%d $008F=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x0190), sw(0x008F)))
    H.assertEq(sw(0x0190), 0, "$0190 cleared by the (4,10) trigger")
  end),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before pathfinding", 10),
  H.waitFrames(150),
  H.call(function() H.log("[ot6] island 0 -> 13: (4,3)->(4,38)") end),
  houseWarp(4, 3, 4, 38, "P1 (4,3)->(4,38): the floor warp into the main hall"),
  care("after P1"),
  H.waitFrames(137),

  creepNav(4, 30, FLEE_WALK),
  care("partway through the main hall (island 13)"),

  H.call(function() H.log("[ot6] island 13 -> 11: (2,24)->(26,36)") end),
  houseWarp(2, 24, 26, 36, "P2 (2,24)->(26,36): into the ambush hall", "flee"),
  care("after P2"),

  H.call(function()
    H.log(string.format(
      "[prep] pre-ambush top-off f%d: TERRA %d/%d LOCKE %d/%d STRAGO %d/%d " ..
      "levels=%d/%d/%d",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE), H.charHp(STRAGO), H.charMaxHp(STRAGO),
      lvl(TERRA), lvl(LOCKE), lvl(STRAGO)))
  end),
  H.fieldCare({ tag = "pre-ambush full top-off", threshold = 1.0 }),
  H.call(function()
    H.log(string.format(
      "[prep] pre-ambush top-off done f%d: TERRA %d/%d LOCKE %d/%d STRAGO %d/%d",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE), H.charHp(STRAGO), H.charMaxHp(STRAGO)))
  end),
  H.call(function() H.log("[ot6] checkpointing before the ambush trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "ambush entry-point checkpoint")
        ambBlob = ckReq.blob
      end),
    })
  end)(),
  H.saveState("thamlab_ambush_healthy" .. SUF .. ".mss"),
  H.logStep(function()
    return string.format(
      "[thamlab] banked thamlab_ambush_healthy%s.mss at f%d (%d,%d) map=%d " ..
      "phase=%d levels T/L/S=%d/%d/%d",
      SUF, H.frame, H.fieldX(), H.fieldY(), H.mapId() & 0x1ff,
      H.readByte(0x021E), lvl(TERRA), lvl(LOCKE), lvl(STRAGO))
  end),
  L45.watch(),
  ambushAttempt(1),
  ambushAttempt(2),
  ambushAttempt(3),
  ambushAttempt(4),
  ambushAttempt(5),
  H.call(function()
    if not ambWon then
      error("ambush (battle 45): all 5 seed-ladder attempts lost", 0)
    end
  end),
  L45.report(),
  care("after the (21,22) ambush"),

  H.call(function() H.log("[ot6] island 11 -> 1: (26,21)->(21,9)") end),
  houseWarp(26, 21, 21, 9, "P3 (26,21)->(21,9): into the north corridor", "flee"),
  care("after P3"),

  H.call(function() H.log("[ot6] island 1 -> 28: (28,3)->(4,55), Fire Rod spur") end),
  houseWarp(28, 3, 4, 55, "P5 (28,3)->(4,55): the Fire Rod spur"),
  care("after the Fire Rod spur-in"),
  chestAuto(4, 52, 104, "Fire Rod", FIRE_ROD),
  care("after the Fire Rod"),
  houseWarp(4, 56, 28, 5, "P5 return (4,56)->(28,5): back to the north corridor"),
  care("after the Fire Rod spur-out"),

  H.call(function() H.log("[ot6] island 1 -> 12: (23,3)->(46,27)") end),
  houseWarp(23, 3, 46, 27, "P4 (23,3)->(46,27): into the east wing"),
  care("after P4"),

  H.call(function() H.log("[ot6] island 12 -> 4: (49,21)->(45,10), Ice Rod spur") end),
  houseWarp(49, 21, 45, 10, "P6 (49,21)->(45,10): the Ice Rod spur"),
  care("after the Ice Rod spur-in"),
  chestAuto(45, 7, 105, "Ice Rod", ICE_ROD),
  care("after the Ice Rod"),
  H.equipWeapon(charPos(STRAGO), ICE_ROD, { slot = 0, tag = "Ice Rod -> STRAGO" }),
  houseWarp(45, 11, 49, 23, "P6 return (45,11)->(49,23): back to the east wing"),
  care("after the Ice Rod spur-out"),

  H.call(function() H.log("[ot6] island 12 -> 26: (43,21)->(21,54)") end),
  houseWarp(43, 21, 21, 54, "P7 (43,21)->(21,54): into the south hall"),
  care("after P7"),

  H.call(function() H.log("[ot6] island 26 -> 24: (21,49)->(46,54), FlameEater's chamber") end),
  houseWarp(21, 49, 46, 54, "P8 (21,49)->(46,54): into FlameEater's chamber"),
  care("before the FlameEater trigger"),

  H.call(function() H.log("[ot6] checkpointing before the FlameEater trigger") end),
  H.saveState("thamlab_flame_healthy" .. SUF .. ".mss"),
  H.logStep(function()
    return string.format(
      "[thamlab] banked thamlab_flame_healthy%s.mss at f%d (%d,%d) map=%d " ..
      "phase=%d levels T/L/S=%d/%d/%d hp T=%d/%d L=%d/%d S=%d/%d " ..
      "mp=%d,%d,%d bag f/t/p=%d/%d/%d -- both healthy fixtures on disk, " ..
      "run truncated here (the FlameEater ladder is the lab's subject, " ..
      "not its fixture)",
      SUF, H.frame, H.fieldX(), H.fieldY(), H.mapId() & 0x1ff,
      H.readByte(0x021E), lvl(TERRA), lvl(LOCKE), lvl(STRAGO),
      H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE),
      H.charHp(STRAGO), H.charMaxHp(STRAGO),
      H.charMp(TERRA), H.charMp(LOCKE), H.charMp(STRAGO),
      H.invCountOf(FENIX_DOWN), H.invCountOf(TONIC), H.invCountOf(POTION))
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 6000000, allowGameOver = true }, flat)

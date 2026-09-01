
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1

local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local TERRA, LOCKE, STRAGO, SHADOW = 0, 1, 7, 3
local FIRE_ROD, ICE_ROD = 0x35, 0x36
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local saveArg = nil

-- Preps TERRA and LOCKE with a 4-piece loadout and an Ice-granting esper
-- each before the ambush; STRAGO gets an esper too.  No enemy stat changes.
local TERRA_GEAR = { { 0, 0x0E }, { 1, 0x5C }, { 2, 0x6E }, { 3, 0x89 } }
  -- Blizzard(w) / Mithril Shld(sh) / Bandana(he) / Mithril Vest(ar)
local LOCKE_GEAR = { { 0, 0x0F }, { 1, 0x00 }, { 1, 0x01 }, { 1, 0x02 },
                     { 2, 0x73 }, { 3, 0x86 } }
  -- ThunderBlade(w) / offhand DAGGER ladder / Head Band(he) / Kung Fu
  -- Suit(ar).  LOCKE wears the Genji Glove, so his left hand holds a
  -- second weapon, never a shield -- the { 1, $5A } Buckler this list
  -- used to force is the anti-pattern the wave-4 kits removed.
-- Esper indices (genju_prop.asm's numbering): SHIVA=2 grants {ICE, OSMOSE,
-- SHELL}; MADUIN=6 grants {FIRE, ICE, BOLT} -- one to TERRA, one to LOCKE,
-- for the boosted multi-target Ice cast the fight plan leads with (Ot6FoldTbl
-- folds Ice -> Ice2 -> Ice3). BISMARK=7 grants {HASTE, SLOW, {}} (no castable
-- Water spell); given to STRAGO, whose own Aqua Rake is the water answer.
local SHIVA_ESPER, MADUIN_ESPER, BISMARK_ESPER = 2, 6, 7
-- char-select row, resolved live via (partyByte>>3)&3, the same read
-- M.equipLoadout/M.equipWeapon use.
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end

-- Probe instrumentation (not part of the route): dumps the byte obj.asm's
-- sort_obj_work reads for CheckSlot1-4/CheckOtherSlots -- $0867+41*id, bit
-- $40 = enabled, low 3 bits = party number -- for TERRA/LOCKE/SHADOW/STRAGO,
-- plus $1a6d (active party number) and the slot object pointers
-- $07fb/07fd/07ff/0801 and leader $0803.
local PROBE_IDS = { { 0, "TERRA" }, { 1, "LOCKE" }, { 3, "SHADOW" }, { 7, "STRAGO" } }
-- Frames to screenshot across the win-tail teardown window.
local SHOT_FRAMES_TAIL = {
  [20740] = true, [20900] = true, [21100] = true, [21300] = true,
  [21500] = true, [21700] = true, [21958] = true, [22100] = true,
}
-- Traces the event PC through f21200-21900, logged on every change.
local peTrailLast = nil
local _cbe622Sym = nil
do
  local ok, v = pcall(H.sym, "_cbe622")
  if ok then _cbe622Sym = v end
end
local function probePcTrail()
  if H.frame < 21200 or H.frame > 21900 then return end
  local bank, hi, lo = H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)
  local e8 = H.readWord(0x00e8)
  local wm = H.worldMode()
  local m1f64 = H.readWord(0x1f64)
  local key = string.format("%02X:%02X%02X:%04X:%s:%04X", bank, hi, lo, e8,
    tostring(wm), m1f64)
  if key ~= peTrailLast then
    peTrailLast = key
    H.log(string.format(
      "[probe127-pctrail] f%d eventPC=%02X:%02X%02X e8=$%04X worldMode=%s 1f64=$%04X",
      H.frame, bank, hi, lo, e8, tostring(wm), m1f64))
  end
end
local function probeDump(tag)
  local parts = {}
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local b = H.readByte(0x0867 + 41 * id)
    parts[#parts + 1] = string.format("%s=$%02X(en=%d,pty=%d)",
      name, b, (b & 0x40) ~= 0 and 1 or 0, b & 0x07)
  end
  H.log(string.format(
    "[probe127 %s] f%d 1a6d=$%02X 07fb=$%04X 07fd=$%04X 07ff=$%04X " ..
    "0801=$%04X 0803=$%04X %s",
    tag, H.frame, H.readByte(0x1a6d), H.readWord(0x07fb), H.readWord(0x07fd),
    H.readWord(0x07ff), H.readWord(0x0801), H.readWord(0x0803),
    table.concat(parts, " ")))
end
local probeHits = {}
local function probePc()
  local s = emu.getState()
  return string.format("%02X:%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0)
end
local function armProbeWatch()
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local addr = 0x7E0867 + 41 * id
    emu.addMemoryCallback(function(a, v)
      local line = string.format(
        "[probe127 watch] f%d pc=%s %s($0867+41*%d) <- $%02X",
        H.frame, probePc(), name, id, v)
      probeHits[#probeHits + 1] = line
      if #probeHits > 40 then table.remove(probeHits, 1) end
      H.log(line)
    end, emu.callbackType.write, addr, addr)
  end
  H.log("[probe127] write-watch armed on $0867+41*{0,1,3,7} (TERRA/LOCKE/SHADOW/STRAGO)")
end

local function probeEventDump(tag)
  local sw050A = (H.readByte(0x1E80 + (0x050A >> 3)) >> (0x050A & 7)) & 1
  local e1 = H.readByte(0x00e1)
  H.log(string.format(
    "[probe127-event %s] f%d ctl=%s algn=%s ev=%s dlg=%s " ..
    "e1(wait o/f/s)=$%02X(o=%d,f=%d,s=%d) e2(objWait)=$%02X " ..
    "e3(pauseCnt)=$%02X eventPC(bank:e6e5)=%02X:%02X%02X e8(evStackPtr)=$%04X " ..
    "ea(opcode)=$%02X da(curObjOfs)=$%02X dc(curObj)=$%02X pos=(%d,%d) " ..
    "onAmbushTile(21,22)=%s sw($050A)=%d",
    tag, H.frame, tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    e1, (e1 >> 7) & 1, (e1 >> 6) & 1, (e1 >> 5) & 1,
    H.readByte(0x00e2), H.readByte(0x00e3),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
    H.readWord(0x00e8), H.readByte(0x00ea),
    H.readByte(0x00da), H.readByte(0x00dc),
    H.fieldX(), H.fieldY(),
    tostring(H.fieldX() == 21 and H.fieldY() == 22), sw050A))
end

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- edge-A through dialogs/scenes until settled (gen_thamasa_arrive's settle)
local function settle(maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and not H.battleLoadStarted()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
    end),
  }, what)
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

-- gen_thamasa_arrive's crossDoor, unchanged
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  if opts.healer == nil then opts.healer = TERRA end
  return H.crossDoor(sx, sy, dm, dx, dy, what, opts)   -- promoted to the lib
end

-- Live NPC lookup: scan object slots 16..31 for whichever sits nearest
-- (x,y), rather than trust "$10 + record order" past 16 make_npc records
-- on one map.
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

-- chaseTalk needs a concrete object index at construction time (every step
-- in an H.run list is built before the emulator boots -- gen_tunnelarmr's
-- posOf note), but the door NPC's slot is only knowable live.  This is
-- M.chaseTalk's body (lib/ot6_field.lua) with the one line that reads
-- objIdx replaced by a call to idxFn() every frame instead.
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

-- Every warp tile the house's walks use (the source tiles of the houseWarp
-- calls below).  A walk toward one warp must AVOID all the others: the
-- pathfinder knows walkability, not warps, and the regen's fire_out
-- routed the (21,9)->(28,3) walk through (23,3) -- the east wing's warp --
-- teleporting the party mid-walk and stranding the step (run.IgBKYd89).
local HOUSE_WARPS = {
  {2,24}, {4,3}, {4,56}, {21,49}, {23,3}, {26,21}, {28,3}, {43,21}, {45,11}, {49,21}, {60,21},
}
local function otherWarps(sx, sy)
  local out = {}
  for _, w in ipairs(HOUSE_WARPS) do
    if not (w[1] == sx and w[2] == sy) then out[#out + 1] = { w[1], w[2] } end
  end
  return out
end
local function creepXY(tx, ty, step)
  step = step or 14
  local function pt()
    local px, py = H.fieldX(), H.fieldY()
    local dx, dy = tx - px, ty - py
    local dist = math.abs(dx) + math.abs(dy)
    if dist <= step or dist == 0 then return tx, ty end
    -- the straight-line waypoint can land on a wall or behind one (the
    -- regen's fire_out died on "no path (43,22)->(36,14)", a waypoint,
    -- when a different start tile moved the interpolation onto stone);
    -- only a REACHABLE waypoint shortens the walk, otherwise creep to
    -- the target itself and let the pathfinder route the whole way
    local wx, wy = px + math.floor(dx * step / dist), py + math.floor(dy * step / dist)
    for _, w in ipairs(HOUSE_WARPS or {}) do
      if w[1] == wx and w[2] == wy and not (w[1] == tx and w[2] == ty) then return tx, ty end
    end
    if H.bfsPath(wx, wy) then return wx, wy end
    return tx, ty
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

-- gen_thamasa_arrive's chestAuto: live-staged (bfsPath candidates), so no
-- hand-guessed stand tile is needed for either map-351 chest.
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
        magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }),
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

local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end
local function shopTalk(nx, ny, what)
  return H.shopTalk(nx, ny, what, { healer = TERRA })      -- promoted to the lib
end
local function shopClose(what) return H.shopClose(what) end

local function logStragoJoin()
  return H.call(function()
    -- ff6/notes/field-ram.txt:885-895: the 37-byte character record,
    -- indexed by character id (same convention as $1850+charId): +$08
    -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
    -- flag, masked off), +$0D current MP, +$0F max MP (same mask).
    local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
    local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
    local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
    local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
    local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
    H.log(string.format(
      "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
      "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
  end)
end

local WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
               items = true, maxFrames = 20000, healPercent = 85,
               magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
-- islands 13/11 only: flee wandering flames rather than fight every one
-- (see houseWarp's own note on the `flee` parameter, below).
local FLEE_WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
local FLAMEEATER_WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
  items = true, maxFrames = 100000, healPercent = 60 }

local function houseWarp(sx, sy, dx, dy, what, playBattles)
  return seq({
    creepNav(sx, sy, { playBattles = playBattles or "tactical", healer = TERRA,
      bank = 3, items = true, maxFrames = 20000, healPercent = 85,
      magic = { [TERRA] = { spell = ICE_SPELL, boost = false } },
      avoid = otherWarps(sx, sy),
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

local function battleHpAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
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
local AQUA_RAKE_LORE_ID = 3
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
-- battle_lore.lua's own tested fact: $306A+id reads id+$8B iff that lore
-- id is currently offered by Ot6LoreMask's live walk; otherwise whatever
-- InitBattle's own clear left there. Comparing against the exact expected
-- value (rather than measuring a separate "fill" byte first) sidesteps
-- needing that extra live-measurement step.
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
-- The battle lore window is POSITIONAL by lore id: one row per id, with
-- unlearned/unoffered ids rendering as empty rows (thamlab, measured:
-- learned {3,7,20} -> Aqua Rake (id 3) renders on row index 3; the old
-- compacted-count model computed row 0, and the driver A-tapped the empty
-- first row for ~61k frames -- the stall the owner watched twice).
local function loreRowForA(targetId) return targetId end

local function newAmbushPlan(tag)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local stepIdx = 0
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
  -- built once per fresh ST_CMD (turnPlan == nil or a new actor's turn)
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
      local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
      H.log(string.format(
        "[%s] opener check f%d: first actor to get a turn is slot %d " ..
        "(char $%02X) at %d/%d hp -- the opener's own damage on whoever it " ..
        "caught is whatever's MISSING from THEIR max, logged separately " ..
        "per party member below", tag, H.frame, actor,
        H.readByte(BCHID_A + actor * 2), hp, mx))
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
    -- 1. self-heal, always allowed (the fence lesson)
    if mx > 0 and hp > 0 and hp < mx * 0.40 then
      local idx = bagIdxOfA({ TONIC, POTION })
      if idx then return { kind = "item", ids = { TONIC, POTION }, target = actor } end
    end
    -- 2. revive window: at most one Balloon left, revive STRAGO first
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
    -- 3. offense -- lead with AoE weakness magic: STRAGO's Aqua Rake is
    -- free every turn regardless; TERRA and
    -- LOCKE now both carry an Ice-granting esper (SHIVA/MADUIN), so they
    -- lead with a boosted, multi-target Ice cast (Balloons are weak to
    -- ice|water, thamasa-route.md) whenever they can pay for it, falling
    -- back to the pre-PREP break-and-burst kit (Filch/boosted Fight) only
    -- when the cast isn't available (esper unequipped, out of MP, or the
    -- greyed bit refuses it).
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
  -- per-frame button for the CURRENT plan/state
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
        -- closed-loop char-column steer (plan-local, so nothing carries
        -- across episodes): up/down only -- left/right switch target
        -- GROUPS in this pincer formation; single 2-frame taps with a
        -- long dwell, because battle d-pad input is auto-repeat, not
        -- edge, driven.  (thamlab, measured: the old blind rotation's
        -- first press exiled the cursor into a monster group and the
        -- 240-spin blind A fed Fenix Downs to a Balloon -- eight ~1740-
        -- frame whiff episodes on one seed; this steer confirms in ~35
        -- frames on both pincer and normal shapes.)
        plan.fixMf = (plan.fixMf or -1) + 1
        local want = 1 << plan.target
        local d7d = H.readByte(0x7B7D)
        if d7d ~= 0 then plan.fixSeen = d7d end   -- latch across the blink
        local ace = H.readByte(0x7ACE)
        if plan.tgtSpin > 600 then return "a" end -- safety net only
        if plan.fixSeen == want then return "a" end
        local ph = plan.fixMf % 16
        if ph >= 2 then return nil end
        if ace % 2 == 0 then return (ace == 0) and "right" or "left" end
        return "down"
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
        return "a"                       -- default enemy cursor, no steer
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
      -- Same boost-bank shape the fight fallback uses below (spend BP,
      -- capped at 3, only once at least 2 is banked) -- OT6 folds a boosted
      -- base cast to its next tier via Ot6FoldTbl (Ice -> Ice2 -> Ice3), so
      -- this is how the plan gets the bigger AoE hit rather than the base
      -- 4 MP tier every single cast.
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
        -- re-read the cell every tick (not just at plan time): the list is
        -- rebuilt when the window opens, matching M.newFightDriver's own
        -- button()'s "re-read, don't trust the plan-time cell" note.
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
      return "a"                         -- default enemy cursor, no steer
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
    local actor = H.readByte(ACTOR_A) & 3
    local st = H.readByte(MSTATE_A)
    if st == 0x01 then H.setPad({}); return end   -- ST_TRANS
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_A then
      -- a fresh actor turn hasn't reached the command list yet (a
      -- transitional state); hold still rather than build a plan off a
      -- read that might still be settling, matching H.newFightDriver's
      -- own "only build a plan at ST_CMD" convention.
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
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    -- count landed actions on the ST_TGT->confirm edge, logged once per
    -- kind so the report has real cadence numbers
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
    H.call(function() probeDump("PRE-BATTLE45 attempt-" .. n) end),
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
      probeDump("POST-BATTLE45 attempt-" .. n)
      probeEventDump("POST-BATTLE45 attempt-" .. n)
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

-- ---------------------------------------------------------- FlameEater --
-- Battle 79, formation 449: shields 7, pierce class, weak ice, absorbs
-- fire, the authored OT6 water add.  Fired by stepping on the (46,53)
-- floor trigger (event_trigger.asm:1716), which re-forces party order
-- STRAGO,TERRA,LOCKE itself.  A win sets $0090=1 (the SAME _ca5ea9 gate
-- Dadaluma/TunnelArmr use); a loss is vanilla GameOver.  L26 HP8400 vs a
-- party around L16-19 is a long fight -- newFightDriver's own tactical
-- kit (boosted Fight, TERRA's Cure, the item bag) fights it honestly, no
-- bespoke per-turn plan.  A seed ladder (H.newSeedLadder, 5 rungs
-- like gen_sabin_train's battle 68) retries a loss from a checkpoint taken
-- just before the trigger tile, with a care stop each attempt.
local L79 = H.newSeedLadder("FlameEater (battle 79)", { attempts = 5 })
local feBlob, feWon = nil, false

local function flameEaterAttempt(n)
  -- The nuke repertoire is what wins this board (thamlab, 8-seed protocol
  -- at the routed levels: libnuke 5/8 with its win set strictly
  -- containing the plain driver's 3/8; at healthy levels 3 of its wins
  -- are 0-death 0-item).  TERRA/LOCKE lead boosted Ice (the fold pays the
  -- AoE tier), STRAGO Aqua Rake through the Lore menu.
  local F = H.newFightDriver("FlameEater", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 60,
    nuke = { 0x01 }, nukeLore = { 3 } })
  local notBattle, giveUp = 0, 0
  local loadReq
  -- H.cond's branches take a plain step list, not a pre-wrapped seq({...}).
  return H.cond(function() return feWon end, {}, {
    H.logStep(function()
      return string.format("FlameEater attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(feBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "FlameEater entry-point reload") end),
      H.waitFrames(90),
      care("post-reload, attempt " .. n),
    }) or seq({}),
    L79.spread(n),
    H.call(function() H.log(string.format(
      "[FlameEater] approaching (46,53), attempt %d", n)) end),
    creepNav(46, 52, FLAMEEATER_WALK),
    pressWalk("down", function()
      return sw(0x0090) == 1 or H.battleLoadStarted() or H.battleActive()
    end, 8000, "walk onto (46,53) until battle 79 starts (or it's already won)"),
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
    }, "FlameEater fight (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format(
        "[FlameEater] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
    end),
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or a real GameOver shows itself)"),
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and sw(0x0090) == 1
         and partyOf(STRAGO) ~= 0 and partyOf(TERRA) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "FlameEater attempt %d LOST -- GameOver read-fired (event " ..
          "GameOver, $CC/E568), f%d", n, H.frame))
      elseif realWin then
        feWon = true
        H.log(string.format(
          "FlameEater BEATEN on attempt %d, f%d, map=%d pos=(%d,%d)",
          n, H.frame, map(), H.fieldX(), H.fieldY()))
      else
        H.log(string.format(
          "FlameEater attempt %d LOST -- win verification failed " ..
          "($0090=%d partyOf(STRAGO)=%d partyOf(TERRA)=%d " ..
          "gameOverFired=%d, giveUp=%d), f%d",
          n, sw(0x0090), partyOf(STRAGO), partyOf(TERRA), H.gameOverFired,
          giveUp, H.frame))
      end
    end),
    H.cond(function() return not feWon end, {
      lossReload(function() return feBlob end, "FlameEater"),
    }, {
      -- heal-after-every-battle: the boss is no exception, and three of
      -- the lab's protocol wins ended with someone under the standing
      -- floor -- recover before the win tail so the banked state ships
      -- whole (zero frames when the party comes out clean).
      H.careStop("care after the FlameEater"),
    }),
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
      "[ot6] boot f%d world=(%d,%d) party0=%02X party1=%02X party3=%02X",
      H.frame, H.worldX(), H.worldY(), H.readByte(0x1850) & 7,
      H.readByte(0x1851) & 7, H.readByte(0x1853) & 7))
    H.assertEntryContract("thamasa-night-v1")
  end),

  -- ---- 2. care, then PREP, then into town ---------------------------------
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
  -- Best-effort: each gear piece equips only if the bag holds it; a piece
  -- this lineage never bought or already wears keeps the current slot,
  -- with a log.  (Same inline pattern as gen_ifrit_magicite /
  -- gen_banquet_done: a shared lib helper would re-stale every generated
  -- state in the chain.)
  (function()
    local KITS = { { TERRA, "TERRA", TERRA_GEAR },
                   { LOCKE, "LOCKE", LOCKE_GEAR } }
    local steps = {}
    for _, kit in ipairs(KITS) do
      local char, name, pairs_ = kit[1], kit[2], kit[3]
      for _, p in ipairs(pairs_) do
        local slot, item = p[1], p[2]
        local tag = string.format("%s loadout slot %d", name, slot)
        steps[#steps + 1] = H.cond(
          function() return H.invSlotOf(item) ~= nil end,
          { H.equipLoadout(char, { { slot, item } }, { tag = tag }) },
          { H.logStep(string.format(
              "%s: $%02X not in this lineage's bag; keeping current gear",
              tag, item)) })
      end
    end
    return H.cond(function() return true end, steps)
  end)(),
  H.equipEsper(charPos(TERRA), SHIVA_ESPER, { tag = "SHIVA -> TERRA (Ice)" }),
  H.equipEsper(charPos(LOCKE), MADUIN_ESPER, { tag = "MADUIN -> LOCKE (Ice)" }),
  H.setRows({ [TERRA] = true, [LOCKE] = true }, { tag = "TERRA/LOCKE back row" }),
  H.call(function()
    H.log(string.format(
      "[prep] TERRA/LOCKE geared f%d: TERRA %d/%dhp, LOCKE %d/%dhp (post-gear)",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE)))
  end),

  crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44)"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
    "shop interior settled before pathfinding", 10),
  H.waitFrames(150),
  shopTalk(36, 39, "Thamasa item shop"),
  -- Essentials (Potion, Fenix) first, then the Tonic soak LAST so a short
  -- purse shorts Tonics, not the revives.  Gil is deep here (~70k), so all
  -- three reach their ceilings; the ordering is the route-wide restock rule
  -- (owner: Tonic -> 99, "a rite of passage to get 99 in the bag").
  H.buyItem(POTION, 1, function() return 15 - H.invCountOf(POTION) end, "POTION to 15"),
  H.buyItem(FENIX_DOWN, 6, function() return 20 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 20"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.call(function()
    H.log(string.format(
      "[shop] Thamasa item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
      gil(), H.frame))
  end),
  shopClose("Thamasa item shop"),
  crossDoor(36, 45, 343, 26, 39, "item shop door 347(36,45)->343(26,39), return"),

  -- ---- 3. the inn: door, innkeeper, the whole fire scene -----------------
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
  -- one continuous scripted stretch from here: the Yes confirm (default
  -- cursor), the innkeeper walking off, and (since $008D=1) straight into
  -- the night/fire scene with no further choice screens (see header).
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
    H.screenshot("thamasa_fire_started")
  end),
  H.call(function()
    probeDump("GOOD-post-fire")
    armProbeWatch()
  end),

  -- ---- 4. talk to Strago at the house door -> STRAGO joins -> map 351 ---
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
      -- ff6/notes/field-ram.txt:885-895: the 37-byte character record,
      -- indexed by character id (same convention as $1850+charId): +$08
      -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
      -- flag, masked off), +$0D current MP, +$0F max MP (same mask).
      local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
      local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
      local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
      local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
      local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
      H.log(string.format(
        "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
        "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
    end
    H.log(string.format("[ot6] map 351 entry f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_house_entry")
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
      "[prep] pre-ambush top-off f%d: TERRA %d/%d LOCKE %d/%d STRAGO %d/%d",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE), H.charHp(STRAGO), H.charMaxHp(STRAGO)))
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

  -- island 26 -> 24 is one-way in the decoded table (no return pair
  -- recorded) -- consistent with it leading straight to FlameEater's room,
  -- whose own win tail exits via load_map 349 rather than back through here
  H.call(function() H.log("[ot6] island 26 -> 24: (21,49)->(46,54), FlameEater's chamber") end),
  houseWarp(21, 49, 46, 54, "P8 (21,49)->(46,54): into FlameEater's chamber"),
  care("before the FlameEater trigger"),

  -- checkpoint the entry point for the retry ladder, once
  H.call(function() H.log("[ot6] checkpointing before the FlameEater trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "FlameEater entry-point checkpoint")
        feBlob = ckReq.blob
      end),
    })
  end)(),
  L79.watch(),
  flameEaterAttempt(1),
  flameEaterAttempt(2),
  flameEaterAttempt(3),
  flameEaterAttempt(4),
  flameEaterAttempt(5),
  H.call(function()
    if not feWon then
      error("FlameEater: all 5 seed-ladder attempts lost", 0)
    end
  end),
  L79.report(),

  -- ---- 6. the win tail: rescue, the night talk at Strago's house --------
  H.advanceStory(function()
    return map() == 349 and H.hasControl() and sw(0x0091) == 1
       and sw(0x0098) == 1
  end, 60000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 349, "control in Strago's house after the win tail")
    H.assertEq(sw(0x0091), 1, "$0091 -- FlameEater aftermath resolved")
    H.assertEq(sw(0x0098), 1, "$0098 -- morning-after companion switch")
    H.assertEq(sw(0x0090), 1, "$0090 still SET -- FlameEater beaten")
    H.log(string.format("[ot6] win tail settled f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_after_fight")
  end),

  -- ---- 7. leave the house -> Shadow's goodbye ----------------------------
  -- SHADOW's gear, recorded before remove_equip fires, so the exit
  -- contract's "gear back in the bag" claim is an inventory delta rather
  -- than a guess at what he carries.
  H.call(function()
    H._shadowWeapon = H.readByte(0x1600 + 37 * SHADOW + 0x1F)
    H._shadowWeaponBefore = H._shadowWeapon ~= 0xFF
      and H.invCountOf(H._shadowWeapon) or nil
    H.log(string.format("[ot6] SHADOW's weapon before remove_equip: $%02X (bag=%s)",
      H._shadowWeapon, tostring(H._shadowWeaponBefore)))
  end),
  houseWarp(60, 21, 38, 11, "stairs (60,21)->(38,11): upstairs to downstairs, Strago's house"),
  care("after the stairs down"),
  H.navTo(37, 25, { maxFrames = 6000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true, arrive = function() return map() ~= 349 end }),
  pressWalk("down", function() return map() ~= 349 end, 1800,
    "held DOWN through 349(37,25) -> Shadow's goodbye on 343(29,15)"),
  H.advanceStory(function()
    return map() == 343 and H.hasControl() and sw(0x0092) == 1
  end, 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "back on the town map after Shadow's goodbye")
    H.assertEq(sw(0x0092), 1, "$0092 -- Shadow's goodbye played")
    if H._shadowWeapon ~= 0xFF and H._shadowWeaponBefore ~= nil then
      local now = H.invCountOf(H._shadowWeapon)
      H.assertEq(now, H._shadowWeaponBefore + 1, string.format(
        "SHADOW's weapon ($%02X) returned to the bag: %d -> %d",
        H._shadowWeapon, H._shadowWeaponBefore, now))
    else
      H.log("[ot6] SHADOW carried no measurable weapon at boot -- " ..
        "remove_equip's bag delta is NOT asserted, only logged")
    end
    H.log(string.format("[ot6] Shadow's goodbye done f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_shadow_goodbye")
  end),

  care("before leaving town"),
  H.navTo(21, 47, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world (249,128)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] outside Thamasa: world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame))
    H.screenshot("thamasa_fireout_world")
  end),
  H.fieldCare({ tag = "care before the M save", threshold = 0.9 }),
  H.call(function()
    H.assertPartyStanding("fire_out exit")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT outside Thamasa")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA in party 1 at the M boundary")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE in party 1 at the M boundary")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO in party 1 at the M boundary")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW not in the party at the M boundary")
  end),

  -- ---- 9. the world battery save -- checkpoint M -------------------------
  H.call(function()
    H.assertExitContractPreSave("fire-out-v1")
  end),
  H.saveState("fire_out.mss"),
  (function()
    local saveReq, loadReq
    return H.cond(function() return true end, {
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(H.worldMode(), true, "reload: on the world map")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- fire_out verified")
      end),
    })
  end)(),
  (function() local calmN, ph = 0, 0
    return H.driveUntil(function()
      calmN = (H.readByte(0x59) ~= 0) and calmN + 1 or 0
      return calmN >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open outside Thamasa")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.assertExitContract("fire-out-v1")
    H.screenshot("thamasa_fireout_saved")
  end),
  H.logStep(function()
    return string.format("fire-out-v1 saved via the real Save UI at "
      .. "frame %d -- FlameEater beaten, Shadow's gear back in the bag; "
      .. "checkpoint M of v0.13", H.frame)
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

H.run({ maxFrames = 3000000, allowGameOver = true }, flat)

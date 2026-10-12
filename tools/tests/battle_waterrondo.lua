-- @suite savestate=moogle_cleared slow
-- battle_waterrondo.lua -- Water Rondo is Mog's divine: only a full 3-BP
-- boost dances it, and danced with one it never stumbles (#380).
--
-- kits.md "Divines": a divine's one gate is a full 3-BP boost.  Mog's is
-- Water Rondo (dance 5).  Ot6DanceRowColor greys its row and the confirm
-- buzzes with fewer than three points pending; a start with three records
-- tier 3 (Ot6DanceStartGate), and Ot6DanceTerrain lets a tier-3 Water Rondo
-- start wherever the party stands -- vanilla's off-terrain start stumbles
-- half the time (Cmd_13's RandCarry) -- turning the background to the
-- river.  The paths the engine picks a dance by spend no boost and are
-- closed: a random Dance draws from the known dances less Water Rondo
-- (Ot6DanceKnownRand), and a Water Rondo start under three points that
-- still arrives (a dance id left from an earlier start) stumbles, charging
-- nothing.
--
-- The run is the real MOG in the moogle defense (battle_dancestumble's
-- fixture and march): he learns the terrain's dance by winning P2's first
-- wave.  SYNTHETIC SETUP (waivered), because moogle_defense is the route's
-- only MOG-with-Dance window and Water Rondo is learned on the Lete River,
-- which no route state reaches with MOG: between the waves the known-dance
-- mask ($1D4C) gains Water Rondo; in the second wave MOG's pool := 999 so
-- the price is never the reason a row greys or a start fails (three points
-- price the start at 99, past his real pool).  His squad Defends.  Three
-- arms, each from a snapshot of the second wave:
--   A. the gate (real menus): at his first window, pending 1, Water Rondo's
--      row is grey ($25) while the terrain dance's is white, and A on it
--      buzzes, commits nothing and leaves the list open.
--   B. the divine (real menus): MOG Defends two turns to bank three points
--      (every character opens with one), then R to pending 3 and Water
--      Rondo, from one snapshot BRANCHES times (each idling 7 frames longer,
--      its own draw of the terrain roll).  Every start must lock in (no
--      stumble arm executed, DANCE set), with tier 3 recorded, the boosted
--      price (H.boostPrice(8, 3) = 99) charged, and the background turned to
--      the river's (DanceBG's Water Rondo entry).  Vanilla stumbles each
--      such start with probability 1/2 (RandCarry), so a ROM without the
--      rule passes all BRANCHES with probability 2^-BRANCHES.
--   C. the engine's pick (synthetic): MOG Muddled (STATUS2 bit 5, put back
--      if a hit clears it, and his HP topped up under half) with Water
--      Rondo left as his dance id ($32E1), from the snapshot MUDDLES times.
--      His first random Dance must stumble (the stumble arm executes, no MP
--      charged, nothing pending at the turn's end) and clear the id; every
--      draw RandDance makes from the known dances ($ff path: the mask
--      RandBit is handed) must leave Water Rondo out.  Without the rule a
--      Water Rondo start stumbles only off its roll, 1/2.
-- Old-ROM red and mutants: build/attempts/wt/v028-kits/.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/moogle_defense.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_DEF = 0x05, 0x21, 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local FIGHTPARTY = 0x1A6D               -- which party a defense battle engaged
local RONDO = 5
local DANCETIER = 0x7EEDA1              -- OT6_DANCETIER (ot6_memory.inc), stride 2
local WHITE, GREY = 0x21, 0x25
local BRANCHES, MUDDLES = 8, 6

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end
local function tierOf(s) return emu.read(DANCETIER + s * 2, emu.memType.snesMemory) end
local function muddled(s) return (H.readByte(0x3EE5 + s * 2) & 0x20) ~= 0 end

local DANCENAME = H.sym("DanceName") & 0x3FFFFF
local function danceNameSeq(id)
  local t = {}
  for i = 0, 11 do t[#t + 1] = H.readRomByte(DANCENAME + id * 12 + i) end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function findInMap(seq)
  for w = 0x7C00, 0x7CF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, emu.memType.snesVideoRam) & 0xFF) ~= seq[i] then
        hit = false; break
      end
    end
    if hit then return w end
  end
  return nil
end
local function mapWord(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end

-- squads (gen_moogle's tables): P2 = MOG + three moogles, leader obj $019A
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }
local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

local mogSlot, danceId = nil, nil
local ph, hb = 0, -600

local function untilP2Battle(what)
  local battN = 0
  return H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 30 and H.readByte(FIGHTPARTY) == 2
  end, 60000, {
    H.call(function()
      ph = ph + 1
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[hb f%d] batt=%s party=%d menu=%02x",
          H.frame, tostring(H.battleLoadStarted()), H.readByte(FIGHTPARTY),
          H.readByte(MENU)))
      end
      if H.battleLoadStarted() and H.readByte(FIGHTPARTY) == 2 then
        H.setPad({})
      else
        H.setPad(ph % 8 < 4 and { a = true } or {})
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- a window's hands for Defend: Right to the Def. window, A there
local function defendHands()
  local st = H.readByte(MSTATE)
  local step = ph % 40
  if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
  elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
  elseif step < 4 then H.setPad({ right = true })      -- Fight -> Def
  elseif step >= 20 and step < 24 then H.setPad({ a = true })
  else H.setPad({}) end
end

local function winByTapA(what)
  return H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
    H.call(function()
      ph = ph + 1
      H.setPad(ph % 8 < 4 and { a = true } or {})
    end),
    H.waitFrames(1),
  }, what)
end

local function findMog()
  mogSlot = nil
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
  end
  assert(mogSlot, "MOG is in P2's battle party")
end

local function mogMenu(what)
  return H.driveUntil(function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if not H.battleLoadStarted() then H.setPad({}) return end
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= mogSlot then defendHands()
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- MOG Defends this window: his queue takes the command, then the window goes
local function mogDefends(what)
  return H.driveUntil(function()
    return H.readByte(MENU) == 0 or H.readByte(ACTOR) ~= mogSlot
  end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then defendHands()
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

local function raiseBoost(want, what)
  return H.driveUntil(function()
    return H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
       and pend(mogSlot) == want
  end, 900, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MSTATE) ~= ST_CMD or H.readByte(ACTOR) ~= mogSlot then
        H.setPad({}) return
      end
      local p = pend(mogSlot)
      if p < want then H.setPad(ph % 10 < 5 and { r = true } or {})
      elseif p > want then H.setPad(ph % 10 < 5 and { l = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

local function openDance(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_DANCE end,
    1200, {
      H.call(function()
        ph = ph + 1
        local edge = ph % 10 < 5
        local a = H.readByte(ACTOR)
        if H.readByte(MSTATE) ~= ST_CMD then H.setPad({}) return end
        local wantCell = nil
        for i = 0, 3 do
          if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_DANCE then wantCell = i end
        end
        assert(wantCell, "MOG's real battle command list carries Dance now")
        local cur = H.readByte(0x890F + a)
        if cur == wantCell then H.setPad(edge and { a = true } or {})
        elseif cur < wantCell then H.setPad(edge and { down = true } or {})
        else H.setPad(edge and { up = true } or {}) end
      end),
      H.waitFrames(1),
    }, what)
end

local function danceCursorTo(id, what)
  return H.driveUntil(function()
    local a = H.readByte(ACTOR)
    return H.readByte(MSTATE) == ST_DANCE
       and H.readByte(0x8937 + a) == id % 2
       and H.readByte(0x893B + a) == id // 2
  end, 900, {
    H.call(function()
      ph = ph + 1
      local edge = ph % 10 < 5
      local a = H.readByte(ACTOR)
      if H.readByte(MSTATE) ~= ST_DANCE then H.setPad({}) return end
      local row, col = id // 2, id % 2
      local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
      if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
      elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

local function backToCmd(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_CMD end, 900, {
    H.call(function()
      ph = ph + 1
      H.setPad(ph % 10 < 5 and { b = true } or {})
    end),
    H.waitFrames(1),
  }, what)
end

-- ---- observers --------------------------------------------------------------
local buzzes, confirms = 0, 0
local rec = nil                         -- the live branch's record (arms B, C)
local masks = {}                        -- RandBit's mask on RandDance's draw
local inRandDance = false

local function findStumbleArm()
  local base = H.sym("Cmd_13") & 0x3FFFFF
  local pat = { 0xA9, 0x06, 0x8D, 0x01, 0x34 }
  for off = 0, 0x7F do
    local hit = true
    for i = 1, #pat do
      if H.readRomByte(base + off + i - 1) ~= pat[i] then hit = false; break end
    end
    if hit then return (H.sym("Cmd_13") + off) end
  end
  error("Cmd_13's stumble arm (lda #$06 / sta $3401) not found")
end

local function installObservers()
  for _, base in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
      emu.callbackType.write, base + 0x95, base + 0x95)
    emu.addMemoryCallback(function() confirms = confirms + 1 end,
      emu.callbackType.write, base + 0x96, base + 0x96)
  end
  local arm = findStumbleArm()
  emu.addMemoryCallback(function()
    if not (rec and mogSlot) then return end
    if (emu.getState()["cpu.y"] & 0xFF) ~= mogSlot * 2 then return end
    rec.stumbles = (rec.stumbles or 0) + 1
    rec.stumbleF = rec.stumbleF or H.frame
  end, emu.callbackType.exec, arm, arm)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.committed and mogSlot) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= mogSlot * 2 then return end
    if H.readByte(0x3A7C) ~= CMD_DANCE then return end
    rec.done = { f = H.frame, pend = pend(mogSlot), bank = bp(mogSlot), mp = mpOf(mogSlot),
                 dancing = dancing(mogSlot), tier = tierOf(mogSlot), bg = H.readByte(0x11E2),
                 id = H.readByte(0x32E1 + mogSlot * 2) }
  end, emu.callbackType.exec, ae, ae)
  -- RandDance's draw from the known dances: the RandBit right after a
  -- RandDance entry whose dance id is $ff (the only path that calls RandBit)
  local rd, rb = H.sym("RandDance"), H.sym("RandBit")
  emu.addMemoryCallback(function()
    if not mogSlot then return end
    if (emu.getState()["cpu.y"] & 0xFF) ~= mogSlot * 2 then return end
    inRandDance = H.readByte(0x32E1 + mogSlot * 2) == 0xFF
  end, emu.callbackType.exec, rd, rd)
  emu.addMemoryCallback(function()
    if not inRandDance then return end
    inRandDance = false
    masks[#masks + 1] = emu.getState()["cpu.a"] & 0xFFFF
    H.log(string.format("[rondo] f%d RandDance draws from mask %04X", H.frame, masks[#masks]))
  end, emu.callbackType.exec, rb, rb)
  H.log(string.format("[rondo] stumble arm $%06X, Ot6ActionEnd $%06X, RandDance $%06X, RandBit $%06X",
    arm, ae, rd, rb))
end

local riverBg = nil

-- ---- the run ----------------------------------------------------------------
local snap0, snap3 = nil, nil
local recsB, recsC = {}, {}

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "control on the defense map"),
  H.call(function()
    H.assertEq(H.mapId(), 51, "moogle_defense on map 51")
    installObservers()
    riverBg = H.readRomByte((H.sym("DanceBG") & 0x3FFFFF) + RONDO)
  end),
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  untilP2Battle("the west arm's first wave engages MOG's squad"),
  H.waitFrames(240),
  H.call(function()
    findMog()
    danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
    H.assertEq(danceId < 8 and danceId ~= RONDO, true,
      "this background teaches a dance, and it is not Water Rondo")
  end),
  winByTapA("P2's first wave won with plain Fights"),
  H.waitFrames(60),
  H.call(function()
    local mask = H.readByte(DANCES)
    H.assertEq(mask & (1 << danceId) ~= 0, true, "the victory taught the background's dance")
    H.writeByte(DANCES, mask | (1 << RONDO))
    H.log(string.format("[rondo] terrain dance %d; known mask %02X -> %02X (Water Rondo added, synthetic)",
      danceId, mask, H.readByte(DANCES)))
  end),
  untilP2Battle("the west arm's second wave engages MOG's squad"),
  H.waitFrames(240),
  H.call(function()
    findMog()
    local bgDance = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
    H.assertEq(bgDance ~= RONDO and H.readByte(0x11E2) ~= riverBg, true,
      "the battle is off Water Rondo's terrain: vanilla's stumble roll is live")
    H.log(string.format("[rondo] second wave: MOG slot %d, %d MP, %d BP; terrain dance %d, river bg %02X",
      mogSlot, mpOf(mogSlot), bp(mogSlot), bgDance, riverBg))
  end),
  mogMenu("MOG's first window"),
  H.call(function()
    H.writeWord(0x3C08 + mogSlot * 2, 999)
    H.log("[rondo] MOG's pool := 999 (synthetic: the price is not the reason)")
    H.setPad({})
    snap0 = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap0, "snapshot at MOG's first window") end),

  -- ---- A. the gate ------------------------------------------------------------
  raiseBoost(1, "A: R to pending 1"),
  openDance("A: the dance list opens"),
  H.waitFrames(20),
  H.call(function()
    local wr, td = findInMap(danceNameSeq(RONDO)), findInMap(danceNameSeq(danceId))
    H.assertEq(wr ~= nil and td ~= nil, true, "both dances are drawn in the list")
    H.log(string.format("[rondo] A: pending %d: Water Rondo font %02X, terrain dance font %02X",
      pend(mogSlot), mapWord(wr) >> 8, mapWord(td) >> 8))
    H.assertEq(mapWord(td) >> 8, WHITE, "A: the terrain dance's row is white (the control)")
    H.assertEq(mapWord(wr) >> 8, GREY, "A: Water Rondo's row is grey with one point pending")
  end),
  danceCursorTo(RONDO, "A: cursor onto Water Rondo"),
  H.call(function()
    rec = { arm = "A", buzzes = buzzes, confirms = confirms, queue = H.readByte(0x32CC + mogSlot * 2) }
  end),
  H.driveUntil(function() return buzzes > rec.buzzes end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
        H.setPad(ph % 10 < 5 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "A: Water Rondo is confirmed and buzzes"),
  H.waitFrames(60),
  H.call(function()
    H.setPad({})
    H.assertEq(confirms, rec.confirms, "A: the confirm sound did not play")
    H.assertEq(H.readByte(MSTATE), ST_DANCE, "A: the dance list is still open")
    H.assertEq(H.readByte(0x32CC + mogSlot * 2), rec.queue, "A: nothing was queued for MOG")
    H.assertEq(dancing(mogSlot), false, "A: no dance started")
    H.log("[rondo] A PASS: under three points Water Rondo greys and buzzes")
    rec = nil
  end),
  backToCmd("A: back out of the list"),
  raiseBoost(0, "A: L back to pending 0, so the Defends bank"),

  -- ---- B. three points: the divine never stumbles --------------------------
  mogDefends("B: MOG Defends (a point banked)"),
  mogMenu("B: MOG's second window"),
  mogDefends("B: MOG Defends again"),
  mogMenu("B: MOG's third window"),
  H.call(function()
    H.assertEq(bp(mogSlot) >= 3, true, string.format("B: MOG banked three points (%d)", bp(mogSlot)))
    H.writeWord(0x3C08 + mogSlot * 2, 999)
    H.setPad({})
    snap3 = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap3, "snapshot at MOG's three-point window") end),
}

local function branchB(k)
  local req
  return {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap3.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (B branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { arm = "B", k = k }
      recsB[#recsB + 1] = rec
    end),
    H.waitFrames((k - 1) * 7 + 1),
    raiseBoost(3, "B: R to pending 3"),
    openDance("B: the dance list opens"),
    H.waitFrames(20),
    H.call(function()
      local wr = findInMap(danceNameSeq(RONDO))
      rec.font = wr and (mapWord(wr) >> 8) or -1
    end),
    danceCursorTo(RONDO, "B: cursor onto Water Rondo"),
    H.call(function()
      rec.pend0, rec.bank0, rec.mp0, rec.bg0 = pend(mogSlot), bp(mogSlot), mpOf(mogSlot), H.readByte(0x11E2)
    end),
    H.driveUntil(function()
      return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF or dancing(mogSlot)
    end, 1800, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
          H.setPad(ph % 10 < 5 and { a = true } or {})
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "B: Water Rondo commits"),
    H.call(function() rec.committed = true end),
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      return rec.done ~= nil and H.frame >= rec.done.f + 20
    end, 20000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) ~= mogSlot then defendHands()
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "B: the start turn resolves"),
    H.call(function()
      local d = rec.done
      if not d then
        H.log(string.format("[rondo] B branch %d: the wave ended before the start resolved (no outcome)", k))
        return
      end
      H.log(string.format("[rondo] B branch %d: font %02X, confirm pending %d bank %d MP %d bg %02X | "
        .. "turn end pending %d MP %d dancing=%s tier %d bg %02X id %d stumbles %d",
        k, rec.font, rec.pend0, rec.bank0, rec.mp0, rec.bg0, d.pend, d.mp, tostring(d.dancing), d.tier, d.bg,
        d.id, rec.stumbles or 0))
    end),
  }
end

for k = 1, BRANCHES do for _, st in ipairs(branchB(k)) do body[#body + 1] = st end end

-- ---- C. the engine's pick ------------------------------------------------------
local function branchC(k)
  local req
  return {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap0.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (C branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { arm = "C", k = k, mp0 = mpOf(mogSlot), masks0 = #masks }
      recsC[#recsC + 1] = rec
      H.writeByte(0x32E1 + mogSlot * 2, RONDO)
      H.writeByte(0x3EE5 + mogSlot * 2, H.readByte(0x3EE5 + mogSlot * 2) | 0x20)
      rec.committed = true
      H.log(string.format("[rondo] C branch %d: MOG Muddled, dance id := Water Rondo (synthetic), %d MP",
        k, rec.mp0))
    end),
    H.waitFrames((k - 1) * 7 + 1),
    -- until his first random Dance resolves, then until a draw from the known
    -- dances (or the wave ends)
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      return rec.done ~= nil and #masks > rec.masks0 and H.frame >= rec.done.f + 20
    end, 40000, {
      H.call(function()
        ph = ph + 1
        if H.battleActive() and not muddled(mogSlot) and not dancing(mogSlot)
           and (H.readByte(0x3EE4 + mogSlot * 2) & 0xC2) == 0 then
          H.writeByte(0x3EE5 + mogSlot * 2, H.readByte(0x3EE5 + mogSlot * 2) | 0x20)
        end
        local hp, mx = H.readWord(0x3BF4 + mogSlot * 2), H.readWord(0x3C1C + mogSlot * 2)
        if H.battleActive() and hp > 0 and hp < mx // 2 then H.writeWord(0x3BF4 + mogSlot * 2, mx) end
        -- every open window Defends, MOG's own included: the window the
        -- snapshot holds was opened before the Muddle, and his turns after
        -- it are the engine's
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        else defendHands() end
      end),
      H.waitFrames(1),
    }, "C: MOG's random Dances"),
    H.call(function()
      local d = rec.done
      if not d then
        H.log(string.format("[rondo] C branch %d: no random Dance resolved before the wave ended", k))
        return
      end
      H.log(string.format("[rondo] C branch %d: first random Dance: stumbles %d, turn end pending %d MP %d "
        .. "(was %d) dancing=%s id %02X; draws after it: %d", k, rec.stumbles or 0, d.pend, d.mp, rec.mp0,
        tostring(d.dancing), d.id, #masks - rec.masks0))
    end),
  }
end

for k = 1, MUDDLES do for _, st in ipairs(branchC(k)) do body[#body + 1] = st end end

body[#body + 1] = H.call(function()
  H.setPad({})
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  local price = H.boostPrice(8, 3)
  local resolvedB, resolvedC = 0, 0
  for _, r in ipairs(recsB) do
    local d = r.done
    if d then
      resolvedB = resolvedB + 1
      check(r.font == WHITE, string.format("B %d: Water Rondo's row is white at three points (font %02X)", r.k, r.font))
      check(r.pend0 == 3, string.format("B %d: confirmed with pending %d (want 3)", r.k, r.pend0))
      check((r.stumbles or 0) == 0, string.format("B %d: the start stumbled", r.k))
      check(d.dancing, string.format("B %d: the dance did not lock in", r.k))
      check(d.tier == 3, string.format("B %d: the start recorded tier %d (want 3)", r.k, d.tier))
      check(r.mp0 - d.mp == price, string.format("B %d: charged %d MP (want %d)", r.k, r.mp0 - d.mp, price))
      check(d.bg == riverBg, string.format("B %d: background %02X after the start (want the river's %02X)",
        r.k, d.bg, riverBg))
    end
  end
  for _, r in ipairs(recsC) do
    local d = r.done
    if d then
      resolvedC = resolvedC + 1
      check((r.stumbles or 0) >= 1 and r.stumbleF <= d.f, string.format(
        "C %d: the Water Rondo start under three points did not stumble", r.k))
      check(d.mp == r.mp0, string.format("C %d: the stumble charged %d MP", r.k, r.mp0 - d.mp))
      check(d.pend == 0, string.format("C %d: %d pip(s) pending at the stumble's end", r.k, d.pend))
      check(not d.dancing, string.format("C %d: a dance locked in from the Water Rondo start", r.k))
      check(d.id == 0xFF, string.format("C %d: the dance id was left at %02X (want $FF)", r.k, d.id))
    end
  end
  for i, m in ipairs(masks) do
    check(m & (1 << RONDO) == 0, string.format("draw %d: RandDance drew from mask %04X, Water Rondo in it", i, m))
  end
  H.log(string.format("[rondo] SUMMARY B resolved %d of %d, C resolved %d of %d, random draws %d",
    resolvedB, #recsB, resolvedC, #recsC, #masks))
  for _, m in ipairs(fails) do H.log("[rondo] FAIL " .. m) end
  H.assertEq(resolvedB >= BRANCHES - 2, true, "B: at least BRANCHES-2 starts resolved")
  H.assertEq(resolvedC >= 1 and #masks >= 1, true, "C: a Water Rondo start and a random draw were observed")
  H.assertEq(#fails, 0, "every arm: the full boost is Water Rondo's one gate, and it never stumbles")
  H.log("[rondo] PASS")
end)

H.run({ maxFrames = 600000 }, body)

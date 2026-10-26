-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_waterrondo.lua -- Water Rondo is an ordinary dance (#478).
--
-- Water Rondo (dance 5) was Mog's divine (#380): greyed and buzzing under
-- three pending points, a start under three stumbling whatever the roll and
-- dropping its boost, and left out of a random Dance's draw.  The owner
-- (2026-10-26) made it one of his eight dances like the others, so it is
-- offered, priced, boosted and rolled as they are (#473's ladder), and a
-- random Dance can draw it.  This suite checks it where it used to differ.
--
-- Played from water-rondo-v1 (cold Continue on the Blackjack's tile outside
-- Nikeah: LOCKE, EDGAR, SABIN and MOG, who learned Water Rondo in the
-- Serpent Trench): the party walks into a world-map encounter, whose
-- background is not the river's, so a Water Rondo start's roll is live.
-- MOG's first command window is snapshotted; LOCKE, EDGAR and SABIN Defend
-- throughout.  Three arms:
--   A. the menu (real menus, nothing written): at pending 1, Water Rondo's
--      row is white, as another known dance's is, and A on it plays the
--      confirm, not the buzz, and closes the list.
--   B. the roll (real menus, nothing written): MOG Defends one turn to bank
--      two points; from that snapshot, branch k idles 7(k-1) frames (its own
--      draw), raises 1 or 2 points (alternately for the first BRANCHES, then
--      1) and starts Water Rondo, until a one-point start has both landed
--      and stumbled (at most MAX_B branches: a one-point start stumbles 1 in
--      4, so 56 one-point tries miss a stumble about once in 10^7).  Each start is predicted from the draw its roll
--      reads (RNGTbl[$be + 1], $be as Cmd_13 begins; battle_danceodds): at
--      1 point a draw below $40 stumbles, at 2 below $10.  Asserted per
--      resolved start: the row was white and the confirm took; it stumbled
--      exactly when the ladder says, and exactly when the dance did not lock
--      in; the boost is spent either way (the pips still pending at the
--      turn's Ot6ActionEnd, the bank down by them 20 frames on); a stumble
--      charges no MP and keeps the dance id; a landed start records its
--      tier, charges H.boostPrice(8, p) and turns the background to the
--      river's.  At one point, at least one start lands and one stumbles.
--   C. the engine's pick (SYNTHETIC, waivered: no battle Muddles MOG on
--      cue): from the first snapshot MOG is Muddled (STATUS2 bit 5, put back
--      if a hit clears it, his HP topped up under half) until RandDance
--      draws from the known dances (no dance chosen yet: $32E1 = $FF), at
--      most MUDDLES branches.  The mask RandBit is handed must be every
--      known dance, Water Rondo among them.
-- Red on the ROM before #478 (Water Rondo the divine) in all three arms.
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- WATERRONDO_BURN ahead of the file): the walker first fights that many
-- encounters on the walk's tiles, to vary the encounter history
-- (TESTING.md), with field care after them.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_DEF = 0x05, 0x21, 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local RONDO = 5
local DANCETIER = 0x7EEDA1              -- OT6_DANCETIER (ot6_memory.inc), stride 2
local WHITE = 0x21
local BRANCHES, MAX_B, MUDDLES = 8, 64, 6
local BURN = type(WATERRONDO_BURN) == "number" and WATERRONDO_BURN or 0
local FIGHT = {}
local THRESH = { [1] = 0x40, [2] = 0x10 }   -- the ladder (kits.md, Mog)

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

local mogSlot, ctlId = nil, nil
local ph = 0

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

local function findMog()
  mogSlot = nil
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
  end
  assert(mogSlot, "MOG is in the battle party")
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

-- ---- the world: walk two tiles until an encounter fires
local W = nil
local function pickWalk()
  return H.call(function()
      if W then return end
      -- two tiles in a line away from the save tile, Nikeah's gate (east of
      -- it) left out: the walk stays on open ground
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) and H.worldPassable(x + 2 * d[1], y + 2 * d[2]) then
          W = { { x + 2 * d[1], y + 2 * d[2] }, { x + d[1], y + d[2] } }
        end
      end
      assert(W, "two walkable tiles in a line beside the save tile, away from Nikeah")
      H.log(string.format("[rondo] walking (%d,%d) <-> (%d,%d)", W[1][1], W[1][2], W[2][1], W[2][2]))
    end)
end
local function walkIn()
  local wp = 1
  return H.seqStep({
    pickWalk(),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() or not H.worldAligned() then
          if not H.worldHasControl() then H.setPad({}) end
          return
        end
        local x, y = H.worldX(), H.worldY()
        if x == W[wp][1] and y == W[wp][2] then wp = wp % 2 + 1 end
        local tx, ty = W[wp][1], W[wp][2]
        local dir = tx > x and "right" or tx < x and "left" or ty > y and "down" or "up"
        H.setPad({ [dir] = true })
      end),
      H.waitFrames(1),
    }, "a world-map encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  })
end
-- BURN: the walker fights one encounter out on the walk's tiles
-- (battle_dancestep's)
local function fightThrough(what)
  local o0, wp = nil, 1
  return H.withReset(H.driveUntil(function() return o0 ~= nil and #H.outcomes > o0 end, 200000, {
    H.call(function() if o0 == nil then o0 = #H.outcomes end end),
    H.worldNavTo(function() return W[wp][1] end, function() return W[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.call(function() wp = wp % 2 + 1 end),
  }, what), function() o0, wp = nil, 1 end)
end
local function worldControl(what)
  return H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() end, 6000, what)
end

-- ---- observers --------------------------------------------------------------
local buzzes, confirms = 0, 0
local rec = nil                         -- the live branch's record
local draws = {}                        -- RandDance's draws from the known dances
local inRandDance = false

local function rng(i) return H.readRomByte((H.sym("RNGTbl") & 0x3FFFFF) + (i & 0xFF)) end
local function predicts(tier, d) return d < THRESH[tier] end

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
  local function mine(reg) return mogSlot and (emu.getState()["cpu." .. reg] & 0xFF) == mogSlot * 2 end
  -- the start's roll: Cmd_13 begins for MOG, not yet dancing; the draw a
  -- tier-1/2 roll reads is RNGTbl[$be + 1] (battle_danceodds)
  local c13 = H.sym("Cmd_13")
  emu.addMemoryCallback(function()
    if not (rec and rec.committed) or rec.roll or not mine("y") or dancing(mogSlot) then return end
    local be = H.readByte(0xBE)
    rec.roll = { f = H.frame, be = be, d = rng(be + 1), bg = H.readByte(0x11E2) }
  end, emu.callbackType.exec, c13, c13)
  local arm = findStumbleArm()
  emu.addMemoryCallback(function()
    if not rec or not mine("y") then return end
    rec.stumbles = (rec.stumbles or 0) + 1
  end, emu.callbackType.exec, arm, arm)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.committed) or rec.done or not mine("x") then return end
    if H.readByte(0x3A7C) ~= CMD_DANCE then return end
    rec.done = { f = H.frame, pend = pend(mogSlot), bank = bp(mogSlot), mp = mpOf(mogSlot),
                 dancing = dancing(mogSlot), tier = tierOf(mogSlot), bg = H.readByte(0x11E2),
                 id = H.readByte(0x32E1 + mogSlot * 2) }
  end, emu.callbackType.exec, ae, ae)
  -- RandDance's draw from the known dances: the RandBit right after a
  -- RandDance entry whose dance id is $ff (the only path that calls RandBit)
  local rd, rb = H.sym("RandDance"), H.sym("RandBit")
  emu.addMemoryCallback(function()
    if not mine("y") then return end
    inRandDance = H.readByte(0x32E1 + mogSlot * 2) == 0xFF
  end, emu.callbackType.exec, rd, rd)
  emu.addMemoryCallback(function()
    if not inRandDance then return end
    inRandDance = false
    draws[#draws + 1] = { mask = emu.getState()["cpu.a"] & 0xFFFF, known = H.readByte(DANCES) }
    H.log(string.format("[rondo] f%d RandDance draws from mask %04X (known dances %02X)", H.frame,
      draws[#draws].mask, draws[#draws].known))
  end, emu.callbackType.exec, rb, rb)
  H.log(string.format("[rondo] Cmd_13 $%06X, stumble arm $%06X, Ot6ActionEnd $%06X, RandDance $%06X, "
    .. "RandBit $%06X", c13, arm, ae, rd, rb))
end

local riverBg = nil
local fails = {}
local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end

-- A on the highlighted cell until the confirm sounds or buzzes
local function confirmCell(what)
  return H.driveUntil(function()
    return confirms > rec.confirms0 or buzzes > rec.buzzes0
  end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
        H.setPad(ph % 10 < 5 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- ---- the run ----------------------------------------------------------------
local snap0, snapB, reqB = nil, nil, nil
local recsB, recsC = {}, {}

local body = {
  H.bootCheckpoint("water-rondo-v1"),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() end, 6000,
    "world control at Nikeah"),
  H.call(function()
    local mask = H.readByte(DANCES)
    H.assertEq(mask & (1 << RONDO) ~= 0, true, string.format("MOG knows Water Rondo (known dances %02X)", mask))
    for d = 0, 7 do
      if ctlId == nil and d ~= RONDO and (mask & (1 << d)) ~= 0 then ctlId = d end
    end
    H.assertEq(ctlId ~= nil, true, "MOG knows a dance besides Water Rondo (the menu's control)")
    riverBg = H.readRomByte((H.sym("DanceBG") & 0x3FFFFF) + RONDO)
  end),
  pickWalk(),
}
for i = 1, BURN do
  body[#body + 1] = H.seqStep({
    fightThrough("BURN: the walker fights encounter " .. i),
    worldControl("world control after BURN " .. i),
    H.call(function()
      H.log(string.format("[rondo] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
        H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    end),
  })
end
if BURN > 0 then
  body[#body + 1] = H.fieldCare({ tag = "care after the BURN", threshold = H.CARE_BEFORE_FIGHTS })
  body[#body + 1] = worldControl("world control after the care")
end
for _, st in ipairs({
  H.call(function() installObservers() end),
  walkIn(),
  H.call(function()
    findMog()
    local bgDance = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
    H.assertEq(bgDance ~= RONDO and H.readByte(0x11E2) ~= riverBg, true,
      "the battle is off Water Rondo's terrain: the start's roll is live")
    H.log(string.format("[rondo] formation group $%04X, $be $%02X: MOG slot %d, %d MP, %d BP; bg %02X (its dance %d), "
      .. "river bg %02X; known dances %02X, control dance %d", H.readWord(0x11E0), H.readByte(0xBE), mogSlot,
      mpOf(mogSlot), bp(mogSlot), H.readByte(0x11E2), bgDance, riverBg, H.readByte(DANCES), ctlId))
  end),
  mogMenu("MOG's first window"),
  H.call(function()
    H.assertEq(mpOf(mogSlot) >= H.boostPrice(8, 2), true, string.format(
      "MOG's pool (%d) pays a two-point Dance start (%d): the price is not the reason", mpOf(mogSlot),
      H.boostPrice(8, 2)))
    H.assertEq(H.readByte(0x32E1 + mogSlot * 2), 0xFF, "MOG has chosen no dance yet ($32E1)")
    H.setPad({})
    snap0 = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap0, "snapshot at MOG's first window") end),

  -- ---- A. the menu: offered at one point, like any dance ----------------------
  raiseBoost(1, "A: R to pending 1"),
  openDance("A: the dance list opens"),
  H.waitFrames(20),
  H.call(function()
    local wr, td = findInMap(danceNameSeq(RONDO)), findInMap(danceNameSeq(ctlId))
    H.assertEq(wr ~= nil and td ~= nil, true, "both dances are drawn in the list")
    rec = { arm = "A", fontWR = mapWord(wr) >> 8, fontTD = mapWord(td) >> 8 }
    H.log(string.format("[rondo] A: pending %d: Water Rondo font %02X, control dance font %02X",
      pend(mogSlot), rec.fontWR, rec.fontTD))
  end),
  danceCursorTo(RONDO, "A: cursor onto Water Rondo"),
  H.call(function() rec.buzzes0, rec.confirms0 = buzzes, confirms end),
  confirmCell("A: Water Rondo is confirmed (or buzzes)"),
  H.waitFrames(60),
  H.call(function()
    H.setPad({})
    local a = rec
    a.buzzed, a.confirmed = buzzes > a.buzzes0, confirms > a.confirms0
    a.queue = H.readByte(0x32CC + mogSlot * 2)
    H.log(string.format("[rondo] A: confirm sounded %s, buzzed %s, MOG's queue $%02X, list open %s",
      tostring(a.confirmed), tostring(a.buzzed), a.queue, tostring(H.readByte(MSTATE) == ST_DANCE)))
    check(a.fontTD == WHITE, string.format("A: the control dance's row is white (font %02X)", a.fontTD))
    check(a.fontWR == WHITE, string.format("A: Water Rondo's row is white at one point (font %02X)", a.fontWR))
    check(a.confirmed and not a.buzzed, "A: A on Water Rondo at one point plays the confirm, not the buzz")
    check(H.readByte(MSTATE) ~= ST_DANCE, "A: the dance list closed on the confirm")
    rec = nil
  end),

  -- ---- B's snapshot: two points banked ---------------------------------------
  H.call(function() H.setPad({}); rec = nil; reqB = H.requestLoadState(snap0.blob) end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(reqB, "snapshot load (to bank B's points)")
    H.rearmInputInjection()
  end),
  mogDefends("B: MOG Defends (a point banked)"),
  mogMenu("B: MOG's second window"),
  H.call(function()
    H.assertEq(bp(mogSlot) >= 2, true, string.format("B: MOG banked two points (%d)", bp(mogSlot)))
    H.setPad({})
    snapB = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snapB, "snapshot at MOG's two-point window") end),
}) do body[#body + 1] = st end

-- ---- B. one or two points: the start rolls on the ladder ---------------------
-- a one-point start has landed and has stumbled
local function seenAtOne(stumble)
  for _, r in ipairs(recsB) do
    if r.p == 1 and r.done and not r.buzzed and ((r.stumbles or 0) > 0) == stumble then return true end
  end
  return false
end
local function branchB(k)
  local req
  local p = k <= BRANCHES and (k - 1) % 2 + 1 or 1
  return H.cond(function() return k <= BRANCHES or not (seenAtOne(true) and seenAtOne(false)) end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snapB.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (B branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { arm = "B", k = k, p = p }
      recsB[#recsB + 1] = rec
    end),
    H.waitFrames((k - 1) * 7 + 1),
    raiseBoost(p, "B: R to pending " .. p),
    openDance("B: the dance list opens"),
    H.waitFrames(20),
    H.call(function()
      local wr = findInMap(danceNameSeq(RONDO))
      rec.font = wr and (mapWord(wr) >> 8) or -1
    end),
    danceCursorTo(RONDO, "B: cursor onto Water Rondo"),
    H.call(function()
      rec.pend0, rec.bank0, rec.mp0 = pend(mogSlot), bp(mogSlot), mpOf(mogSlot)
      rec.buzzes0, rec.confirms0 = buzzes, confirms
      rec.committed = true
    end),
    H.driveUntil(function()
      return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF or dancing(mogSlot) or buzzes > rec.buzzes0
    end, 1800, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
          H.setPad(ph % 10 < 5 and { a = true } or {})
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "B: Water Rondo commits (or buzzes)"),
    H.call(function() rec.buzzed = buzzes > rec.buzzes0 end),
    H.driveUntil(function()
      if rec.buzzed or not H.battleLoadStarted() then return true end
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
      if rec.buzzed then
        H.log(string.format("[rondo] B branch %d (p=%d): the confirm buzzed (font %02X)", k, p, rec.font))
        return
      end
      if not d then
        H.log(string.format("[rondo] B branch %d (p=%d): the battle ended before the start resolved (no outcome)",
          k, p))
        return
      end
      rec.bankAfter = H.battleLoadStarted() and bp(mogSlot) or nil
      local r = rec.roll
      H.log(string.format("[rondo] B branch %d (p=%d): font %02X, confirm pending %d bank %d MP %d | roll %s | "
        .. "turn end pending %d MP %d dancing=%s tier %d bg %02X id %d stumbles %d | +20f bank %s",
        k, p, rec.font, rec.pend0, rec.bank0, rec.mp0,
        r and string.format("f%d $be $%02X draw $%02X bg $%02X, the ladder says %s", r.f, r.be, r.d, r.bg,
          predicts(p, r.d) and "stumble" or "lands") or "-",
        d.pend, d.mp, tostring(d.dancing), d.tier, d.bg, d.id, rec.stumbles or 0, tostring(rec.bankAfter)))
    end),
  }, {})
end

for k = 1, MAX_B do body[#body + 1] = branchB(k) end

-- ---- C. the engine's pick: a random Dance draws from every known dance -------
local function branchC(k)
  local req
  return H.cond(function() return #draws == 0 end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap0.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (C branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { arm = "C", k = k }
      recsC[#recsC + 1] = rec
      H.writeByte(0x3EE5 + mogSlot * 2, H.readByte(0x3EE5 + mogSlot * 2) | 0x20)
      H.log(string.format("[rondo] C branch %d: MOG Muddled (synthetic); dance id $%02X", k,
        H.readByte(0x32E1 + mogSlot * 2)))
    end),
    H.waitFrames((k - 1) * 7 + 1),
    H.driveUntil(function()
      return not H.battleLoadStarted() or #draws > 0
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
    }, "C: MOG's random Dance"),
    H.call(function()
      H.log(string.format("[rondo] C branch %d: %d draw(s) from the known dances", k, #draws))
      rec = nil
    end),
  }, {})
end

for k = 1, MUDDLES do body[#body + 1] = branchC(k) end

body[#body + 1] = H.call(function()
  H.setPad({})
  local resolvedB, landed, stumbled = 0, 0, 0
  for _, r in ipairs(recsB) do
    local d = r.done
    if r.buzzed then
      resolvedB = resolvedB + 1
      check(false, string.format("B %d: the confirm buzzed on Water Rondo at %d point(s) (font %02X)", r.k, r.p, r.font))
    elseif d then
      resolvedB = resolvedB + 1
      local st = (r.stumbles or 0) > 0
      if st then stumbled = stumbled + 1 else landed = landed + 1 end
      check(r.font == WHITE, string.format("B %d: Water Rondo's row is white at %d point(s) (font %02X)", r.k, r.p, r.font))
      check(r.pend0 == r.p, string.format("B %d: confirmed with pending %d (want %d)", r.k, r.pend0, r.p))
      check(r.roll ~= nil, string.format("B %d: MOG's start reached Cmd_13", r.k))
      if r.roll then
        local want = predicts(r.p, r.roll.d)
        check(st == want, string.format("B %d: at %d point(s), draw $%02X: stumbled=%s, the ladder says %s",
          r.k, r.p, r.roll.d, tostring(st), tostring(want)))
      end
      check(st == not d.dancing, string.format("B %d: stumbled=%s but dancing=%s", r.k, tostring(st),
        tostring(d.dancing)))
      check(d.pend == r.p, string.format("B %d: %d pip(s) pending at the turn's end (want %d: the boost is spent, "
        .. "not dropped)", r.k, d.pend, r.p))
      if r.bankAfter then
        check(r.bankAfter == r.bank0 - r.p, string.format("B %d: bank %d -> %d (want %d: %d spent, no regen)",
          r.k, r.bank0, r.bankAfter, r.bank0 - r.p, r.p))
      end
      if st then
        check(d.mp == r.mp0, string.format("B %d: the stumble charged %d MP (want 0)", r.k, r.mp0 - d.mp))
        check(d.id == RONDO, string.format("B %d: the dance id is %02X after the stumble (want Water Rondo's, %d)",
          r.k, d.id, RONDO))
      else
        check(d.tier == r.p, string.format("B %d: the start recorded tier %d (want %d)", r.k, d.tier, r.p))
        local price = H.boostPrice(8, r.p)
        check(r.mp0 - d.mp == price, string.format("B %d: charged %d MP (want %d)", r.k, r.mp0 - d.mp, price))
        check(d.bg == riverBg, string.format("B %d: background %02X after the start (want the river's %02X)",
          r.k, d.bg, riverBg))
      end
    end
  end
  for i, m in ipairs(draws) do
    check(m.mask == m.known and (m.mask & (1 << RONDO)) ~= 0, string.format(
      "draw %d: RandDance drew from mask %04X (want every known dance, %02X, Water Rondo among them)", i, m.mask,
      m.known))
  end
  H.log(string.format("[rondo] SUMMARY B resolved %d of %d (%d landed, %d stumbled); C %d branch(es), "
    .. "random draws %d; %d failure(s)", resolvedB, #recsB, landed, stumbled, #recsC, #draws, #fails))
  for _, m in ipairs(fails) do H.log("[rondo] FAIL " .. m) end
  H.assertEq(resolvedB >= BRANCHES - 2, true, "B: at least BRANCHES-2 starts resolved")
  H.log(string.format("[rondo] B at one point: landed %s, stumbled %s", tostring(seenAtOne(false)),
    tostring(seenAtOne(true))))
  H.assertEq(#draws >= 1, true, "C: a random Dance drew from the known dances")
  H.assertEq(#fails, 0, "Water Rondo is offered, rolled, settled and drawn like any dance")
  H.assertEq(seenAtOne(false) and seenAtOne(true), true,
    "B: a one-point Water Rondo start both landed and stumbled (the stumble settlement was exercised)")
  H.log("[rondo] PASS")
end)

H.run({ maxFrames = 600000 }, body)

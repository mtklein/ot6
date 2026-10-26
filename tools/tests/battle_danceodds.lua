-- @suite savestate=wor_tritoch slow
-- battle_danceodds.lua -- each boost point makes a Dance start less likely
-- to stumble (#473).
--
-- Off its terrain a Dance start stumbles on vanilla's coin in Cmd_13
-- (RandCarry: an even draw from RNGTbl, a permutation of 0-255, so exactly
-- 1/2).  Dance is a chance verb in this respect, on the Rage coin's ladder
-- (docs/design/kits.md, Mog): the start's tier (OT6_DANCETIER, the pending
-- boost Ot6DanceStartGate records) tilts the roll in Ot6DanceTerrain:
--   0 BP   vanilla's coin, untouched          stumble when the draw is even
--   1 BP   a fresh draw < $40 stumbles        1/4
--   2 BP   a fresh draw < $10 stumbles        1/16
--   3 BP   never                              0
-- Both rules take the next RNGTbl entry, so the draw the start's roll reads
-- is RNGTbl[$be + 1], with $be read as Cmd_13 begins.  Each branch's outcome
-- is predicted from that draw by the rule for its level: an exact check of
-- the rule on every draw the branches meet, not a sample of the odds.  The
-- thresholds themselves are read from the built ROM (Ot6DanceStumbleOdds)
-- and counted against RNGTbl: 64, 16 and 0 of its 256 entries, the odds.
--
-- The run is the real MOG on the World of Ruin map (wor_tritoch), with
-- battle_dancestumble's walk-in: a world-map encounter, the lowest-numbered
-- known dance that is not the background's own (so the roll is live), his
-- party Defending.  Nothing is written anywhere in this file.  His first
-- command window is snapshotted and branched.  Each branch takes the first
-- level still short of its coverage (from a rotation), Defends enough turns
-- to bank that level (each unboosted turn earns a pip; he opens with one)
-- plus n % 6 more, n being how often the level has branched in this seat
-- (the draw's variation), then raises the boost to the level with R and
-- starts the dance.  A level is covered when it has MIN_PER resolved starts
-- and, for 1-3, one whose draw tells its rule from vanilla's coin (an even
-- draw at or above its threshold, or an odd one below); levels 1 and 2 also
-- need a start whose draw the rule says stumbles (below $40, below $10), so
-- the boosted stumble itself is exercised, not only landings; 0 BP needs
-- both outcomes.  A level-2 stumble is a 1-in-16 draw and one seat gives
-- only a few distinct draws, so when a seat's MAX_BRANCHES are used (or
-- LOST_RUN in a row give no outcome) the same encounter is walked into
-- again from its world-map snapshot one frame later each time: a seat.  The
-- battle RNG starts from the game clock's frame (4 to $be per frame), so each
-- seat is a fresh draw of the same formation.  Stops at the first witness;
-- else an encounter gets DISTINCT_BE distinct $be (a repeat is skipped) and
-- there are MAX_ENCOUNTERS encounters.
-- Observed, never written: $be, the background and the pending boost as
-- Cmd_13 begins; the stumble arm's execution ("Stumbled!!", found by its
-- bytes); MOG's pending boost, bank, MP, DANCE status and the background at
-- the start turn's Ot6ActionEnd, and his bank 20 frames later.
-- Asserted, per branch whose start turn resolved:
--   1. the start was confirmed at the branch's level, off its terrain;
--   2. it stumbled exactly when its level's rule says, from the draw;
--   3. it stumbled exactly when the dance did not lock in, and a landed
--      start turned the background to the dance's own (DanceBG);
--   4. the settlement: a stumble charged no MP, a start the boosted price
--      (H.boostPrice(8, level)); either way a boosted level's pips were
--      spent (bank down by the level, #473) and 0 BP earned the regen pip;
-- and, from the ROM, the three thresholds' odds over RNGTbl.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tritoch.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE = 0x05, 0x21
local ST_DEF = 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local MIN_PER, MAX_BRANCHES = 3, 16      -- branches per seat
local MAX_EXTRA = 6                       -- extra Defends cycle 0..5
-- Walk-ins per encounter.  The battle seed ($be, InitBattle) is the clock's
-- frame times 4 mod 256, so 64 walk-ins stepped one frame apart are 64
-- distinct seeds; an encounter is given DISTINCT_BE of them (55) before the
-- next encounter is taken, SEATS (64) walk-ins at most.
local SEATS, DISTINCT_BE = 64, 55
local THRESH = { [1] = 0x40, [2] = 0x10, [3] = 0x00 }   -- the design (kits.md)
local WANT_OF_256 = { [1] = 64, [2] = 16, [3] = 0 }     -- its odds over RNGTbl
-- The encounter is whatever the world deals; battle_dancestumble's handling
-- (#454): LOST_RUN branches in a row without an outcome, or MAX_BRANCHES
-- used, and the next encounter is taken, at most MAX_ENCOUNTERS.
local LOST_RUN, MAX_ENCOUNTERS = 3, 2

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end

local function rng(i) return H.readRomByte((H.sym("RNGTbl") & 0x3FFFFF) + (i & 0xFF)) end
local function bgDance(bg) return H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg) end
local function danceBg(id) return H.readRomByte((H.sym("DanceBG") & 0x3FFFFF) + id) end

-- the rule under test: does a start at `level` stumble on draw d?
local function predicts(level, d)
  if level == 0 then return (d & 1) == 0 end       -- RandCarry: carry clear
  return d < THRESH[level]
end
-- does draw d tell the level's rule from vanilla's coin?
local function telling(level, d)
  return level > 0 and predicts(level, d) ~= predicts(0, d)
end

local mogSlot, danceId, offId = nil, nil, nil
local enc, encs, encLost, lostRun, seat = 0, {}, nil, 0, 0
local seenBe, nBe = {}, 0      -- this encounter's distinct $be, and their count

-- why MOG's turn can no longer come in this battle, or nil
local function lostWhy()
  if not H.battleLoadStarted() then return "the battle ended" end
  local s = mogSlot
  local hp, st1 = H.readWord(0x3BF4 + s * 2), H.readByte(0x3EE4 + s * 2)
  if hp == 0 or (st1 & 0xC2) ~= 0 then
    return string.format("MOG (slot %d) is down (HP %d, STATUS1 $%02X)", s, hp, st1)
  end
  -- the wave won under the branch (the bystanders' Defends spend turns the
  -- monsters die in): victory pages follow, and the dance window never comes
  local present, standing = 0, 0
  for e = 4, 9 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      present = present + 1
      if H.readWord(0x3BF4 + e * 2) > 0 then standing = standing + 1 end
    end
  end
  if present > 0 and standing == 0 then return "the wave was won (no enemy standing)" end
  return nil
end
local ph = 0

-- the bystanders' hands: Defend from the command window, page dialogs
local function bystander()
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

local rec = nil           -- the live branch's record
local function lostNow()
  if rec == nil then encLost = encLost or lostWhy(); return encLost ~= nil end
  rec.lost = rec.lost or lostWhy()
  return rec.lost ~= nil
end

local function mogMenu(what)
  return H.driveUntil(function()
    if rec and rec.lost then return true end
    if H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD then return true end
    return lostNow()
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if not H.battleLoadStarted() then H.setPad({}) return end
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= mogSlot then bystander()
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- R until MOG's pending boost reads the branch's level (edge presses, read back)
local function raiseBoost(what)
  return H.driveUntil(function()
    if rec.lost or lostNow() then return true end
    return H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
       and pend(mogSlot) == rec.b
  end, 900, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MSTATE) ~= ST_CMD or H.readByte(ACTOR) ~= mogSlot then
        H.setPad({}) return
      end
      local p = pend(mogSlot)
      if p < rec.b then H.setPad(ph % 10 < 5 and { r = true } or {})
      elseif p > rec.b then H.setPad(ph % 10 < 5 and { l = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

local function openDance(what)
  return H.driveUntil(function()
      if rec.lost or lostNow() then return true end
      return H.readByte(MSTATE) == ST_DANCE
    end, 1200, {
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

local function danceCursorTo(what)   -- onto offId, read when it runs
  return H.driveUntil(function()
    if rec.lost or lostNow() then return true end
    local id = offId
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
      local id = offId
      local row, col = id // 2, id % 2
      local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
      if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
      elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- ---- observers --------------------------------------------------------------
local recs = {}           -- one per branch

-- the stumble arm, by its bytes: `lda #$06 / sta $3401` ("Stumbled!!")
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
  local arm = findStumbleArm()
  local c13 = H.sym("Cmd_13")
  -- the start's roll: $be as Cmd_13 begins (nothing before the roll draws)
  emu.addMemoryCallback(function()
    if not (rec and rec.pend0 and mogSlot) or rec.roll then return end
    if (emu.getState()["cpu.y"] & 0xFF) ~= mogSlot * 2 then return end
    local be = H.readByte(0xBE)
    rec.roll = { be = be, d = rng(be + 1), bg = H.readByte(0x11E2),
                 pend = pend(mogSlot) }
  end, emu.callbackType.exec, c13, c13)
  emu.addMemoryCallback(function()
    if not (rec and rec.roll and mogSlot) then return end
    if (emu.getState()["cpu.y"] & 0xFF) ~= mogSlot * 2 then return end
    rec.stumbled = true
  end, emu.callbackType.exec, arm, arm)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.roll and mogSlot) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= mogSlot * 2 then return end
    if H.readByte(0x3A7C) ~= CMD_DANCE then return end
    rec.done = { f = H.frame, pend = pend(mogSlot), bank = bp(mogSlot),
                 mp = mpOf(mogSlot), dancing = dancing(mogSlot),
                 bg = H.readByte(0x11E2) }
  end, emu.callbackType.exec, ae, ae)
  H.log(string.format("[danceodds] Cmd_13 $%06X, stumble arm $%06X, Ot6ActionEnd $%06X",
    c13, arm, ae))
end

-- per level: resolved, stumbles, landings, telling draws, and draws on
-- which the level's rule predicts a stumble
local function tally()
  local t = {}
  for l = 0, 3 do t[l] = { res = 0, st = 0, dn = 0, tell = 0, pst = 0 } end
  for _, r in ipairs(recs) do
    if r.after then
      local x = t[r.b]
      x.res = x.res + 1
      if r.stumbled then x.st = x.st + 1 else x.dn = x.dn + 1 end
      if telling(r.b, r.roll.d) then x.tell = x.tell + 1 end
      if predicts(r.b, r.roll.d) then x.pst = x.pst + 1 end
    end
  end
  return t
end
-- is level l still short of its coverage?
local function short(t, l)
  local x = t[l]
  if x.res < MIN_PER then return true end
  if l == 0 then return x.st == 0 or x.dn == 0 end
  if x.tell == 0 then return true end
  return l <= 2 and x.pst == 0       -- a boosted start the rule says stumbles
end
local function needMore()
  local t = tally()
  for l = 0, 3 do if short(t, l) then return true end end
  return false
end
-- the level a new branch takes: the first short level from a rotation
local function pickLevel(k)
  local t = tally()
  for i = 0, 3 do
    local l = (k - 1 + i) % 4
    if short(t, l) then return l end
  end
  return (k - 1) % 4
end

local snap = nil
local dupSeat = false   -- this seat's $be was met already: same draws, skipped
local seatUses = {}       -- branches each level has taken in this seat
local function branch(bi, wait)
  local k                      -- the record's number (#recs + 1), set below
  local req
  local level, defends = nil, nil
  return H.cond(function()
    return needMore() and encLost == nil and lostRun < LOST_RUN and not dupSeat
  end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (encounter " .. enc .. " seat " .. seat .. " branch " .. bi .. ")")
      H.rearmInputInjection()
      level = pickLevel(bi)
      -- the draw: Defends before the start move the battle RNG; a level
      -- this seat has used n times Defends n % MAX_EXTRA more turns
      local n = seatUses[level] or 0
      seatUses[level] = n + 1
      defends = math.max(level - 1, 0) + n % MAX_EXTRA
      k = #recs + 1
      rec = { k = k, b = level, wait = wait, enc = enc, seat = seat, defs = 0 }
      recs[#recs + 1] = rec
      H.log(string.format("[danceodds] branch %d (encounter %d seat %d): level %d, %d idle frames, %d Defends",
        k, enc, seat, level, wait, defends))
    end),
    H.waitFrames(wait + 1),
    H.repeatN(MAX_EXTRA + 2, { H.cond(function() return not rec.lost and rec.defs < defends end, {
      H.call(function() rec.defs = rec.defs + 1 end),
      H.driveUntil(function()
        if rec.lost or lostNow() then return true end
        return H.readByte(MENU) == 0 or H.readByte(ACTOR) ~= mogSlot
      end, 1800, {
        H.call(function()
          ph = ph + 1
          if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
            if pend(mogSlot) > 0 and H.readByte(MSTATE) == ST_CMD then
              H.setPad(ph % 10 < 5 and { l = true } or {})
            else bystander() end
          else H.setPad({}) end
        end),
        H.waitFrames(1),
      }, "MOG Defends (the draw, and the pips)"),
      mogMenu("MOG's next window"),
    }, {}) }),
    H.call(function()
      if rec.lost then return end
      H.assertEq(bp(mogSlot) >= level, true, string.format(
        "branch %d: MOG banked the level's %d pip(s) by Defending (bank %d)",
        k, level, bp(mogSlot)))
    end),
    raiseBoost("R to the branch's level"),
    openDance("the dance list opens"),
    H.waitFrames(20),
    danceCursorTo("cursor onto the off-terrain dance's cell"),
    H.call(function()
      if rec.lost then return end
      rec.pend0, rec.bank0, rec.mp0 = pend(mogSlot), bp(mogSlot), mpOf(mogSlot)
      H.log(string.format("[danceodds] confirm: level %d, pending %d, bank %d, %d MP",
        level, rec.pend0, rec.bank0, rec.mp0))
    end),
    H.driveUntil(function()
      if rec.lost or lostNow() then return true end
      return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF or dancing(mogSlot) or rec.roll ~= nil
    end, 1800, {
      -- the wave can end under the confirm: the victory pages wait for A
      -- (battle_dancestumble's same step)
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) == mogSlot then
          H.setPad(ph % 10 < 5 and { a = true } or {})
        else bystander() end
      end),
      H.waitFrames(1),
    }, "the dance commits"),
    -- run until 20 frames past the start turn's end (or the wave's end)
    H.driveUntil(function()
      if rec.lost then return true end
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(mogSlot), mp = mpOf(mogSlot) }
        return true
      end
      if not rec.done then return lostNow() end
      return false
    end, 20000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) ~= mogSlot then bystander()
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "MOG's dance start turn resolves"),
    H.call(function()
      local d, a, r = rec.done, rec.after, rec.roll
      if not (d and a and r) then
        rec.after = nil
        lostRun = lostRun + 1
        H.log(string.format("[danceodds] branch %d (encounter %d): %s before "
          .. "the start turn resolved (no outcome; %d in a row here)", k, enc,
          rec.lost or "the wave ended", lostRun))
        return
      end
      lostRun = 0
      H.log(string.format("[danceodds] branch %d level %d %s: $be $%02X draw $%02X "
        .. "predicts %s%s | roll bg $%02X pending %d | confirm pending %d bank %d "
        .. "MP %d | turn end f%d pending %d bank %d MP %d dancing=%s bg $%02X "
        .. "| +20f bank %d", k, level,
        rec.stumbled and "STUMBLED" or (d.dancing and "DANCED" or "NEITHER"),
        r.be, r.d, predicts(level, r.d) and "stumble" or "lands",
        telling(level, r.d) and " (tells from vanilla)" or "", r.bg, r.pend,
        rec.pend0, rec.bank0, rec.mp0, d.f, d.pend, d.bank, d.mp,
        tostring(d.dancing), d.bg, a.bank))
    end),
  })
end

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the World of Ruin map"),
  H.call(function() installObservers() end),
}

local function worldControl(what)
  return H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, what)
end

-- battle_gaufight's walk: alternate left/right at tile boundaries until the
-- world's own encounter roll wins
local function walkIn()
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        ph = ph + 1
        H.setPad({ [(ph % 2 == 0) and "left" or "right"] = true })
      end),
      H.waitFrames(1),
    }, "a world-map encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
    H.waitFrames(240),
  })
end

-- the walker fights the encounter the world map holds next, from here
local function fightThrough(what)
  local o0, wp, W = nil, 1, nil
  return H.withReset(H.driveUntil(function()
    return o0 ~= nil and #H.outcomes > o0
  end, 200000, {
    H.call(function()
      if o0 ~= nil then return end
      o0 = #H.outcomes
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
      assert(W, "a walkable tile beside the party")
    end),
    H.worldNavTo(function() return W[wp][1] end, function() return W[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical" }),
    H.call(function() wp = wp % #W + 1 end),
  }, what), function() o0, wp, W = nil, 1, nil end)
end

-- encounter e: from encounter e-1's world map (restored, and that encounter
-- fought out by the walker), the party cared for, the world map
-- snapshotted, the walk in, MOG's first window snapshotted, the branches
local seatOf
local function encounter(e)
  local req
  local out = {
    H.cond(function() return e > 1 end, {
      H.call(function()
        H.setPad({}); rec = nil
        req = H.requestLoadState(encs[e - 1].blob)
      end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "world-map snapshot load (encounter " .. (e - 1) .. ")")
        H.rearmInputInjection()
      end),
      worldControl("world control before encounter " .. (e - 1)),
      fightThrough("the walker fights encounter " .. (e - 1) .. " out"),
    }, {}),
    worldControl("world control before encounter " .. e),
    H.fieldCare({ tag = "care before encounter " .. e, threshold = H.CARE_BEFORE_FIGHTS }),
    worldControl("world control after the care (encounter " .. e .. ")"),
    H.call(function()
      H.assertEq(H.charHp(MOG) > 0 and (H.charStatus1(MOG) & 0xC2) == 0, true, string.format(
        "encounter %d: MOG stands before the walk in (HP %d, STATUS1 $%02X)", e,
        H.charHp(MOG), H.charStatus1(MOG)))
      rec, enc = nil, e
      seenBe, nBe = {}, 0
      encs[e] = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(encs[e], "world-map snapshot (encounter " .. e .. ")") end),
  }
  for s = 1, SEATS do out[#out + 1] = H.cond(function() return needMore() and nBe < DISTINCT_BE end, { seatOf(e, s) }, {}) end
  return H.seqStep(out)
end

-- seat s of encounter e: the same encounter walked into again from its
-- world-map snapshot, s frames later.  The battle RNG starts from the
-- game clock's frame (InitBattle: $be, 4 per frame mod 256), so each seat is
-- another draw of the same formation; the encounter counters, and so the
-- formation, do not move.  A seat whose $be was met already would repeat that
-- seat's draws and is skipped; it does not count toward DISTINCT_BE.
seatOf = function(e, s)
  local req
  local out = {
    H.cond(function() return s > 1 end, {
      H.call(function()
        H.setPad({}); rec = nil
        req = H.requestLoadState(encs[e].blob)
      end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "world-map snapshot load (encounter " .. e .. " seat " .. s .. ")")
        H.rearmInputInjection()
      end),
      worldControl("world control (encounter " .. e .. " seat " .. s .. ")"),
    }, {}),
    H.call(function() rec, encLost, lostRun, seat, seatUses, dupSeat = nil, nil, 0, s, {}, false end),
    H.waitFrames(s),
    walkIn(),
    H.call(function()
      findMog()
      local be = H.readByte(0xBE)
      dupSeat = seenBe[be] ~= nil
      if not dupSeat then seenBe[be] = s; nBe = nBe + 1 end
      H.log(string.format("[danceodds] encounter %d seat %d (%d idle frames): $be $%02X, %s "
        .. "(%d distinct $be of %d this encounter)", e, s, s,
        be, dupSeat and ("a repeat of seat " .. seenBe[be] .. ", skipped") or "new", nBe, DISTINCT_BE))
      local mask = H.readByte(DANCES)
      danceId = bgDance(H.readByte(0x11E2))
      offId = nil
      for d = 0, 7 do
        if mask & (1 << d) ~= 0 and d ~= danceId then offId = d; break end
      end
      H.assertEq(offId ~= nil, true, string.format(
        "MOG knows a dance that is not this background's (mask %02X, terrain dance %d)",
        mask, danceId))
      H.log(string.format("[danceodds] encounter %d seat %d: formation group $%04X, $be $%02X; "
        .. "known mask %02X, terrain dance %d, chosen dance %d; MOG slot %d, %d MP, %d BP", e, s,
        H.readWord(0x11E0), H.readByte(0xBE), mask, danceId, offId, mogSlot, mpOf(mogSlot), bp(mogSlot)))
    end),
    H.cond(function() return not dupSeat end, { mogMenu("MOG's command window") }, {}),
    H.cond(function() return encLost == nil and not dupSeat end, {
      H.call(function()
        H.assertEq(mpOf(mogSlot) >= H.boostPrice(8, 3), true, string.format(
          "MOG's real pool (%d) pays a boost-3 dance start (%d)",
          mpOf(mogSlot), H.boostPrice(8, 3)))
        H.setPad({})
        snap = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap, "snapshot at MOG's window") end),
    }, {
      H.call(function()
        if dupSeat then return end
        H.log(string.format("[danceodds] encounter %d: %s before MOG's first window: "
          .. "no branch here", e, encLost))
      end),
    }),
  }
  for bi = 1, MAX_BRANCHES do out[#out + 1] = branch(bi, (bi - 1) * 7) end
  return H.seqStep(out)
end
for e = 1, MAX_ENCOUNTERS do
  body[#body + 1] = H.cond(function() return needMore() end, { encounter(e) }, {})
end
body[#body + 1] = H.call(function()
  H.setPad({})
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    local d, a, roll = r.done, r.after, r.roll
    if a then
      local want = predicts(r.b, roll.d)
      check(r.pend0 == r.b and roll.pend == r.b, string.format(
        "branch %d: the start was confirmed with pending %d (%d at the roll), want %d",
        r.k, r.pend0, roll.pend, r.b))
      check(bgDance(roll.bg) ~= offId, string.format(
        "branch %d: the dance (%d) is off the roll's background ($%02X)", r.k, offId, roll.bg))
      check((r.stumbled or false) == want, string.format(
        "branch %d: level %d, draw $%02X: stumbled=%s, the rule says %s", r.k, r.b,
        roll.d, tostring(r.stumbled or false), tostring(want)))
      check((r.stumbled or false) == (not d.dancing), string.format(
        "branch %d: stumbled=%s but dancing=%s", r.k, tostring(r.stumbled), tostring(d.dancing)))
      local regen = math.min(5, r.bank0 + 1)
      local bankWant = r.b == 0 and regen or r.bank0 - r.b
      check(a.bank == bankWant, string.format(
        "branch %d: level %d, bank %d -> %d (want %d: %s)", r.k, r.b, r.bank0, a.bank,
        bankWant, r.b == 0 and "the unboosted regen" or "the boost spent"))
      if r.stumbled then
        check(d.mp == r.mp0, string.format(
          "branch %d: a stumbled start charged %d MP (want 0)", r.k, r.mp0 - d.mp))
      else
        check(r.mp0 - d.mp == H.boostPrice(8, r.b), string.format(
          "branch %d: a started dance charged %d MP (want %d)", r.k, r.mp0 - d.mp,
          H.boostPrice(8, r.b)))
        check(d.bg == danceBg(offId), string.format(
          "branch %d: a landed start left background $%02X (want the dance's $%02X)",
          r.k, d.bg, danceBg(offId)))
      end
    end
  end
  local t = tally()
  for l = 0, 3 do
    H.log(string.format("[danceodds] SUMMARY level %d: resolved %d, stumbled %d, "
      .. "danced %d, draws telling the rule from vanilla %d, draws the rule says stumble %d",
      l, t[l].res, t[l].st, t[l].dn, t[l].tell, t[l].pst))
  end
  for _, m in ipairs(fails) do H.log("[danceodds] FAIL " .. m) end
  -- the ladder's thresholds in the built ROM, as odds over RNGTbl
  -- (a literal H.sym call: compose.py injects only the names it sees)
  local ok, base = pcall(function() return H.sym("Ot6DanceStumbleOdds") end)
  local romFails = {}
  if not ok then
    romFails[1] = "Ot6DanceStumbleOdds is not in this ROM: no ladder"
  else
    base = base & 0x3FFFFF
    for l = 1, 3 do
      local th = H.readRomByte(base + l - 1)
      local n = 0
      for i = 0, 255 do if rng(i) < th then n = n + 1 end end
      H.log(string.format("[danceodds] ROM level %d: threshold $%02X, %d of 256 RNGTbl "
        .. "entries stumble (want %d)", l, th, n, WANT_OF_256[l]))
      if th ~= THRESH[l] or n ~= WANT_OF_256[l] then
        romFails[#romFails + 1] = string.format("level %d threshold $%02X (%d/256), want $%02X (%d/256)",
          l, th, n, THRESH[l], WANT_OF_256[l])
      end
    end
  end
  local even = 0
  for i = 0, 255 do if (rng(i) & 1) == 0 then even = even + 1 end end
  H.log(string.format("[danceodds] ROM level 0: vanilla's coin, %d of 256 RNGTbl entries even", even))
  for _, m in ipairs(romFails) do H.log("[danceodds] FAIL ROM " .. m) end
  H.assertEq(#fails, 0, "every resolved start stumbled by its level's rule and settled (#473)")
  for l = 0, 3 do
    H.assertEq(t[l].res >= MIN_PER, true, string.format(
      "level %d: at least %d starts resolved (%d)", l, MIN_PER, t[l].res))
  end
  for l = 1, 3 do
    H.assertEq(t[l].tell >= 1, true, string.format(
      "level %d: a draw that tells its rule from vanilla's coin was met", l))
  end
  for l = 1, 2 do
    H.assertEq(t[l].pst >= 1, true, string.format(
      "level %d: a start whose draw the rule says stumbles was met (the stumble arm exercised)", l))
  end
  H.assertEq(t[0].st >= 1 and t[0].dn >= 1, true, "0 BP: both outcomes seen")
  H.assertEq(#romFails, 0, "the ROM's thresholds are 1/4, 1/16 and never (#473)")
end)

-- Worst case, no witness anywhere: a seat of 16 branches costs ~38k frames
-- (build/attempts/wt/v037-danceodds-seats/exhaust3.out: 30 seats, 31 walk-ins,
-- PASS at frame 1171225 with level 2 never satisfied), and an encounter is at
-- most SEATS = 64 walk-ins (a repeated $be is skipped, nearly free), so two
-- encounters are 2 * 64 * 40k = 5.1M frames, plus ~0.2M to reach the first and
-- fight it out: under 6M.  The normal run stops at the first witness.
H.run({ maxFrames = 6000000 }, body)

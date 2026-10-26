-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_dancestep.lua -- a locked-in Dance step that meets another
-- dancer's background rolls on its start's ladder (#473, #476).
--
-- The tier a Dance start bought (OT6_DANCETIER) is read by every step of
-- that dance (kits.md, Mog: "a locked-in step that meets another dancer's
-- background rolls on the same odds"), a rule in Ot6DanceTerrain
-- (ot6_dance.asm) that battle_danceodds and battle_dancestumble, which roll
-- only starts, do not reach.  Another dancer's landed start turns the
-- background to his dance's, so MOG's next step is off its terrain and
-- rolls: at tier 1 a draw below $40 stumbles, at tier 2 below $10, where
-- vanilla's coin stumbles on any even draw.  Both take the next RNGTbl
-- entry, so the draw a step's roll reads is RNGTbl[$be + 1], $be read as
-- Cmd_13 begins (battle_danceodds' prediction), and each such step is
-- predicted from the tier MOG's START recorded, not from the byte the step
-- reads, so a step that read some other tier is caught.
--
-- Played, nothing written: Continue wor-gogo-v1 (beside the Falcon by
-- Thamasa), board, and in the Falcon's cabin seat MOG, GOGO, TERRA and
-- CELES (route-wor-gogo.md's regroup; no route state seats MOG beside
-- GOGO); in the field menu give GOGO Dance in his second row (his kit
-- keeps Mimic in the first); lift off, land by Ebot's Rock and walk into a
-- world-map encounter.  The battle's first command window is snapshotted
-- and branched; TERRA and CELES Defend throughout.
--   B(t), t = 1 or 2: MOG starts the background's own dance if he knows it
--      (no roll), else the first known dance, at pending t; once he is
--      dancing GOGO starts, unboosted, a known dance whose background is
--      not MOG's, again at each window while he is not dancing.  Every MOG
--      step that comes in on a background not his dance's is an observation.
-- A seat is the encounter walked into again from its world-map snapshot,
-- s frames later (another $be, the same formation); a branch idles 7k
-- frames more and Defends MOG (k-1) % 3 more turns first.  An encounter
-- that keeps ending before an outcome (LOST_RUN) is fought out by the
-- walker and the next is taken, at most MAX_ENCOUNTERS.
-- A confirm counts once the seat's command list holds it (a Dance pick
-- opens a target window first).
-- Asserted, per observation: MOG's start tier was t; the step stumbled
-- exactly when the tier's rule says from its draw.  Coverage: each tier
-- MIN_B observations, one with a draw on which the tier's rule and
-- vanilla's coin disagree (TELL).
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- DANCESTEP_BURN ahead of the file): the walker fights that many encounters
-- on the landing's tiles first, to vary the encounter history (TESTING.md).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CELES, MOG, GOGO = 0x00, 0x06, 0x0A, 0x0C
local NAMES = { [TERRA] = "TERRA", [CELES] = "CELES", [MOG] = "MOG", [GOGO] = "GOGO" }
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_DEF, ST_TGT = 0x05, 0x21, 0x27, 0x38
local CMD_DANCE = 0x13
local CMDTBL, CMDROW = 0x202E, 0x890F
local DANCES = 0x1D4C
local DANCETIER = 0x7EEDA1              -- OT6_DANCETIER (ot6_memory.inc), stride 2
local LANDING = { 250, 224 }            -- gen_wor_ebot's landing by Ebot's Rock
local BURN = type(DANCESTEP_BURN) == "number" and DANCESTEP_BURN or 0
local MIN_B = 3
local SEATS, MAX_BRANCHES, LOST_RUN, MAX_ENCOUNTERS = 8, 12, 4, 3
local BRANCH_FRAMES = 30000             -- a branch's budget once it starts
local THRESH = { [1] = 0x40, [2] = 0x10 }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, names = NAMES })
local regroup, liftOff, say = K.regroup, K.liftOff, K.say

local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end
local function tierOf(s) return emu.read(DANCETIER + s * 2, emu.memType.snesMemory) end
local function rng(i) return H.readRomByte((H.sym("RNGTbl") & 0x3FFFFF) + (i & 0xFF)) end
local function bgDance(bg) return H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg) end
local function danceBg(id) return H.readRomByte((H.sym("DanceBG") & 0x3FFFFF) + id) end
local function predicts(tier, d)
  if tier == 0 then return (d & 1) == 0 end
  return d < THRESH[tier]
end
local function telling(tier, d) return predicts(tier, d) ~= predicts(0, d) end

-- ---- GOGO's commands (gen_wor_gogo's field-menu walk) ----------------------
-- $05 main (Status row 4) -A-> $06 character select -A-> $0c status (the
-- command row) -A-> $6a the command list ($7E9D8A + row, $7E9D89 the count;
-- MenuState_6a writes the row's id to $1616 + 37*GOGO + row)
local function gogoCmdByte(row) return H.readByte(0x1600 + 37 * GOGO + 0x16 + row) end
local function gogoCommands(want, what)
  local ph, idx, listLogged = 0, 1, false
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, row)
    if cur == row then return { "a" } end
    return { [cur < row and "down" or "up"] = true }
  end
  local function gogoPos()
    for p = 0, 3 do
      local b = H.readByte(0x1850 + GOGO)
      if (b & 7) == H.activeParty() and ((b >> 3) & 3) == p then return p end
    end
    return nil
  end
  local function allSet()
    for _, w in ipairs(want) do if gogoCmdByte(w[1]) ~= w[2] then return false end end
    return true
  end
  return H.withReset(H.seqStep({
    H.driveUntil(function() return allSet() and not H.menuRunning() and H.hasControl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s = st()
        local held = {}
        while idx <= #want and gogoCmdByte(want[idx][1]) == want[idx][2] do idx = idx + 1 end
        if allSet() then
          if s ~= -1 then held = { "b" } end
        elseif s == -1 then
          if H.hasControl() then held = { "x" } end
        elseif s == 0x05 then
          held = steer(H.readByte(0x4B), 4)
        elseif s == 0x06 then
          local p = gogoPos()
          if p == nil then error(what .. ": GOGO is not in the active party", 0) end
          held = steer(H.readByte(0x4B), p)
        elseif s == 0x0C then
          held = steer(H.readByte(0x4B), want[idx][1])
        elseif s == 0x6A then
          local n = H.readByte(0x7E9D89)
          if not listLogged then
            local t = {}
            for r = 0, n - 1 do t[#t + 1] = string.format("%02X", H.readByte(0x7E9D8A + r)) end
            H.log(string.format("[dancestep] %s: GOGO's command list (%d): %s", what, n, table.concat(t, " ")))
            listLogged = true
          end
          local row = nil
          for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == want[idx][2] then row = r end end
          if row == nil then error(string.format("%s: command $%02X is not in GOGO's list", what, want[idx][2]), 0) end
          held = steer(H.readByte(0x4B), row)
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, what),
    H.call(function()
      H.log(string.format("[dancestep] %s: GOGO's commands %02X %02X %02X %02X", what, gogoCmdByte(0),
        gogoCmdByte(1), gogoCmdByte(2), gogoCmdByte(3)))
    end),
  }), function() ph, idx, listLogged = 0, 1, false end)
end

-- ---- the battle's seats -----------------------------------------------------
local mogS, gogoS = nil, nil
local function findSeats()
  mogS, gogoS = nil, nil
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id == MOG then mogS = s end
    if id == GOGO then gogoS = s end
  end
  H.assertEq(mogS ~= nil and gogoS ~= nil, true, "MOG and GOGO are in the battle party")
end

local function cmdRow(s, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local rec = nil            -- the live branch
local recs = {}
local function down(s)
  local hp, st1 = H.readWord(0x3BF4 + s * 2), H.readByte(0x3EE4 + s * 2)
  return hp == 0 or (st1 & 0xC2) ~= 0
end
-- why the branch can no longer resolve, or nil
local function lostWhy()
  if not H.battleLoadStarted() then return "the battle ended" end
  if down(mogS) then return "MOG is down" end
  if down(gogoS) then return "GOGO is down" end
  local present, standing = 0, 0
  for e = 4, 9 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      present = present + 1
      if H.readWord(0x3BF4 + e * 2) > 0 then standing = standing + 1 end
    end
  end
  if present > 0 and standing == 0 then return "the wave was won" end
  return nil
end

-- ---- observers ----------------------------------------------------------------
local function findStumbleArm()
  local base = H.sym("Cmd_13") & 0x3FFFFF
  local pat = { 0xA9, 0x06, 0x8D, 0x01, 0x34 }   -- lda #$06 / sta $3401 ("Stumbled!!")
  for off = 0, 0x7F do
    local hit = true
    for i = 1, #pat do
      if H.readRomByte(base + off + i - 1) ~= pat[i] then hit = false; break end
    end
    if hit then return H.sym("Cmd_13") + off end
  end
  error("Cmd_13's stumble arm (lda #$06 / sta $3401) not found")
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cy() return emu.getState()["cpu.y"] & 0xFF end
  local function cx() return emu.getState()["cpu.x"] & 0xFF end
  local function on(sym, fn)
    emu.addMemoryCallback(function() if rec and not rec.over then fn(rec) end end,
      emu.callbackType.exec, sym, sym)
  end
  local arm = findStumbleArm()
  -- Cmd_13 begins: a start (not yet dancing) or a locked-in step
  on(H.sym("Cmd_13"), function(c)
    local y = cy()
    if y ~= mogS * 2 and y ~= gogoS * 2 then return end
    local s = y // 2
    local be = H.readByte(0xBE)
    local ev = { who = s, f = H.frame, be = be, d = rng(be + 1), bg = H.readByte(0x11E2),
      locked = dancing(s), pend = pend(s), tier = tierOf(s), mp = mpOf(s) }
    c.ev[#c.ev + 1] = ev
    c.cur[s] = ev
  end)
  on(H.sym("Ot6DanceTerrain"), function(c)
    local y = cy()
    local ev = c.cur[y // 2]
    if ev and ev.id == nil then
      ev.id = emu.getState()["cpu.a"] & 0xFF
      ev.tierT = tierOf(y // 2)
    end
  end)
  on(arm, function(c)
    local ev = c.cur[cy() // 2]
    if ev then ev.stumbled = true end
  end)
  on(H.sym("Ot6ActionEnd"), function(c)
    local x = cx()
    for _, s in ipairs({ mogS, gogoS }) do
      if x == s * 2 and c.cur[s] and not c.cur[s].done then
        local ev = c.cur[s]
        ev.done = { f = H.frame, dancing = dancing(s), bg = H.readByte(0x11E2) }
      end
    end
  end)
  H.log(string.format("[dancestep] observers: Cmd_13 $%06X, stumble arm $%06X, Ot6DanceTerrain $%06X, "
    .. "Ot6ActionEnd $%06X", H.sym("Cmd_13"), arm, H.sym("Ot6DanceTerrain"), H.sym("Ot6ActionEnd")))
end

-- ---- the menu policy ------------------------------------------------------------
-- one button for the window on screen, or nil to hold it
local function defend(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  return "b"
end
local function toRow(s, cmd)
  local want = cmdRow(s, cmd)
  assert(want, string.format("seat %d's battle list has command $%02X", s, cmd))
  local cur = H.readByte(CMDROW + s) & 3
  if cur ~= want then return cur < want and "down" or "up" end
  return "a"
end
local function toPend(s, p)
  if pend(s) < p then return "r" end
  if pend(s) > p then return "l" end
  return nil
end
local function toDance(s, id)
  local row, col = id // 2, id % 2
  local cr, cc = H.readByte(0x893B + s), H.readByte(0x8937 + s)
  if cr ~= row then return cr < row and "down" or "up" end
  if cc ~= col then return cc < col and "right" or "left" end
  return "a"
end
-- a dancer's start from his command window: pending p, Dance, the cell of id
local function danceStart(c, s, p, id, mark)
  local st = H.readByte(MSTATE)
  if st == ST_CMD then
    if c[mark] and H.frame - c[mark].f > 120 then c[mark] = nil end   -- a later window: start again
    local b = toPend(s, p)
    if b then return b end
    return toRow(s, CMD_DANCE)
  end
  if st == ST_DANCE then
    local b = toDance(s, id)
    if b == "a" then
      c[mark] = { f = H.frame, pend = pend(s), bank = bank(s), mp = mpOf(s) }
      c.presses = (c.presses or 0) + 1
      if c.presses <= 4 or c.presses % 50 == 0 then
        H.log(string.format("[dancestep] f%d seat %d confirms dance %d (press %d): cursor row %d col %d, "
          .. "pending %d, bank %d, MP %d", H.frame, s, id, c.presses, H.readByte(0x893B + s),
          H.readByte(0x8937 + s), pend(s), bank(s), mpOf(s)))
      end
    end
    return b
  end
  if c[mark] and st == ST_TGT then return "a" end   -- the dance's target window
  if c[mark] then return nil end      -- the confirm is closing the list: let it
  return "b"
end

local function decide(c)
  if not H.battleLoadStarted() or H.readByte(MENU) == 0 then return "a" end   -- pages, victory
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == mogS then
    if c.mogGo then
      if st == ST_CMD and pend(mogS) > 0 then return "l" end
      return defend(st)
    end
    local need = c.t
    if bank(mogS) < need or c.mogDefs < c.extra then
      if st == ST_CMD and pend(mogS) > 0 then return "l" end
      if st == ST_DEF then c.mogDefPending = true end
      return defend(st)
    end
    return danceStart(c, mogS, need, c.x, "mogPress")
  end
  if a == gogoS then
    -- B: GOGO dances once MOG is dancing
    if not (c.mogGo and dancing(mogS)) or dancing(gogoS) then
      if st == ST_CMD and pend(gogoS) > 0 then return "l" end
      return defend(st)
    end
    return danceStart(c, gogoS, 0, c.y, "gogoPress")
  end
  if st == ST_CMD and pend(a) > 0 then return "l" end
  return defend(st)
end

local ph = 0
-- a confirm counts once its seat's command list holds the action (a buzzed or
-- dropped press leaves the list empty and the window open, and is pressed again)
local function queued(s) return H.readByte(0x32CC + s * 2) ~= 0xFF end
local function drive(c)
  if c.mogPress and not c.mogGo and (queued(mogS) or c.cur[mogS]) then
    c.mogGo = c.mogPress
    H.log(string.format("[dancestep] f%d MOG's dance is queued (confirmed f%d)", H.frame, c.mogPress.f))
  end
  ph = ph + 1
  if ph % 8 == 0 then
    local b = decide(c)
    c.btn = b
  end
  if ph % 8 < 4 and c.btn then H.setPad({ [c.btn] = true }) else H.setPad({}) end
end

-- ---- coverage -----------------------------------------------------------------
local function obsOf(r)
  -- MOG's locked-in steps that came in off his dance's terrain, after a
  -- start of his that recorded the branch's tier
  local out = {}
  local start = nil
  for _, ev in ipairs(r.ev) do
    if ev.who == r.mogS then
      if not ev.locked then start = ev
      elseif start and ev.done and bgDance(ev.bg) ~= r.x then
        out[#out + 1] = { ev = ev, t0 = start.pend }
      end
    end
  end
  return out
end

local function tally()
  local t = { [1] = { n = 0, tell = 0 }, [2] = { n = 0, tell = 0 } }
  for _, r in ipairs(recs) do
    for _, o in ipairs(obsOf(r)) do
      local x = t[r.t]
      x.n = x.n + 1
      if telling(r.t, o.ev.d) then x.tell = x.tell + 1 end
    end
  end
  return t
end
local function shortOf(t)
  local s = {}
  for k = 1, 2 do if t[k].n < MIN_B or t[k].tell < 1 then s[#s + 1] = "B" .. k end end
  return s
end
local function needMore() return #shortOf(tally()) > 0 end

-- ---- a branch -------------------------------------------------------------------
local snap, enc, seat, lostRun, encLost = nil, 0, 0, 0, nil
local function branch(bi)
  local req, c
  return H.cond(function() return needMore() and lostRun < LOST_RUN and encLost == nil end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, string.format("battle snapshot load (encounter %d seat %d branch %d)", enc, seat, bi))
      H.rearmInputInjection()
      local short = shortOf(tally())
      local pick = short[(bi - 1) % #short + 1]
      c = { k = #recs + 1, enc = enc, seat = seat, bi = bi, ev = {}, cur = {},
        mogDefs = 0, extra = (bi - 1) % 3, mogS = mogS, gogoS = gogoS, t = tonumber(pick:sub(2)) }
      local mask = H.readByte(DANCES)
      local bgd = bgDance(H.readByte(0x11E2))
      if bgd < 8 and (mask & (1 << bgd)) ~= 0 then c.x = bgd end
      for d = 0, 7 do
        if c.x == nil and (mask & (1 << d)) ~= 0 then c.x = d end
      end
      for d = 0, 7 do
        if c.y == nil and c.x ~= nil and d ~= c.x and (mask & (1 << d)) ~= 0
           and danceBg(d) ~= danceBg(c.x) then c.y = d end
      end
      H.assertEq(c.x ~= nil and c.y ~= nil, true, string.format(
        "MOG knows two dances with different backgrounds (mask %02X)", mask))
      c.wait = (bi - 1) * 7
      recs[#recs + 1] = c
      rec = c
      ph = 0
      H.log(string.format("[dancestep] branch %d (encounter %d seat %d #%d): B(t=%d), %d idle frames, %d extra "
        .. "Defends; bg $%02X (its dance %d); MOG dance %d, GOGO dance %d; MOG bank %d MP %d, GOGO bank %d MP %d",
        c.k, enc, seat, bi, c.t, c.wait, c.extra, H.readByte(0x11E2), bgd, c.x, c.y,
        bank(mogS), mpOf(mogS), bank(gogoS), mpOf(gogoS)))
    end),
    H.lazy(function() return H.waitFrames(c.wait + 1) end),
    H.call(function() c.f0 = H.frame end),
    H.driveUntil(function()
      c.lost = c.lost or lostWhy()
      if not c.lost and H.frame - c.f0 > BRANCH_FRAMES then
        c.lost = string.format("the branch's %d frames ran out", BRANCH_FRAMES)
      end
      -- until MOG's dance ends, or the battle does
      if c.lost then return true end
      if c.mogGo and c.mogStartDone == nil then
        for _, ev in ipairs(c.ev) do
          if ev.who == mogS and not ev.locked and ev.done then c.mogStartDone = ev end
        end
      end
      if c.mogStartDone and not c.mogStartDone.done.dancing then return true end   -- the start stumbled
      if c.mogStartDone then
        local last = c.cur[mogS]
        if last and last.locked and last.stumbled and last.done then return true end  -- a step stumbled
      end
      return false
    end, 40000, {
      H.call(function()
        if c.mogDefPending and H.readByte(MSTATE) ~= ST_DEF then
          c.mogDefPending = false
          c.mogDefs = c.mogDefs + 1
        end
        drive(c)
      end),
      H.waitFrames(1),
    }, "the branch resolves"),
    H.call(function()
      c.over = true
      H.setPad({})
      for _, ev in ipairs(c.ev) do
        H.log(string.format("[dancestep] branch %d %s %s f%d: $be $%02X draw $%02X bg $%02X (dance %d) "
          .. "id %s pend %d tier@cmd %d tier@roll %s MP %d stumbled=%s%s", c.k, ev.who == mogS and "MOG" or "GOGO",
          ev.locked and "step" or "start", ev.f, ev.be, ev.d, ev.bg, bgDance(ev.bg), tostring(ev.id), ev.pend, ev.tier,
          tostring(ev.tierT), ev.mp, tostring(ev.stumbled or false),
          ev.done and string.format(" -> dancing=%s bg $%02X", tostring(ev.done.dancing), ev.done.bg) or ""))
      end
      local obs = obsOf(c)
      if #obs > 0 then lostRun = 0 else lostRun = lostRun + 1 end
      for _, o in ipairs(obs) do
        H.log(string.format("[dancestep] branch %d B(t=%d) OBS MOG step f%d off terrain (bg $%02X): start tier %d, "
          .. "draw $%02X, the rule says %s%s; stumbled=%s", c.k, c.t, o.ev.f, o.ev.bg, o.t0, o.ev.d,
          predicts(o.t0, o.ev.d) and "stumble" or "lands", telling(o.t0, o.ev.d) and " (tells from vanilla)" or "",
          tostring(o.ev.stumbled or false)))
      end
      H.log(string.format("[dancestep] branch %d B(t=%d): %d observation(s)%s", c.k, c.t, #obs,
        c.lost and (", then " .. c.lost) or ""))
      rec = nil
    end),
  }, {})
end

-- ---- the world --------------------------------------------------------------------
local function worldControl(what)
  return H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, what)
end
local W = nil
local function walkIn()
  local wp = 1
  return H.seqStep({
    H.call(function()
      if W then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
      assert(W, "a walkable tile beside the landing")
      H.log(string.format("[dancestep] walking (%d,%d) <-> (%d,%d)", W[1][1], W[1][2], W[2][1], W[2][2]))
    end),
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
local function fightThrough(what)
  local o0, wp = nil, 1
  return H.withReset(H.driveUntil(function() return o0 ~= nil and #H.outcomes > o0 end, 200000, {
    H.call(function() if o0 == nil then o0 = #H.outcomes end end),
    H.worldNavTo(function() return W[wp][1] end, function() return W[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.call(function() wp = wp % 2 + 1 end),
  }, what), function() o0, wp = nil, 1 end)
end

local encs = {}
local function seatOf(e, s)
  local req
  local out = {
    H.cond(function() return s > 1 end, {
      H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(encs[e].blob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "world-map snapshot load (encounter " .. e .. " seat " .. s .. ")")
        H.rearmInputInjection()
      end),
      worldControl("world control (encounter " .. e .. " seat " .. s .. ")"),
    }, {}),
    H.call(function() seat, lostRun, encLost = s, 0, nil end),
    H.waitFrames(s),
    walkIn(),
    H.call(function()
      findSeats()
      H.log(string.format("[dancestep] encounter %d seat %d: formation group $%04X, $be $%02X, bg $%02X; "
        .. "MOG slot %d (L%d, %d MP), GOGO slot %d (L%d, %d MP); known dances $%02X", e, s, H.readWord(0x11E0),
        H.readByte(0xBE), H.readByte(0x11E2), mogS, K.lv(MOG), mpOf(mogS), gogoS, K.lv(GOGO), mpOf(gogoS),
        H.readByte(DANCES)))
    end),
    -- the battle's first command window, whoever's
    H.driveUntil(function()
      encLost = lostWhy()
      return encLost ~= nil or (H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD)
    end, 20000, {
      H.call(function() ph = ph + 1; H.setPad((H.readByte(MENU) == 0 and ph % 8 < 4) and { a = true } or {}) end),
      H.waitFrames(1),
    }, "the first command window"),
    H.cond(function() return encLost == nil end, {
      H.call(function()
        H.assertEq(mpOf(mogS) >= H.boostPrice(8, 2), true, string.format(
          "MOG's pool (%d) pays a two-point Dance start (%d)", mpOf(mogS), H.boostPrice(8, 2)))
        H.setPad({})
        snap = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap, "battle snapshot") end),
    }, {}),
  }
  for bi = 1, MAX_BRANCHES do out[#out + 1] = branch(bi) end
  return H.seqStep(out)
end

local function encounter(e)
  local req
  local out = {
    H.cond(function() return e > 1 end, {
      H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(encs[e - 1].blob) end),
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
      enc = e
      encs[e] = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(encs[e], "world-map snapshot (encounter " .. e .. ")") end),
  }
  for s = 1, SEATS do
    out[#out + 1] = H.cond(function() return needMore() end, { seatOf(e, s) }, {})
  end
  return H.seqStep(out)
end

local body = {
  H.bootCheckpoint("wor-gogo-v1"),
  H.call(function() say("wor", "boot") end),
  regroup({ MOG, GOGO, TERRA, CELES }),
  gogoCommands({ { 1, CMD_DANCE } }, "GOGO: Dance in his second row"),
  liftOff(),
  H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon down by Ebot's Rock", fight = FIGHT }),
  worldControl("world control on the landing"),
  H.call(function()
    say("wor", "landed")
    installObservers()
  end),
}
for i = 1, BURN do
  body[#body + 1] = H.seqStep({
    H.call(function()
      if W then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
    end),
    fightThrough("BURN: the walker fights encounter " .. i),
    worldControl("world control after BURN " .. i),
    H.call(function()
      H.log(string.format("[dancestep] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
        H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    end),
  })
end
for e = 1, MAX_ENCOUNTERS do
  body[#body + 1] = H.cond(function() return needMore() end, { encounter(e) }, {})
end
body[#body + 1] = H.call(function()
  H.setPad({})
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    for _, o in ipairs(obsOf(r)) do
      check(o.t0 == r.t, string.format("branch %d: MOG's start recorded tier %d (want %d)", r.k, o.t0, r.t))
      local want = predicts(r.t, o.ev.d)
      check((o.ev.stumbled or false) == want, string.format(
        "branch %d: MOG's step f%d at tier %d, draw $%02X: stumbled=%s, the start's ladder says %s", r.k, o.ev.f,
        r.t, o.ev.d, tostring(o.ev.stumbled or false), tostring(want)))
      check((o.ev.stumbled or false) == (not o.ev.done.dancing), string.format(
        "branch %d: MOG's step f%d stumbled=%s but dancing=%s after it", r.k, o.ev.f,
        tostring(o.ev.stumbled or false), tostring(o.ev.done.dancing)))
    end
  end
  local t = tally()
  H.log(string.format("[dancestep] SUMMARY B(1) %d observations (%d telling), B(2) %d observations (%d telling); "
    .. "%d branches", t[1].n, t[1].tell, t[2].n, t[2].tell, #recs))
  for _, m in ipairs(fails) do H.log("[dancestep] FAIL " .. m) end
  H.assertEq(#fails, 0, "every locked-in step rolled on its start's ladder")
  local short = shortOf(t)
  H.assertEq(#short, 0, "coverage: " .. (#short > 0 and ("short of " .. table.concat(short, ", ")) or "met"))
  H.log("[dancestep] PASS")
end)

H.run({ maxFrames = 6000000 }, body)

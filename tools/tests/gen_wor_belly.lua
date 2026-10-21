-- gen_wor_belly.lua -- the Gogo arc's first leg (docs/design/route-wor-gogo.md):
-- Continue the `wor-gau-v1` battery (SABIN, GAU, TERRA and CELES beside the
-- Falcon by Duncan's house), the Falcon's cabin (TERRA, CELES, RELM and
-- STRAGO), Triangle Island, where the Zone Eater (world group 32) engulfs a
-- party that lets it (the walker leaves its battle to the engine), the
-- belly's bridge (276: its conductors watched, its jumps pressed) to the
-- door (21,33), and the save point beyond it (279 (24,4)): the
-- `wor-belly-v1` battery, the retry point for the crushing room and GOGO
-- (gen_wor_gogo).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 349, 344, 347
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local SHOP_ITEMS = 74
local function links(doors)
  local out = {}
  for _, d in ipairs(doors) do
    for _, dir in ipairs({ "up", "down", "left", "right" }) do out[#out + 1] = { d[1], d[2], dir, d[3], d[4] } end
  end
  return out
end
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function lv(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(REVIVIFY), H.invCountOf(TENT),
    H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end
local function kitLine(members)
  local t = {}
  for _, ch in ipairs(members) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
-- walk onto (x, y) until the map reads dst (gen_wor_relm's)
local function walkInto(x, y, dst, what, avoid)
  local function there() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.waitUntil(there, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- off a field map's edge onto the world map (gen_wor_locke's outToWorld)
local function outToWorld(dir, what)
  local n = 0
  return H.seqStep({
    H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ dir }) }, what),
    H.release(),
    H.withReset(H.waitUntil(function()
      local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
      n = ok and n + 1 or 0
      return n >= 30
    end, 2400, what .. ": back on the World of Ruin map"), function() n = 0 end),
    H.call(function() say("wor", what) end),
  })
end
-- onto a world door until its field map holds the screen
local function enterFrom(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_locke's)
local function board()
  local n, ph = 0, 0
  local drv = H.fightDriverFor("board", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local battleFrames = 0
  local function offTile()
    return not H.battleLoadStarted() and H.worldSettled() and not H.aboardAirship()
      and (H.worldX() ~= H.readByte(0x1F62) or H.worldY() ~= H.readByte(0x1F63))
  end
  return H.withReset(H.driveUntil(function()
    n = H.airshipControl() and n + 1 or 0
    return n >= 30
  end, 30000, {
    H.cond(offTile, {
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = battleFrames + 1
        if battleFrames >= 3 then drv.frame() end
        return
      end
      if battleFrames > 0 then drv.idle() end
      ph = (ph + 1) % 16
      if H.aboardAirship() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "board the Falcon"), function() n, ph, battleFrames = 0, 0, 0 end)
end
-- the cabin's waiting members (map 12) each ask "Change party members?"
-- (_caf59d); NPC_n is object $10 + n - 1, shown by its switch
-- (gen_wor_locke's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
      if obj == nil and sw(n[3]) == 1 and reach then obj = n end
    end
    return obj
  end
  return H.seqStep({
    board(),
    H.withReset((function()
      local ph = 0
      return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
        H.call(function()
          ph = (ph + 1) % 16
          H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
        end),
      }, "X: to the Falcon's deck (map 11)")
    end)(), function() end),
    walkInto(24, 8, MAP_CABIN, "the deck -> the cabin (map 12)"),
    H.call(function() pickTalker() end),
    H.cond(function() return obj == nil end, {
      H.navTo(23, 44, { maxFrames = 3000, arrive = function() return H.fieldY() < 40 end }),
      H.waitUntil(function() return settled() and H.fieldY() < 40 end, 1200, "up the cabin's stairs", 1),
      H.call(function() pickTalker() end),
    }, {}),
    H.call(function()
      H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
      H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
    end),
    H.lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      local n = 0
      for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("%s is in party 1 after the regroup", NAMES[ch]))
      end
      H.assertEq(n, #members, "party 1 holds exactly the regroup's members")
      say("regroup", "after the menu")
    end),
  })
end
-- lift off from the deck's wheel (_caf532: face left, A held on (15,8))
local function liftOff()
  return H.seqStep({
    H.navTo(15, 8, { maxFrames = 3000 }),
    H.faceAndHoldA("left", function() return H.dialogWaiting() end, 1200, "the Falcon's wheel (11 (15,8)): face left, A"),
    H.release(),
    H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
  })
end
-- the key of every battle (reads only)
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d party %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map(), H.activeParty()))
    end, emu.callbackType.exec, addr, addr)
  end)
end
-- a walk over a map's floor and its doors
local function walk(x, y, what, avoid, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
        fight = FIGHT, avoid = avoid, arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- a chest from whichever side of it the party can reach (gen_wor_ragnarok's)
local function chestAt(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local legs = H.bfsReach(nil, nil, nil, LINKS[map()] or {}, cx + o[1], cy + o[2])
      if legs then
        return H.seqStep({
          walk(cx + o[1], cy + o[2], what .. ": beside it"),
          H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item,
            nav = { fight = FIGHT } }),
        })
      end
    end
    error(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end
-- ---- the Gogo arc's helpers ----
-- Doom Gaze's two cells ($0B00..$0B07: x, y in four-tile cells, world/init.asm @86a6; ctrl.asm @6f1d
-- checks the first two while A is held in the air) and whether it is beaten ($1DD2 bit 0) and its HP
-- ($1DD3, the battle's $3EBE saved)
local function doomLine()
  return string.format("Doom Gaze cells (%d,%d) (%d,%d) [tiles (%d,%d) (%d,%d)]; beaten $1DD2.0=%d; hp $1DD3=%d",
    H.readByte(0x0B00), H.readByte(0x0B02), H.readByte(0x0B04), H.readByte(0x0B06),
    H.readByte(0x0B00) * 4, H.readByte(0x0B02) * 4, H.readByte(0x0B04) * 4, H.readByte(0x0B06) * 4,
    H.readByte(0x1DD2) & 1, H.readWord(0x1DD3))
end
-- pace between the tile the party stands on and a passable neighbour until done(), the world walker
-- playing the battles; spare: species words the walker leaves to the engine (no input)
local function pace(done, budget, what, spare)
  local A, B, n0 = nil, nil, nil
  return H.seqStep({
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      A, B, n0 = { x, y }, nil, #H.outcomes
      for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) then B = { bx, by } end
      end
      H.assertEq(B ~= nil, true, what .. ": a passable tile beside (" .. x .. "," .. y .. ")")
      H.log(string.format("[pace] %s: pacing (%d,%d) <-> (%d,%d)", what, A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function()
      if done() then return true end
      if H.battleLoadStarted() or not H.worldMode() or not H.worldSettled() then return false end
      H.assertEq(#H.outcomes - n0 < budget, true, string.format("%s: done within %d battles", what, budget))
      return false
    end, 900000, {
      H.cond(function() return H.worldMode() and not done() end, {
        H.worldNavTo(function() return B[1] end, function() return B[2] end,
          { maxFrames = 20000, playBattles = "tactical", fight = FIGHT, spare = spare,
            arrive = function() return done() end }),
        H.call(function()
          A, B = B, A
          H.log(string.format("[pace] %s: %d battle(s)", what, #H.outcomes - n0))
        end),
      }, { H.call(function() H.setPad({}) end) }),
    }, what),
  })
end
local function objLine(o0, o1)
  local t = {}
  for o = o0 or 0x10, o1 or 0x14 do t[#t + 1] = string.format("$%02X(%d,%d)", o, H.objX(o), H.objY(o)) end
  return table.concat(t, " ")
end
-- ---- the careful walk: the conductors watched ----
-- The bridge's conductors (276 NPC_1..3: random walkers, collision_on, _cb8251) drop the party down the
-- shaft when one touches it.  Each walks a stretch of one row (CONDSEG, measured: x5_cond.txt), a tile every
-- 16-20 frames, either way at even odds.  A person watches them: from where the party stands, a route to the
-- target is planned around their tiles, and of it only the stretch up to the next tile no conductor can
-- reach (a rest) is weighed: the share of CAREFUL_TRIALS simulated walks of the conductors in which one
-- comes within a tile of where the party stands while it stands there.  At or under CAREFUL_RISK the
-- stretch's first move is made; otherwise other routes are tried (the riskiest tile closed, up to five
-- times), then the party stands (on a rest, or where standing is safe enough), or steps or jumps away.
local CARD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
CAREFUL_PACE, CAREFUL_TRIALS, CAREFUL_RISK, CAREFUL_IMPATIENCE = 18, 120, 0.08, 0.002
local STEP_F, JUMP_F, DOOR_F = 16, 72, 40
local CONDSEG = { [276] = { [30] = { { 32, 40 }, { 45, 48 } }, [32] = { { 31, 34 } } } }
local function condList(objs)
  local out = {}
  for _, o in ipairs(objs) do
    local ox, oy = H.objX(o), H.objY(o)
    if not (ox == 0 and oy == 0) then out[#out + 1] = { ox, oy } end
  end
  return out
end
local function condRange(c)
  for _, sg in ipairs((CONDSEG[map()] or {})[c[2]] or {}) do
    if c[1] >= sg[1] - 1 and c[1] <= sg[2] + 1 then return math.min(sg[1], c[1]), math.max(sg[2], c[1]) end
  end
  return c[1], c[1]
end
local function isRest(k, conds)
  local x, y = k & 0xFF, k >> 8
  for _, c in ipairs(conds) do
    local lo, hi = condRange(c)
    if c[2] == y and x >= lo - 1 and x <= hi + 1 then return false end
  end
  return true
end
-- the route to (tx, ty) as moves { kind = "step"|"jump"|"door", dir, link, from, to } (keys (y<<8)|x)
-- around the closed tiles
local function planRoute(tx, ty, lk, closed)
  local sx, sy = H.fieldX(), H.fieldY()
  local byTile, door = {}, {}
  for _, L in ipairs(lk) do
    if L[6] == nil or L[6]() then
      local k = (L[2] << 8) | L[1]
      if L[7] then
        byTile[k] = byTile[k] or {}
        byTile[k][#byTile[k] + 1] = L
      else
        door[k] = (L[5] << 8) | L[4]
      end
    end
  end
  local start, goal = (sy << 8) | sx, (ty << 8) | tx
  local parent, q, qi = { [start] = false }, { start }, 1
  while qi <= #q and qi <= 8000 do
    local k = q[qi]; qi = qi + 1
    if k == goal then
      local out = {}
      while parent[k] do table.insert(out, 1, parent[k].mv); k = parent[k].from end
      return out
    end
    local x, y = k & 0xFF, k >> 8
    local function visit(nk, mv)
      if mv.kind == "step" and door[nk] and nk ~= goal then mv.kind = "door"; nk = door[nk] end
      if parent[nk] == nil and not closed[nk] then
        mv.from, mv.to = k, nk
        parent[nk] = { from = k, mv = mv }
        q[#q + 1] = nk
      end
    end
    for _, L in ipairs(byTile[k] or {}) do visit((L[5] << 8) | L[4], { kind = "jump", link = L, dir = L[3] }) end
    for dir, d in pairs(CARD) do
      if H.canStep(x, y, dir) then visit(((y + d[2]) << 8) | (x + d[1]), { kind = "step", dir = dir }) end
    end
  end
  return nil
end
-- the moves up to and including the first that ends on a rest (or the whole route)
local function toRest(route, conds)
  local out = {}
  for _, m in ipairs(route) do
    out[#out + 1] = m
    if m.kind == "door" or isRest(m.to, conds) then break end
  end
  return out
end
-- where the party stands, over time, along moves: { x, y, from, until }
local function spansOf(moves)
  local spans, t = {}, 0
  for _, m in ipairs(moves) do
    local d = m.kind == "step" and STEP_F or m.kind == "jump" and JUMP_F or DOOR_F
    spans[#spans + 1] = { m.from & 0xFF, m.from >> 8, t, t + d }
    spans[#spans + 1] = { m.to & 0xFF, m.to >> 8, t + d, t + d + STEP_F }
    t = t + d
  end
  return spans, t + STEP_F
end
local seed = 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local function simRisk(spans, tEnd, conds)
  local live = {}
  for _, c in ipairs(conds) do
    for _, sp in ipairs(spans) do
      if sp[2] == c[2] then live[#live + 1] = c; break end
    end
  end
  if #live == 0 then return 0, nil end
  seed = (H.frame * 7919 + 17) % 2147483648
  local hits, worst = 0, {}
  for _ = 1, CAREFUL_TRIALS do
    local hit = false
    for _, c in ipairs(live) do
      local lo, hi = condRange(c)
      local x, tt = c[1], -math.floor(rnd() * CAREFUL_PACE)
      local function check(at)
        for _, sp in ipairs(spans) do
          if sp[2] == c[2] and at >= sp[3] and at < sp[4] and math.abs(x - sp[1]) <= 1 then
            local k = (sp[2] << 8) | sp[1]
            worst[k] = (worst[k] or 0) + 1
            return true
          end
        end
        return false
      end
      hit = check(0)
      while not hit and tt < tEnd do
        tt = tt + CAREFUL_PACE
        local nx = x + (rnd() < 0.5 and -1 or 1)
        if nx >= lo and nx <= hi then x = nx end
        hit = check(math.max(tt, 0))
      end
      if hit then break end
    end
    if hit then hits = hits + 1 end
  end
  local wk, wn = nil, 0
  for k, n in pairs(worst) do if n > wn then wk, wn = k, n end end
  return hits / CAREFUL_TRIALS, wk
end
-- wait for control, fighting a battle that opens meanwhile (one the last step's arrival left loading)
local function waitControl(what)
  local drv = H.fightDriverFor("careful", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local bn = 0
  return H.withReset(H.driveUntil(function()
    return not H.battleLoadStarted() and H.hasControl() and H.tileAligned()
  end, 60000, {
    H.call(function()
      bn = H.battleLoadStarted() and bn + 1 or 0
      if bn >= 3 then drv.frame(); return end
      if bn == 0 then drv.idle() end
      H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {})
    end),
  }, what .. ": control"), function() bn = 0 end)
end
-- a jump from the tile the party stands on: face its way with A pulsed until it lands (on the landing at
-- rest with control) or 600 frames pass without it (logged; the walk plans again from wherever it is)
local function jumpStep(L, what, abort)
  local n, ctl, f0, drv, bn = 0, 0, nil, nil, 0
  drv = H.fightDriverFor("careful jump", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  return H.withReset(H.driveUntil(function()
    f0 = f0 or H.frame
    if abort() then return true end
    -- landed: at rest on the landing with control seen (a landing that is itself a jump's tile re-runs its
    -- script under the party, control one frame in four)
    if H.fieldX() == L[4] and H.fieldY() == L[5] and H.tileAligned() and not H.battleLoadStarted() then
      n = n + 1
      if H.hasControl() then ctl = ctl + 1 end
    else
      n, ctl = 0, 0
    end
    if n >= 6 and ctl >= 1 then return true end
    if H.frame - f0 > 600 and not H.battleLoadStarted() then
      H.log(string.format("[careful] %s: the jump %s from (%d,%d) did not land in 600 frames: at (%d,%d) ctl=%s "
        .. "algn=%s ev=%s dlg=%s facing %d", what, L[3], L[1], L[2], H.fieldX(), H.fieldY(), tostring(H.hasControl()),
        tostring(H.tileAligned()), tostring(H.eventRunning()), tostring(H.dialogWaiting()), H.readByte(0x0743)))
      return true
    end
    return false
  end, 100000, {
    H.call(function()
      bn = H.battleLoadStarted() and bn + 1 or 0
      if bn >= 3 then drv.frame(); return end
      if bn == 0 then drv.idle() end
      local on = H.fieldX() == L[1] and H.fieldY() == L[2] and H.tileAligned() and not H.dialogWaiting()
      local pad = {}
      if on then pad[L[3]] = true; if H.frame % 8 < 4 then pad.a = true end end
      H.setPad(pad)
    end),
  }, what .. ": a jump"), function() n, ctl, f0, bn = 0, 0, nil, 0 end)
end
local function doMove(mv, what, abort)
  if mv.kind == "jump" then return jumpStep(mv.link, what, abort) end
  local d = CARD[mv.dir]
  local x0, y0 = H.fieldX(), H.fieldY()
  local nx, ny = x0 + d[1], y0 + d[2]
  local m0 = map()
  -- a door carries the party far: arriving anywhere two or more tiles off is arriving
  return H.navTo(nx, ny, { maxFrames = 600, playBattles = "tactical", fight = FIGHT,
    arrive = function()
      return abort() or (H.fieldX() == nx and H.fieldY() == ny) or map() ~= m0
        or math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) >= 2
    end })
end
local function carefulWalk(tx, ty, lk, objs, what, budget, abort)
  local moves, waits, lastWhy, stood = 0, 0, nil, 0
  local function there() return H.fieldX() == tx and H.fieldY() == ty and H.tileAligned() end
  local function oneMove()
    local conds = condList(objs)
    local here = (H.fieldY() << 8) | H.fieldX()
    local closed = {}
    for _, c in ipairs(conds) do for dx = -1, 1 do closed[(c[2] << 8) | (c[1] + dx)] = true end end
    local best, bestR, tried = nil, 2, 0
    for _ = 1, 6 do
      local route = planRoute(tx, ty, lk, closed)
      if not route or #route == 0 then break end
      tried = tried + 1
      local pre = toRest(route, conds)
      local sp, te = spansOf(pre)
      local r, wk = simRisk(sp, te, conds)
      if r < bestR then best, bestR = pre, r end
      if r <= CAREFUL_RISK or wk == nil or wk == here then break end
      closed[wk] = true
    end
    local mv = nil
    -- patience runs out: the risk a person takes grows with the frames stood on a rest (four a wait)
    local thr = CAREFUL_RISK + stood * CAREFUL_IMPATIENCE
    -- off a rest, the stretch already begun is finished: standing on a conductor's row is the risk
    local onRest = isRest(here, conds)
    if not onRest then thr = math.max(thr, 0.9) end
    if best and bestR <= thr then
      if bestR > CAREFUL_RISK then
        H.log(string.format("[careful] %s: f%d after %d frames' wait, a stretch at risk %.2f from (%d,%d)", what,
          H.frame, stood * 4, bestR, H.fieldX(), H.fieldY()))
      end
      mv = best[1]
    else
      -- standing here: is it safe enough for a while?
      local sp = { { H.fieldX(), H.fieldY(), 0, 64 } }
      local rs = isRest(here, conds) and 0 or simRisk(sp, 64, conds)
      if rs > CAREFUL_RISK then
        -- a conductor closing in: the move whose stretch to a rest runs the least risk, if less than standing
        local cand = {}
        for dir, d in pairs(CARD) do
          if H.canStep(H.fieldX(), H.fieldY(), dir) then
            cand[#cand + 1] = { kind = "step", dir = dir, from = here,
              to = ((H.fieldY() + d[2]) << 8) | (H.fieldX() + d[1]) }
          end
        end
        for _, L in ipairs(lk) do
          if L[7] and ((L[2] << 8) | L[1]) == here then
            cand[#cand + 1] = { kind = "jump", link = L, dir = L[3], from = here, to = (L[5] << 8) | L[4] }
          end
        end
        local fb, fr = nil, rs
        for _, c in ipairs(cand) do
          if not closed[c.to] or c.kind == "jump" then
            local s2, t2 = spansOf({ c })
            local r2 = simRisk(s2, t2, conds)
            if r2 < fr then fb, fr = c, r2 end
          end
        end
        if fb then
          mv = fb
          H.log(string.format("[careful] %s: f%d out of a conductor's way from (%d,%d) (standing %.2f, %s %.2f)",
            what, H.frame, H.fieldX(), H.fieldY(), rs, fb.kind .. " " .. tostring(fb.dir), fr))
        end
      end
      if mv == nil then
        local why = best and string.format("best of %d route(s) at risk %.2f (%s %s first)", tried, bestR,
          best[1].kind, tostring(best[1].dir)) or "no route"
        if why ~= lastWhy then
          H.log(string.format("[careful] %s: f%d waiting at (%d,%d): %s; %s", what, H.frame, H.fieldX(), H.fieldY(),
            why, objLine()))
        end
        lastWhy = why
      end
    end
    if mv == nil then
      waits = waits + 1
      stood = stood + 1
      return H.waitFrames(4)
    end
    moves = moves + 1
    if mv.kind == "jump" then stood = 0 end
    lastWhy = nil
    if mv.kind == "jump" then
      H.log(string.format("[careful] f%d jump %s from (%d,%d) (risk %.2f); %s", H.frame, mv.link[3], H.fieldX(),
        H.fieldY(), bestR, objLine()))
    end
    return doMove(mv, what, abort)
  end
  local nOut = #H.outcomes
  return H.seqStep({
    H.repeatN(budget or 3000, {
      H.cond(function() return not there() and not abort() end, {
        waitControl(what),
        -- a battle fought on the way: the field care a walk gives after one (the menu stops the field)
        H.cond(function() return #H.outcomes ~= nOut end, {
          H.call(function() nOut = #H.outcomes end),
          H.fieldCare({ tag = "care after battle (careful)" }),
        }, {}),
        H.cond(function() return not abort() end, { H.lazy(oneMove) }, {}),
      }, {}),
    }),
    H.call(function()
      H.log(string.format("[careful] %s: %s after %d moves and %d waits", what, there() and "there" or "stopped",
        moves, waits))
    end),
  })
end
-- ---- the belly's bridge (276) ----
-- route_data map 276: its same-map doors, and its jump triggers (_cb7e4c up, _cb7e63 down, _cb7ea8 either,
-- _cb7e7a left, _cb7e91 right: facing the way with A held, the party jumps two tiles; jumps.py)
local DOORS276 = { { 6, 20, 60, 26 }, { 60, 25, 6, 19 }, { 59, 33, 52, 14 }, { 52, 13, 59, 32 } }
local function jumps(list, dir, n)
  local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[dir]
  local out = {}
  for _, t in ipairs(list) do out[#out + 1] = { t[1], t[2], dir, t[1] + d[1] * n, t[2] + d[2] * n, nil, true } end
  return out
end
local function cat(...)
  local out = {}
  for _, l in ipairs({ ... }) do for _, v in ipairs(l) do out[#out + 1] = v end end
  return out
end
local J276_UP = { { 48, 32 }, { 49, 32 }, { 47, 30 }, { 46, 30 }, { 44, 32 }, { 45, 32 }, { 41, 32 }, { 40, 32 },
  { 39, 32 }, { 38, 32 }, { 37, 32 }, { 34, 32 }, { 33, 32 }, { 32, 32 }, { 31, 32 } }
local J276_DOWN = { { 44, 28 }, { 45, 28 }, { 46, 28 }, { 47, 28 }, { 48, 28 }, { 49, 28 }, { 40, 28 }, { 41, 28 },
  { 39, 30 }, { 38, 30 }, { 37, 30 }, { 31, 28 }, { 32, 28 }, { 33, 28 }, { 34, 28 } }
local J276_BOTH = { { 49, 30 }, { 48, 30 }, { 45, 30 }, { 44, 30 }, { 40, 30 }, { 41, 30 }, { 34, 30 }, { 33, 30 },
  { 32, 30 }, { 31, 30 } }
local LINKS276 = cat(links(DOORS276), jumps(J276_UP, "up", 2), jumps(J276_DOWN, "down", 2), jumps(J276_BOTH, "up", 2),
  jumps(J276_BOTH, "down", 2), jumps({ { 29, 32 } }, "left", 2), jumps({ { 27, 32 } }, "right", 2))
-- a conductor's touch (_cb8251) drops the party down the shaft at x 37 and sets it on (37,17): counted on
-- the edge of the party's entering that column
local falls, inShaft = 0, false
local function fallCount()
  local s = map() == 276 and H.fieldX() == 37 and H.fieldY() >= 9 and H.fieldY() <= 17
  if s and not inShaft then
    falls = falls + 1
    H.log(string.format("[jwalk] f%d dropped down the shaft (%d); %s", H.frame, falls, objLine()))
  end
  inShaft = s
  return falls
end
-- the careful walk to (x, y) on the bridge, again from wherever the party stands while it is not there (a
-- conductor's touch drops it to the shaft's foot, where the plate (46,17) opens the way back: _cb8062,
-- $01F0 for this load of the map), at most `tries` times; done() ends it early
local function jwalk(x, y, lk, what, tries, done)
  local n = 0
  local function there() return (done and done()) or (H.fieldX() == x and H.fieldY() == y and H.tileAligned()) end
  return H.seqStep({
    H.repeatN(tries or 6, {
      H.cond(function() return not there() end, {
        H.call(function()
          n = n + 1
          H.log(string.format("[jwalk] %s: try %d from map %d (%d,%d)", what, n, map(), H.fieldX(), H.fieldY()))
        end),
        waitControl(what),
        H.cond(function()
          return not there() and map() == 276 and sw(0x01F0) == 0 and H.bfsReach(nil, nil, nil, {}, 46, 17) ~= nil
        end, {
          H.navTo(46, 17, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
          H.waitUntil(function() return sw(0x01F0) == 1 and H.hasControl() and H.tileAligned() end, 600,
            "276: the plate (46,17) opens the way", 1),
          H.call(function() say("route", "276: the plate (46,17)") end),
        }, {}),
        H.cond(function() return not there() end, {
          H.lazy(function()
            local f0 = fallCount()
            return carefulWalk(x, y, lk, { 0x10, 0x11, 0x12, 0x13, 0x14 }, what, 3000,
              function() return fallCount() > f0 end)
          end),
        }, {}),
      }, {}),
    }),
    H.call(function()
      H.assertEq(there(), true, string.format("%s: at (%d,%d) on map %d within %d tries", what, x, y, map(), tries or 6))
      H.log(string.format("[jwalk] %s: there after %d tries, %d drop(s) down the shaft", what, n, falls))
      say("route", what)
    end),
  })
end
-- Triangle Island: the Falcon down on (237,52), a landable tile of world group 32 (the Zone Eater, every
-- slot: route_data pool group 32)
local ISLAND = { 237, 52 }
local ZONE_EATER = 0x171
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-gau-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ SABIN, GAU, TERRA, CELES }))
  end),
  -- @@setup-end

  -- ---- 1. the cabin, Triangle Island: the Zone Eater ------------------------------------------
  -- @@stage island
  -- the four highest for the belly (L43-44 bodies: route-wor-gogo.md section 2); GOGO, met at its end,
  -- waits in the cabin for a party of four
  regroup({ TERRA, CELES, RELM, STRAGO }),
  H.gearDress({ tag = "gear for the four" }),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } },
    { tag = "relics for the four" }),
  H.call(function() H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO })) end),
  liftOff(),
  H.call(function() H.log("[doom] aloft: " .. doomLine()) end),
  H.flyTo(ISLAND[1], ISLAND[2], { what = "the Falcon down on Triangle Island", fight = FIGHT }),
  H.call(function() say("wor", "on Triangle Island") end),
  -- the island's battles are the Zone Eater's, and a party that lets its Engulf take every member is
  -- carried inside (battle_main.asm @4807: $3EBC bit 7; world_start.asm @042b, VehicleEvent_05)
  pace(function() return not H.worldMode() end, 12, "the island until the Zone Eater engulfs the party",
    { ZONE_EATER }),
  H.waitUntil(function() return map() == 276 and H.hasControl() and settled() end, 6000, "control in the belly", 5),
  H.call(function() say("story", "engulfed: the belly (276)") end),
  H.saveState("wor_belly_in.mss"),

  -- ---- 2. the bridge -----------------------------------------------------------------------------------
  -- @@stage bridge
  -- the landing (10,12), the door (6,20) to the bridge's east end (60,26), the bridge's rows and their
  -- jumps, the conductors watched (careful walk), and the door (21,33) to the save point's room (279);
  -- a conductor's touch drops the party to the shaft's foot, and the plate (46,17) opens the way back
  jwalk(21, 32, LINKS276, "276: across the bridge to the door (21,33)", 30),
  walkInto(21, 33, 279, "276 (21,33) -> 279"),

  -- ---- 3. the save point -------------------------------------------------------------------------------
  -- @@stage save
  H.fieldCare({ threshold = 1.0, tag = "at the belly's save point" }),
  H.call(function()
    say("wor", "at the save point")
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO }))
  end),
  H.saveAtCheckpoint("wor-belly-v1"),
  H.saveState("wor_belly.mss"),
  H.logStep(function()
    return string.format("wor_belly generated: TERRA L%d, CELES L%d, RELM L%d and STRAGO L%d on the belly's save "
      .. "point, map 279 (%d,%d), saved in slot 3", lv(TERRA), lv(CELES), lv(RELM), lv(STRAGO), H.fieldX(), H.fieldY())
  end),
})

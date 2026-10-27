-- gen_wor_gogo.lua -- the Gogo arc's second leg (docs/design/route-wor-gogo.md):
-- Continue the `wor-belly-v1` battery (TERRA, CELES, RELM and STRAGO on the
-- Zone Eater's belly's save point), the crushing room (280: its ceiling
-- drops on a clock, and the party crosses it from one safe tile to the
-- next), the passage (277) to the room's west half and its jumps, GOGO
-- (278 (8,5), _cb81c6: his name, $00D4; he waits in the cabin for a party
-- of four), a Warp Stone out to Triangle Island, the cabin (STRAGO, RELM,
-- GOGO and TERRA), GOGO's commands (Mimic, Lore, Tools, Item), Thamasa:
-- its item counter and the scene STRAGO and RELM bring to Gungho's door
-- (_cb75bf: $019A, which opens Ebot's Rock), and the save beside the Falcon
-- there: the `wor-gogo-v1` battery, the next leg's boot.
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
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, walkInto, regroup, liftOff = K.say, K.kitLine, K.walkInto, K.regroup, K.liftOff
local watches = K.watches

-- navJ (build/attempts/wt/v034-wor-gogo/lab/mknavj.py): H.navLinks with a link's 7th field pressing A beside its direction
local function navJ(tx, ty, links, opts)
  opts = opts or {}
  local what = opts.what or string.format("to (%d,%d) by the links", tx, ty)
  local tries = 0
  local build
  build = function()
    local legs = nil
    for _, z in ipairs({ false, 1, 2, 0, 3 }) do
      legs = H.bfsReach(nil, nil, z or nil, links, tx, ty, opts.avoid)
      if legs then break end
    end
    if not legs then
      -- a wandering NPC can stand in the only corridor for a while (navTo's
      -- own patience): idle 45 frames and plan again, opts.noPathRetries times
      tries = tries + 1
      if tries > (opts.noPathRetries or 20) then
        error(string.format("navLinks: no route (%d,%d)->(%d,%d) over the floor and %d link(s) [%d retries]",
          H.fieldX(), H.fieldY(), tx, ty, #(links or {}), tries - 1), 0)
      end
      H.log(string.format("[links] %s: no route (%d,%d)->(%d,%d); waiting (retry %d)", what, H.fieldX(), H.fieldY(),
        tx, ty, tries))
      return H.seqStep({ H.waitFrames(45), H.lazy(build) })
    end
    -- a walk leg's own plan must not step onto a link's tile (it would
    -- take the link where the plan meant to walk)
    local wopts = {}
    for k, v in pairs(opts) do wopts[k] = v end
    -- opts.abort(): the plan is stale (a conductor dropped the party): every leg ends at once
    local ab = opts.abort or function() return false end
    wopts.arrive = function() return (opts.arrive and opts.arrive()) or ab() end
    wopts.avoid = {}
    for _, t in ipairs(opts.avoid or {}) do wopts.avoid[#wopts.avoid + 1] = t end
    for _, L in ipairs(links or {}) do
      if (L[6] == nil or L[6]()) and not L[7] then wopts.avoid[#wopts.avoid + 1] = { L[1], L[2] } end
    end
    local desc, steps = {}, {}
    for i, l in ipairs(legs) do
      if l.walk then
        desc[#desc + 1] = string.format("walk (%d,%d)", l.walk[1], l.walk[2])
        -- a walk that ends on the next link's own tile (a door the party
        -- can only reach by a diagonal step, so no press is made onto it:
        -- Strago's house's (60,21)) is carried as it arrives; landing is
        -- arriving
        local nx = legs[i + 1] and legs[i + 1].link
        if nx and nx[1] == l.walk[1] and nx[2] == l.walk[2] then
          local fo = {}
          for k, v in pairs(wopts) do fo[k] = v end
          fo.arrive = function() return (H.fieldX() == nx[4] and H.fieldY() == nx[5]) or ab() end
          steps[#steps + 1] = H.navTo(l.walk[1], l.walk[2], fo)
        else
          steps[#steps + 1] = H.navTo(l.walk[1], l.walk[2], wopts)
        end
      else
        local L, F = l.link, l.from
        desc[#desc + 1] = string.format("%s from (%d,%d) by (%d,%d) -> (%d,%d)", L[3], F[1], F[2], L[1], L[2],
          L[4], L[5])
        -- to the tile the press is made from: the link's own tile (stood
        -- on, the press turns the party and the script reads the facing)
        -- or the one before it (the step onto it is the press); arriving
        -- carried already is arriving
        local fo = {}
        for k, v in pairs(wopts) do fo[k] = v end
        fo.arrive = function() return (H.fieldX() == L[4] and H.fieldY() == L[5]) or ab() end
        steps[#steps + 1] = H.navTo(F[1], F[2], fo)
        -- landed: on the landing tile at rest for 16 frames with control
        -- read on two of them (a landing that is itself a link's tile, the
        -- way back, re-runs its script under the party: control one frame
        -- in four)
        local n, ctl, bn = 0, 0, 0
        local drv = H.fightDriverFor("navLinks", { tactical = true, boost = true, items = true, healPercent = 55 },
          opts.fight)
        steps[#steps + 1] = H.withReset(H.driveUntil(function()
          if ab() then return true end
          if H.fieldX() == L[4] and H.fieldY() == L[5] and H.tileAligned() and not H.battleLoadStarted() then
            n = n + 1
            if H.hasControl() then ctl = ctl + 1 end
          else
            n, ctl = 0, 0
          end
          return n >= 16 and ctl >= 2
        end, 2400, {
          H.call(function()
            -- a battle under the jump is fought as the walks fight theirs
            bn = H.battleLoadStarted() and bn + 1 or 0
            if bn >= 3 then drv.frame(); return end
            if bn == 0 then drv.idle() end
            -- held while the party rests on the press's tile: a link's own
            -- tile has control one frame in four, and the field reads the
            -- pad on those
            local onStart = ((H.fieldX() == F[1] and H.fieldY() == F[2]) or (L[7] and H.fieldX() == L[1]
              and H.fieldY() == L[2])) and H.tileAligned()
              and not H.dialogWaiting()
            local pad = {}
            if onStart and (not opts.safe or opts.safe(L)) then pad[L[3]] = true; if L[7] and (H.frame % 8) < 4 then pad.a = true end end
            H.setPad(pad)
          end),
        }, string.format("%s: the link %s onto (%d,%d) lands on (%d,%d)", what, L[3], L[1], L[2], L[4], L[5])),
        function() n, ctl, bn = 0, 0, 0 end)
      end
    end
    H.log(string.format("[links] %s from (%d,%d): %s", what, H.fieldX(), H.fieldY(), table.concat(desc, "; ")))
    return H.seqStep(steps)
  end
  return H.withReset(H.lazy(function() return build() end), function() tries = 0 end)
end
-- ---- the crushing room (280): hop between the safe tiles on the clock ----
-- Entering 280 starts the ceiling (_cb80b8 -> _cb812c: timer 0, 256 frames); at zero it drops (_cb8149) and
-- the party survives standing on a safe tile ($01B5: _cb81a2's tiles; $01BF: _cb81ab's; the engine clears
-- both as the party steps off) or outside the room (the corridors below row 48/49: _cb81b4/_cb81bd), else
-- GameOver; then the timer runs again (x6, x7: build/attempts/wt/v034-wor-gogo/lab).  A person watches the clock and walks from
-- one safe tile to the next that the time left reaches.
local CRUSH_SAFE = { { 30, 42 }, { 35, 46 }, { 41, 44 }, { 46, 48 }, { 46, 49 }, { 47, 48 }, { 47, 49 }, { 50, 43 },
  { 49, 43 }, { 54, 45 }, { 54, 46 }, { 35, 47 }, { 30, 43 }, { 50, 44 },
  -- the corridors' first tiles out of the room
  { 26, 50 }, { 25, 50 }, { 27, 50 }, { 54, 49 }, { 53, 49 }, { 55, 49 } }
local CRUSH_STEP, CRUSH_MARGIN = 16, 40
local function crushOutside(x, y)
  return (x >= 25 and x <= 27 and y >= 50) or (x >= 53 and x <= 55 and y >= 49) or y >= 54 or x < 24
end
local function crushTimer() return H.readByte(0x1189) | (H.readByte(0x118A) << 8) end
-- the room's chests (#486), each opened from `stand` facing it; `back` is the steps from the stand to the nearest
-- safe tile (0 where the stand is one: the Zephyr Cape's and the Hero Ring's).  A chest is taken when the time
-- left covers the walk to its stand, the opening (CRUSH_OPEN frames) and the walk back to safety
local CRUSH_CHESTS = {
  { stand = { 46, 48 }, face = "up", bit = 232, what = "Zephyr Cape", item = 0xC0, back = 0 },
  { stand = { 41, 44 }, face = "up", bit = 233, what = "Hero Ring", item = 0xC9, back = 0 },
  { stand = { 28, 44 }, face = "left", bit = 234, what = "Tack Star", item = 0x43, back = 3 },
}
local CRUSH_OPEN = 80
-- a chest on the clock: face it, A until its bit is set, and A again on the "Received!" window until it has
-- shown and closed (or 120 frames pass with none): H.openChest lingers 90 frames after the window, which the
-- clock cannot spare beside the Tack Star (lab gg1, "the Hero Ring opened ... (132 frames ...)"); the room's
-- clock event holds control most frames, so control is not waited for (gg2); the window can open 30 frames or
-- more after the bit (gg3)
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function quickChest(o)
  local ph, calm, before, seen = 0, 0, nil, false
  return H.withReset(H.seqStep({
    H.call(function() before = H.invCountOf(o.item) end),
    H.driveUntil(function() return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[o.face] end, 300,
      { H.call(function() H.setPad({ [o.face] = true }) end) }, o.what .. ": faced " .. o.face),
    H.release(),
    H.driveUntil(function()
      if H.dialogWaiting() then seen = true end
      if H.chestOpen(o.bit) and not H.dialogWaiting() then calm = calm + 1 else calm = 0 end
      return (seen and calm >= 8) or calm >= 120
    end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad((ph < 4 and (not H.chestOpen(o.bit) or H.dialogWaiting())) and { a = true } or {})
      end),
    }, o.what .. ": the chest opened and its window closed"),
    H.release(),
    H.call(function()
      H.assertEq(H.chestOpen(o.bit), true, o.what .. ": treasure bit " .. o.bit .. " set")
      H.assertEq(H.invCountOf(o.item), before + 1, string.format("%s: bag %d -> %d of item $%02X", o.what, before,
        H.invCountOf(o.item), o.item))
      H.log(string.format("[chest] chest bit %d (%s): OPENED", o.bit, o.what))
    end),
  }), function() ph, calm, before, seen = 0, 0, nil, false end)
end
local THUNDER_SHLD = { stand = { 1, 46 }, face = "up", bit = 228, what = "Thunder Shld", item = 0x62 }
-- GOGO's room's pool (field group 171, map 278): Ogor x2 (346), Covert and Ogor (347), Wart Puck x2 (348) at
-- 80/256 each and Tap Dancer with Woolly (351) at 16/256; no other map deals it.  The party walks a lap by the
-- door until each is won, within the pick's worst run (110 for 16/256: gen_wor_belly's hunt, gaps.py)
local BELLY171 = { [346] = "Ogor x2", [347] = "Covert, Ogor", [348] = "Wart Puck x2", [351] = "Tap Dancer, Woolly" }
local HUNT_BUDGET = 111
local HUNT278_LAP = { { 8, 12 }, { 8, 11 } }
local function crushWalk(tx, ty, what, chests)
  local hops = 0
  chests = chests or {}
  local function there() return H.fieldX() == tx and H.fieldY() == ty and H.tileAligned() end
  local function oneHop()
    local t = crushTimer()
    local x, y = H.fieldX(), H.fieldY()
    local function steps(gx, gy)
      if gx == x and gy == y then return 0 end
      local p = H.bfsPath(gx, gy)
      return p and #p or nil
    end
    -- the next chest the walk has not opened: taken when the time left covers it, else the hops aim at it
    local goal = nil
    for _, ch in ipairs(chests) do
      if not H.chestOpen(ch.bit) then goal = ch; break end
    end
    if goal then
      local d1 = steps(goal.stand[1], goal.stand[2])
      local cost = d1 and (CRUSH_STEP * (d1 + goal.back) + CRUSH_OPEN)
      if cost and t - CRUSH_MARGIN >= cost then
        hops = hops + 1
        local t0, f0 = t, H.frame
        H.log(string.format("[crush] %s: f%d t=%d to the %s's stand (%d,%d), %d steps, %d back (cost %d)", what,
          H.frame, t, goal.what, goal.stand[1], goal.stand[2], d1, goal.back, cost))
        return H.seqStep({
          H.navTo(goal.stand[1], goal.stand[2], { maxFrames = 1200 }),
          quickChest(goal),
          H.call(function()
            H.log(string.format("[crush] %s: the %s opened at f%d t=%d (%d frames, the clock %d -> %d)", what,
              goal.what, H.frame, crushTimer(), H.frame - f0, t0, crushTimer()))
          end),
        })
      end
    end
    -- the hops aim at the chest's stand while one is left (a chest's stand is gone to only by the test above)
    local ax, ay = tx, ty
    if goal then ax, ay = goal.stand[1], goal.stand[2] end
    local budget = math.floor((t - CRUSH_MARGIN) / CRUSH_STEP)
    -- the target itself, if it is outside the room or the time left reaches it
    local dt = steps(tx, ty)
    if not goal and dt and (dt <= budget or crushOutside(tx, ty) and dt <= budget) then
      hops = hops + 1
      H.log(string.format("[crush] %s: f%d t=%d to the target (%d,%d), %d steps", what, H.frame, t, tx, ty, dt))
      return H.navTo(tx, ty, { maxFrames = 1200 })
    end
    -- else the safe tile nearest the target (or the chest's stand) that the time left reaches
    -- (any safe tile in reach is a candidate: off a safe tile, as after the Tack Star, the nearest to the target
    -- may lie farther from it than the party stands; lab gg5, "no safe tile in reach (budget 5 steps; ... (30,43)
    -- 3 ...)")
    local best, bestD = nil, 999
    local hereSafe = false
    for _, s in ipairs(CRUSH_SAFE) do if s[1] == x and s[2] == y then hereSafe = true end end
    if crushOutside(x, y) then hereSafe = true end
    for _, s in ipairs(CRUSH_SAFE) do
      local ds = steps(s[1], s[2])
      if ds and ds <= budget and ds > 0 then
        -- how far the safe tile leaves the party from the target
        local rest = math.abs(s[1] - ax) + math.abs(s[2] - ay)
        if rest < bestD then best, bestD = s, rest end
      end
    end
    local hereRest = math.abs(x - ax) + math.abs(y - ay)
    if best and (bestD < hereRest or not hereSafe) then
      hops = hops + 1
      H.log(string.format("[crush] %s: f%d t=%d hop to (%d,%d)", what, H.frame, t, best[1], best[2]))
      return H.navTo(best[1], best[2], { maxFrames = 1200 })
    end
    if not hereSafe then
      local near = {}
      for _, s in ipairs(CRUSH_SAFE) do
        if math.abs(s[1] - x) + math.abs(s[2] - y) <= 8 then
          near[#near + 1] = string.format("(%d,%d) %s", s[1], s[2], tostring(steps(s[1], s[2])))
        end
      end
      error(string.format("[crush] %s: f%d t=%d at (%d,%d) z=%d with no safe tile in reach (budget %d steps; %s)",
        what, H.frame, t, x, y, H.readByte(0x00b2) & 3, budget, table.concat(near, ", ")), 0)
    end
    return H.waitFrames(8)
  end
  return H.seqStep({
    H.repeatN(400, {
      H.cond(function() return not there() end, {
        H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, what .. ": control", 1),
        H.lazy(oneHop),
      }, {}),
    }),
    H.call(function()
      H.assertEq(there(), true, string.format("%s: at (%d,%d) on map %d", what, tx, ty, map()))
      say("route", what .. string.format(" (%d hops)", hops))
    end),
  })
end
-- ---- the belly past the crushing room (280's west half, 278) ----
-- 280's west half: its jump triggers (jumps.py: facing the way with A held; some jump twice or thrice in
-- one press: _cb7eb1, _cb7ed2 and their kin)
local function jl(x, y, dir, n)
  local d = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[dir]
  return { x, y, dir, x + d[1] * n, y + d[2] * n, nil, true }
end
local LINKS280W = { jl(14, 54, "left", 4), jl(8, 52, "up", 6), jl(10, 48, "left", 4), jl(8, 46, "down", 6),
  jl(6, 48, "right", 4), jl(12, 48, "down", 2), jl(14, 51, "right", 2), jl(6, 54, "left", 4), jl(1, 52, "up", 4),
  jl(1, 48, "down", 4), jl(10, 54, "right", 4), jl(2, 54, "right", 4), jl(12, 50, "up", 2) }
-- a naming menu (name_menu) suspends the field; START commits the default name (gen_edgar's commitName)
local function commitName(tag)
  local running = 0
  local function menuUp() return H.readByte(0x0059) ~= 0 end
  return H.seqStep({
    H.advanceStory(menuUp, 20000, { playBattles = "tactical", fight = FIGHT }),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format("%s: naming menu open at f%d ($59=%d, menu state $%02X)", tag, H.frame, H.readByte(0x0059),
        H.readByte(0x0026)))
    end),
    H.driveUntil(function()
      running = (H.eventRunning() and not menuUp()) and running + 1 or 0
      return running >= 10
    end, 1800, {
      H.pressButtons({ "start" }, 8),
      H.waitFrames(12),
    }, tag .. ": name committed, event resumed"),
  })
end
-- the field menu's Item list: a Warp Stone ($FD) used where the map allows warp (the belly: route_data
-- "warp on"); $05 main (Item row 0) -A-> $08 list -A-> $19 picked up -A-> used (fieldCare's Tent path)
local WARP_STONE = 0xFD
local function useWarpStone(what)
  local ph, used, n0 = 0, false, nil
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, want)
    if cur == want then return { "a" } end
    return { [cur < want and "down" or "up"] = true }
  end
  return H.withReset(H.driveUntil(function()
    n0 = n0 or H.invCountOf(WARP_STONE)
    return used and not H.menuRunning() and H.worldMode() and H.worldSettled()
  end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s = st()
      if H.invCountOf(WARP_STONE) < n0 then used = true end
      local held = {}
      if used then
        if H.dialogWaiting() then held = { "a" } end
      elseif s == -1 then
        if H.hasControl() then held = { "x" } end
      elseif s == 0x05 then
        held = steer(H.readByte(0x4B), 0)
      elseif s == 0x08 then
        local slot = H.invSlotOf(WARP_STONE)
        if slot == nil then error(what .. ": no Warp Stone in the bag", 0) end
        held = steer(H.readByte(0x4B), slot)
      elseif s == 0x19 then
        local slot = H.invSlotOf(WARP_STONE)
        if slot and H.readByte(0x4B) == slot then held = { "a" } else held = { "b" } end
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, what), function() ph, used, n0 = 0, false, nil end)
end
-- ---- GOGO's commands ----
-- The field menu: $05 main (Status is row 4: field_menu.asm SelectMainMenuOptionTbl) -A-> $06 character
-- select ($4B the party position) -A-> $0c status (GOGO's: $4B the command row 0..3; row 0 is Mimic and A
-- there does nothing, status.asm/field_menu.asm @2254) -A-> $65 -> $6a the command list ($7E9D8A + row: the
-- command ids, $7E9D89 the count; MenuState_6a writes the row's id to $1616 + 37*GOGO + row).  `want` is a
-- list of { row, command id }; a command missing from the list fails the step, naming the list.
local GOGO_CHAR = 12
local function gogoCmdByte(row) return H.readByte(0x1600 + 37 * GOGO_CHAR + 0x16 + row) end
local function gogoCommands(want, what)
  local ph, idx, listLogged = 0, 1, false
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, row)
    if cur == row then return { "a" } end
    return { [cur < row and "down" or "up"] = true }
  end
  local function gogoPos()
    for p = 0, 3 do
      for ch = 0, 15 do
        if (H.readByte(0x1850 + ch) & 7) == H.activeParty() and ((H.readByte(0x1850 + ch) >> 3) & 3) == p
          and ch == GOGO_CHAR then return p end
      end
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
            H.log(string.format("[gogo] %s: the command list (%d): %s", what, n, table.concat(t, " ")))
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
      H.log(string.format("[gogo] %s: commands %02X %02X %02X %02X", what, gogoCmdByte(0), gogoCmdByte(1),
        gogoCmdByte(2), gogoCmdByte(3)))
    end),
  }), function() ph, idx, listLogged = 0, 1, false end)
end
-- Thamasa (gen_wor_phoenix's): the Falcon down on (250,229), the town's door (251,230)
local THAMASA_DOOR, THAMASA_LANDING = { 251, 230 }, { 250, 229 }
-- GOGO's commands beside Mimic (kits.md "Gogo"): Lore, Tools, Item
local GOGO_KIT = { { 1, 0x0C }, { 2, 0x09 }, { 3, 0x01 } }
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-belly-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO }))
  end),
  -- @@setup-end

  -- ---- 1. the crushing room ---------------------------------------------------------------------------
  -- @@stage crush
  -- the door (22,3) lands on 280 (54,52), whose trigger starts the ceiling's clock (_cb80b8); the way on is
  -- the room's south-west corridor (26,54) -> 277, then 277 (4,35) -> the room's west half (15,48)
  walkInto(22, 3, 280, "279 (22,3) -> 280: the crushing room"),
  crushWalk(26, 53, "280: across the crushing room to (26,53)", CRUSH_CHESTS),
  walkInto(26, 54, 277, "280 (26,54) -> 277"),
  walkInto(4, 35, 280, "277 (4,35) -> 280's west half"),
  -- the west half's chest (no clock there): the Thunder Shld (1,45), from below it.  Its corner (x 0-2) is shut
  -- until the plate (12,51) (_cb807e: $018C, _cb7e36) opens the ledge (6,54) the jump west is taken from (labs
  -- x4, x6: no route to it before)
  H.cond(function() return sw(0x018C) == 0 end, {
    H.lazy(function() return navJ(12, 51, LINKS280W, { what = "280 west: onto the plate (12,51)", maxFrames = 12000,
      playBattles = "tactical", fight = FIGHT }) end),
    H.waitUntil(function() return sw(0x018C) == 1 and settled() end, 1800, "280 west: the plate (12,51) ($018C)", 5),
    H.call(function() say("route", "280 west: the plate (12,51)") end),
  }, {}),
  H.lazy(function() return navJ(THUNDER_SHLD.stand[1], THUNDER_SHLD.stand[2], LINKS280W,
    { what = "280 west: below the Thunder Shld", maxFrames = 12000, playBattles = "tactical", fight = FIGHT }) end),
  H.openChest({ stand = THUNDER_SHLD.stand, face = THUNDER_SHLD.face, bit = THUNDER_SHLD.bit, what = THUNDER_SHLD.what,
    item = THUNDER_SHLD.item, nav = { maxFrames = 3000, playBattles = "tactical", fight = FIGHT } }),
  H.lazy(function() return navJ(5, 44, LINKS280W, { what = "280 west: below the door (5,43)", maxFrames = 12000,
    playBattles = "tactical", fight = FIGHT }) end),
  H.call(function()
    for _, o in ipairs({ CRUSH_CHESTS[1], CRUSH_CHESTS[2], CRUSH_CHESTS[3], THUNDER_SHLD }) do
      H.assertEq(H.chestOpen(o.bit), true, string.format("280: the %s's chest (bit %d) is open", o.what, o.bit))
    end
  end),
  walkInto(5, 43, 278, "280 (5,43) -> 278"),
  H.saveState("wor_gogo_278.mss"),

  -- ---- 1b. the hunt in GOGO's room ---------------------------------------------------------------------
  -- @@stage hunt
  K.hunt({ what = "GOGO's room (group 171)", lap = HUNT278_LAP, forms = BELLY171, budget = HUNT_BUDGET,
    castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt" }),
  H.gearDress({ tag = "gear from the crushing room's chests" }),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } },
    { tag = "relics from the crushing room's chests" }),
  H.call(function() H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, STRAGO })) end),

  -- ---- 2. GOGO ------------------------------------------------------------------------------------------
  -- @@stage gogo
  H.navTo(8, 6, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
  H.faceAndHoldA("up", function() return H.dialogWaiting() or not H.hasControl() end, 600, "GOGO (278 (8,5)): face up, A"),
  H.release(),
  commitName("GOGO's name"),
  H.advanceStory(function() return sw(0x00D4) == 1 and settled() end, 30000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "GOGO ($00D4)")
    H.log(string.format("[gogo] party byte $%02X, L%d, HP %d, MP %d, commands %02X %02X %02X %02X", H.readByte(0x1850 + GOGO),
      lv(GOGO), H.readWord(c(GOGO, 9)), H.readWord(c(GOGO, 13)), H.readByte(c(GOGO, 0x16)), H.readByte(c(GOGO, 0x17)),
      H.readByte(c(GOGO, 0x18)), H.readByte(c(GOGO, 0x19))))
  end),
  H.saveState("wor_gogo_met.mss"),

  -- ---- 3. out: the Warp Stone, the cabin, GOGO's kit -----------------------------------------------------
  -- @@stage out
  -- a Warp Stone where the map allows warp sets the party down beside the Falcon on the island
  useWarpStone("a Warp Stone out of the belly"),
  H.call(function() say("wor", "out of the belly") end),
  -- the party for Ebot's Rock: STRAGO (Hidon), RELM (with him, the scene that opens it), GOGO and TERRA
  regroup({ STRAGO, RELM, GOGO, TERRA }),
  gogoCommands(GOGO_KIT, "GOGO: Mimic, Lore, Tools, Item"),
  H.gearDress({ tag = "gear for the four" }),
  H.dressRelics({ { STRAGO, "STRAGO" }, { RELM, "RELM" }, { GOGO, "GOGO" }, { TERRA, "TERRA" } },
    { tag = "relics for the four" }),
  H.call(function() H.log("[kit] " .. kitLine({ STRAGO, RELM, GOGO, TERRA })) end),
  liftOff(),
  H.flyTo(THAMASA_LANDING[1], THAMASA_LANDING[2], { what = "the Falcon to Thamasa", fight = FIGHT }),

  -- ---- 4. Thamasa: the item counter, the scene -----------------------------------------------------------
  -- @@stage thamasa
  H.worldNavTo(THAMASA_DOOR[1], THAMASA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_THAMASA and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
  H.call(function() say("route", "Thamasa") end),
  -- the item counter (gen_wor_gau's), around the scene's triggers
  H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347",
    { fight = FIGHT, avoid = { { 22, 39 }, { 23, 39 } } }),
  H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 74 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
    - H.invCountOf(POTION)) end, "POTION to the band"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(TINCTURE, function() return math.max(0, -(-H.activeTopLevel() // 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the band"),
  H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
  H.shopClose("Thamasa's item shop"),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Thamasa)" }),
  H.call(function() say("shop", "Thamasa") end),
  H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
  -- STRAGO and RELM at Gungho's door (344 (22-23,39): _cb75bf, _cb75d5): $019A, Ebot's Rock's mouth open
  -- (world_2_mod.dat: (249,223)-(249,224))
  H.navTo(23, 40, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
  H.navTo(23, 39, { maxFrames = 3000, arrive = function() return not H.hasControl() end }),
  H.advanceStory(function() return sw(0x019A) == 1 and settled() end, 30000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "Gungho's door ($019A)") end),
  H.saveState("wor_gogo_thamasa.mss"),

  -- ---- 5. the save ---------------------------------------------------------------------------------------
  -- @@stage save
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  H.worldNavTo(THAMASA_LANDING[1], THAMASA_LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.waitFrames(90),
  H.worldNavTo(THAMASA_LANDING[1], THAMASA_LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine({ STRAGO, RELM, GOGO, TERRA }))
  end),
  H.saveAtCheckpoint("wor-gogo-v1"),
  H.saveState("wor_gogo.mss"),
  H.logStep(function()
    return string.format("wor_gogo generated: STRAGO L%d, RELM L%d, GOGO L%d and TERRA L%d beside the Falcon by "
      .. "Thamasa, world (%d,%d), saved in slot 3", lv(STRAGO), lv(RELM), lv(GOGO), lv(TERRA), H.worldX(), H.worldY())
  end),
})

-- probe_black_drgn.lua -- the Black Drgn on the sand beside Tzen, played (#300).
-- A one-off lab (docs/design/route-wor-sabin.md section 12 has its findings):
-- run through tools/tests/probe_black_drgn.py, which derives one copy per
-- variant (the LAB line below) and runs it with OT6_SRAM_CHECKPOINT set and
-- retries off.  (The evidence in build/attempts/wt/black-drgn/ was made
-- under its first name, lab_black_drgn.lua; only the name changed.)
--
-- Cold-Continue a World of Ruin battery that saves at (131,179), one step
-- east of Tzen's door (`wor-tzen-door-v1`: CELES alone; `wor-sabin-v1`:
-- CELES + SABIN), optionally use up K encounters on the plains first (the
-- grind waypoints of gen_wor_tzen_door, off every tile outside the plains
-- groups 31/34 -- docs/TESTING.md "Tests that survive any draw": a seed
-- shift does not re-draw encounters), then walk onto the desert south of
-- the door (world group 36: EarthGuard + Peepers x2, or a lone Black Drgn)
-- and walk it back and forth the way a person who does not know what it
-- holds would, fighting what comes with the walkers' tactical driver
-- (its defaults) and the walkers' field care after each battle, until the
-- Black Drgn (formation 195) has been fought once, or LAB.cap sand
-- battles have passed.  Nothing is written; every step, menu and fight is
-- a button press.  Every battle's open is said with its RNG key (the
-- battle seed $be, the formation and $1FA1-$1FA4, lib's firstBattleKey
-- shape), the party and the bag; the dragon's fight is summed up in one
-- [drgn] VERDICT line.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LAB = { cp = "wor-tzen-door-v1", k = 0, cap = 15 }  -- LAB (probe_black_drgn.py rewrites this line)

local CELES, SABIN = 6, 5
local DRGN_FORM = 195                                -- world group 36's 37.5% formation
local SAND_GROUP = 36
local TONIC, POTION, FENIX, REMEDY, SOFT, TENT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4, 0xF7
local ELIXIR, XPOTION = 0xEC, 0xEA
local AMULET = 0xB3                                 -- protects from Dark|Zombie|Poison (Tzen relic shop 55)
local TZEN_DOOR = { 130, 179 }
local SAVE_TILE = { 131, 179 }
local BOX = { x0 = 118, y0 = 160, x1 = 159, y1 = 223 }
local PLAINS_WPS = { { 141, 196 }, { 136, 200 }, { 144, 199 }, { 141, 203 } }

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch, 8)) end
local function xp(ch) return H.readByte(c(ch, 0x11)) + H.readByte(c(ch, 0x12)) * 256 + H.readByte(c(ch, 0x13)) * 65536 end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local function member(ch, name)
  return string.format("%s L%d xp %d HP %d/%d MP %d/%d status1 $%02X row %s kit %s", name, level(ch), xp(ch),
    H.charHp(ch), H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch),
    (H.readByte(0x1850 + ch) & 0x20) ~= 0 and "back" or "front", kit(ch))
end
local function party()
  local s = member(CELES, "CELES")
  if inParty(SABIN) then s = s .. "; " .. member(SABIN, "SABIN") end
  return s
end
local function bag()
  return { tonic = H.invCountOf(TONIC), potion = H.invCountOf(POTION), fenix = H.invCountOf(FENIX),
           remedy = H.invCountOf(REMEDY), soft = H.invCountOf(SOFT), xpotion = H.invCountOf(XPOTION),
           elixir = H.invCountOf(ELIXIR), tent = H.invCountOf(TENT), amulet = H.invCountOf(AMULET), gil = H.gil() }
end
local function bagStr(b)
  b = b or bag()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d xpotion=%d elixir=%d tent=%d amulet=%d gil=%d",
    b.tonic, b.potion, b.fenix, b.remedy, b.soft, b.xpotion, b.elixir, b.tent, b.amulet, b.gil)
end
local function bagDiff(a, b)
  local t = {}
  for _, k in ipairs({ "tonic", "potion", "fenix", "remedy", "soft", "xpotion", "elixir", "tent", "gil" }) do
    if a[k] ~= b[k] then t[#t + 1] = string.format("%s %d->%d", k, a[k], b[k]) end
  end
  return #t > 0 and table.concat(t, ", ") or "none"
end

-- ---- the battle keys ---------------------------------------------------------
-- InitBattle's `sta $be` (H.seedStoreAddr): A is the battle's RNG seed; the
-- formation is $11E0 and the encounter counters $1FA1-$1FA4 (the lib's
-- firstBattleKey shape), recorded for every battle, not only the first.
local keys, keysUsed = {}, 0
local keyHooked = false
local function hookKeys()
  if keyHooked then return end
  keyHooked = true
  emu.addMemoryCallback(function()
    local seed = emu.getState()["cpu.a"] & 0xff
    keys[#keys + 1] = { frame = H.frame, form = H.readWord(0x11e0), key = H.firstBattleKey(seed, H.readWord(0x11e0)) }
  end, emu.callbackType.exec, H.seedStoreAddr(), H.seedStoreAddr())
end

-- ---- the per-frame watch (the walkers call `arrive` every frame) ---------------
-- A battle's open: its key, the party, the bag.  During the dragon's fight:
-- each seated member's lowest HP, and a death (HP 0) once per member.  At
-- its [outcome]: the VERDICT line.
local inBattle, cur, drgn, sandBattles, lost = false, nil, nil, 0, false
local onSand = false
local function watch()
  local b = H.battleLoadStarted()
  if b and not inBattle then
    inBattle = true
    cur = { open = H.frame, bag = bag(), party = party(), outcomes = #H.outcomes,
            xp = { [CELES] = xp(CELES), [SABIN] = inParty(SABIN) and xp(SABIN) or 0 },
            low = {}, dead = {}, maxhp = {}, sand = onSand }
  end
  if b and cur and cur.form == nil and #keys > keysUsed then
    keysUsed = #keys
    cur.form = keys[#keys].form & 0x1FF
    cur.key = keys[#keys].key
    H.log(string.format("[drgn] battle open f%d on %s: formation $%03X (%d) key %s; %s; %s",
      cur.open, cur.sand and "the SAND" or "the plains", cur.form, cur.form, cur.key, cur.party, bagStr(cur.bag)))
  end
  if b and cur then
    for e = 0, 3 do
      local hp, mx = H.readWord(H.BATTLE_HP + e * 2), H.readWord(0x3C1C + e * 2)
      if mx > 0 and mx < 10000 and hp <= mx then
        cur.maxhp[e] = mx
        if cur.low[e] == nil or hp < cur.low[e] then cur.low[e] = hp end
        if hp == 0 and not cur.dead[e] then
          cur.dead[e] = H.frame
        end
        -- the statuses that land in the fight (STATUS1/2 bits not held at
        -- its open), and in the dragon's fight a trace of every change
        local s1, s2 = H.readByte(0x3EE4 + e * 2), H.readByte(0x3EE5 + e * 2)
        cur.st0 = cur.st0 or {}
        cur.landed = cur.landed or {}
        if cur.st0[e] == nil then cur.st0[e] = { s1, s2 } end
        cur.landed[e] = (cur.landed[e] or 0) | ((s1 & ~cur.st0[e][1]) & 0xFF) | ((((s2 & ~cur.st0[e][2]) & 0xFF)) << 8)
        cur.tr = cur.tr or {}
        local sig = string.format("%d/%02X/%02X", hp, s1, s2)
        if cur.form == DRGN_FORM and cur.tr[e] ~= sig then
          H.log(string.format("[drgn] trace f+%d e%d hp %d/%d st1 $%02X st2 $%02X (was %s)", H.frame - cur.open, e, hp,
            mx, s1, s2, cur.tr[e] or "-"))
        end
        cur.tr[e] = sig
      end
    end
    if cur.form == DRGN_FORM then
      local mh = H.readWord(H.BATTLE_HP + 4 * 2)
      if cur.monHp ~= mh then
        H.log(string.format("[drgn] trace f+%d dragon hp %d (was %s)", H.frame - cur.open, mh, tostring(cur.monHp)))
        cur.monHp = mh
      end
    end
  end
  if not b and inBattle then inBattle = false end
  if cur and #H.outcomes > cur.outcomes then
    local o = H.outcomes[#H.outcomes]
    local form = o.form & 0x1FF
    if cur.sand then sandBattles = sandBattles + 1 end
    if form == DRGN_FORM then
      local lows, deaths, landed = {}, {}, {}
      for e = 0, 3 do
        if cur.low[e] then lows[#lows + 1] = string.format("e%d %d/%d", e, cur.low[e], cur.maxhp[e]) end
        if cur.dead[e] then deaths[#deaths + 1] = string.format("e%d at f+%d", e, cur.dead[e] - cur.open) end
        if cur.landed and cur.landed[e] and cur.landed[e] ~= 0 then
          landed[#landed + 1] = string.format("e%d $%04X%s", e, cur.landed[e],
            (cur.landed[e] & 0x02) ~= 0 and " (ZOMBIE)" or "")
        end
      end
      drgn = { kind = o.kind, tick = o.tick, due = o.due, key = cur.key, bag0 = cur.bag, bag1 = bag(),
               lows = table.concat(lows, ", "), deaths = #deaths > 0 and table.concat(deaths, ", ") or "none",
               xp0 = cur.xp, open = cur.open, party0 = cur.party }
      H.log(string.format("[drgn] VERDICT the Black Drgn: %s after %d ticks (sand battle %d, key %s); lowest HP %s; "
        .. "deaths %s; statuses landed (STATUS2<<8|STATUS1) %s; XP due %d a member; bag at the end hook %s (spent in battle: %s); the party then: %s",
        o.kind:upper(), o.tick, sandBattles, cur.key or "?", drgn.lows, drgn.deaths,
        #landed > 0 and table.concat(landed, ", ") or "none", o.due, bagStr(drgn.bag1),
        bagDiff(cur.bag, drgn.bag1), party()))
      if o.kind == "lost" then lost = true end
    else
      H.log(string.format("[drgn] battle $%03X %s after %d ticks on %s (sand battles so far %d)",
        form, o.kind, o.tick, cur.sand and "the sand" or "the plains", sandBattles))
    end
    cur = nil
  end
  return false
end

-- ---- the sand ----------------------------------------------------------------------
local SAND, NONSAND, WP = nil, nil, nil
local function buildSand()
  local sand, other = {}, {}
  for y = BOX.y0, BOX.y1 do
    for x = BOX.x0, BOX.x1 do
      local g = H.worldEncounterGroup(x, y, x, y)
      if g == SAND_GROUP then sand[#sand + 1] = { x, y }
      elseif H.worldPassable(x, y) then other[#other + 1] = { x, y } end
    end
  end
  other[#other + 1] = TZEN_DOOR
  SAND, NONSAND = sand, H.worldAvoidSet(other)
  -- A: the sand tile nearest the save tile; B: the sand tile farthest from
  -- A (in steps, on the sand) up to 6 steps -- a short beat on the sand
  local best, bd = nil, 1e9
  for _, t in ipairs(sand) do
    local d = math.abs(t[1] - SAVE_TILE[1]) + math.abs(t[2] - SAVE_TILE[2])
    if d < bd then best, bd = t, d end
  end
  local far, fd = nil, -1
  for _, t in ipairs(sand) do
    local p = H.worldBfs(t[1], t[2], {}, best[1], best[2], NONSAND)
    if p and #p <= 6 and #p > fd then far, fd = t, #p end
  end
  WP = { best, far }
  local pool = H.encounterPool(SAND_GROUP)
  local forms = {}
  for slot = 1, 4 do
    for _, f in ipairs(pool[slot].formations) do forms[#forms + 1] = string.format("slot%d:%d", slot, f.id) end
  end
  H.log(string.format("[drgn] the sand: %d tiles of group %d in (%d..%d, %d..%d); pool %s; the beat (%d,%d) <-> (%d,%d), %d steps",
    #sand, SAND_GROUP, BOX.x0, BOX.x1, BOX.y0, BOX.y1, table.concat(forms, " "), best[1], best[2], far[1], far[2], fd))
end

local PLAINS_AVOID = nil
local function plainsAvoid()
  if PLAINS_AVOID == nil then
    local list = {}
    for y = BOX.y0, BOX.y1 do for x = BOX.x0, BOX.x1 do
      local g = H.worldEncounterGroup(x, y, x, y)
      if g ~= nil and g ~= 31 and g ~= 34 then list[#list + 1] = { x, y } end
    end end
    for _, t in ipairs({ TZEN_DOOR, { 140, 209 }, { 141, 209 } }) do list[#list + 1] = t end
    PLAINS_AVOID = H.worldAvoidSet(list)
  end
  return PLAINS_AVOID
end

local wp, bag0 = 1, nil
H.run({ maxFrames = 400000 }, {
  -- ---- 0. cold Continue (gen_wor_sabin's) -------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin outside Tzen", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract(LAB.cp)
    hookKeys()
    inBattle, cur, drgn, sandBattles, lost, onSand, wp = false, nil, nil, 0, false, false, 1
    H.log(string.format("[drgn] boot f%d from %s: world %d (%d,%d); %s; %s; K=%d cap=%d", H.frame, LAB.cp,
      H.worldId(), H.worldX(), H.worldY(), party(), bagStr(), LAB.k, LAB.cap))
  end),

  -- ---- 1. K encounters used up on the plains (the draw moves) -------------------
  H.cond(function() return LAB.k > 0 end, {
    (function()
      local fought0, i = nil, 1
      return H.withReset(H.driveUntil(function()
        return fought0 ~= nil and #H.outcomes - fought0 >= LAB.k
      end, 400000, {
        H.call(function() if fought0 == nil then fought0 = #H.outcomes end end),
        H.worldNavTo(function() return PLAINS_WPS[i][1] end, function() return PLAINS_WPS[i][2] end,
          { maxFrames = 20000, playBattles = "tactical", avoid = plainsAvoid, arrive = watch }),
        H.call(function() i = i % #PLAINS_WPS + 1 end),
      }, "use up K encounters on the plains"), function() fought0, i = nil, 1 end)
    end)(),
    H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 20000, playBattles = "tactical",
      avoid = plainsAvoid, arrive = watch }),
    H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "back at (131,179)", 5),
    H.call(function()
      H.log(string.format("[drgn] %d encounter(s) used up before the sand: f%d world (%d,%d); %s; %s; $1FA1-5 = %02X %02X %02X %02X %02X",
        #H.outcomes, H.frame, H.worldX(), H.worldY(), party(), bagStr(), H.readByte(0x1FA1),
        H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    end),
  }, {}),

  -- ---- 2. onto the sand, until the dragon has been met -------------------------------
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled before the sand", 5),
  H.call(function() buildSand() end),
  -- the first step off the save tile: (131,179)'s neighbours are the door
  -- and the plain, so the way onto the sand avoids only the door
  H.worldNavTo(function() return WP[1][1] end, function() return WP[1][2] end,
    { maxFrames = 20000, playBattles = "tactical", avoid = { TZEN_DOOR }, arrive = watch }),
  H.call(function()
    onSand, bag0, wp = true, bag(), 2
    H.log(string.format("[drgn] onto the sand f%d at (%d,%d): %s; %s", H.frame, H.worldX(), H.worldY(),
      party(), bagStr(bag0)))
  end),
  H.withReset(H.driveUntil(function()
    return drgn ~= nil or lost or sandBattles >= LAB.cap
  end, 600000, {
    H.worldNavTo(function() return WP[wp][1] end, function() return WP[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", avoid = function() return NONSAND end,
        wipeEndsRide = true, arrive = watch }),
    H.call(function() wp = wp % 2 + 1 end),
  }, "walk the sand until the Black Drgn comes"), function() wp = 1 end),
  H.call(function()
    if lost or (drgn and drgn.kind == "lost") then
      error(string.format("LOST: the Black Drgn beat the party (%s) after %d ticks, key %s",
        LAB.cp, drgn and drgn.tick or -1, drgn and drgn.key or "?"), 0)
    end
    H.assertEq(drgn ~= nil, true, string.format("the Black Drgn met within %d sand battles", LAB.cap))
  end),
  -- the field care after the dragon has run inside the leg; finish the leg
  -- so it has, then say what the fight and its care cost
  H.worldNavTo(function() return WP[wp][1] end, function() return WP[wp][2] end,
    { maxFrames = 20000, playBattles = "tactical", avoid = function() return NONSAND end, arrive = watch }),
  H.call(function()
    H.log(string.format("[drgn] after the dragon and its field care f%d: %s; %s; since the dragon opened: %s; "
      .. "since onto the sand: %s; XP CELES +%d%s", H.frame, party(), bagStr(), bagDiff(drgn.bag0, bag()),
      bagDiff(bag0, bag()), xp(CELES) - drgn.xp0[CELES],
      inParty(SABIN) and string.format(" SABIN +%d", xp(SABIN) - drgn.xp0[SABIN]) or ""))
  end),
})

-- gen_edgar.lua -- the whole Figaro chapter, from figaro_entry.mss
-- (TERRA + LOCKE at map 55 (28,42), the castle gate) to the world map
-- outside the sand.  Generates three states:
--   figaro_intro.mss    after the first audience ($0004 set)
--   figaro_matron.mss   after the flashback ($0308 set again)
--   figaro_cleared.mss  first controllable frame on the world map,
--                       TERRA + LOCKE + EDGAR, tools carried
--
-- The party roster changes several times through the chapter; every
-- position read goes through the $0803 party-object offset (H.fieldX/Y)
-- rather than a fixed character slot.
--
-- Shop 82 (map 59 (44,15)) refuses to sell once EDGAR is in the party, so
-- the AutoCrossbow/NoiseBlaster/BioBlaster purchase happens on the first
-- pass through, before the intro scene.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/figaro_entry.mss.lua"

-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end
local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
-- a menu module owns the CPU (the field's own "menu opening" flag; safe
-- here because no battle happens anywhere in the castle to alias it)
local function menuUp() return H.readByte(0x0059) ~= 0 end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- calm()'s world-module twin, for after the submerge: the overworld is a
-- separate engine with its own position and control registers.  The
-- submerge cutscene visits the world map briefly partway through, with
-- worldHasControl() true on a black screen; requiring a lit screen too
-- rejects that transient, which is why the brightness term is required
-- and n is 120 rather than 30.
local function worldCalm(n)
  local cnt = 0
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function where(tag)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) $0004=%d $0005=%d $0006=%d $0308=%d $0311=%d " ..
    "$0313=%d $0315=%d $01F0=%d $01F1=%d $01F8=%d gil=%d party=%d%d%d%d%d%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0004), sw(0x0005),
    sw(0x0006), sw(0x0308), sw(0x0311), sw(0x0313), sw(0x0315), sw(0x01F0),
    sw(0x01F1), sw(0x01F8), gil(),
    H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1852) & 7,
    H.readByte(0x1853) & 7, H.readByte(0x1854) & 7, H.readByte(0x1855) & 7))
end

-- crossDoor/talkTo/buy expand to several steps; H.cond with an always-true
-- predicate wraps a list into a single step object (a bare list can't be
-- spliced into a step list).
local function seq(steps) return H.cond(function() return true end, steps) end

local aPhase = 0

-- Cross the entrance whose source tile is (sx,sy), landing on map dm at
-- (dx,dy).  The door tile is a wall until CheckDoor opens it, so BFS
-- cannot plan through it: the crossing is navTo to a neighbouring tile
-- plus one continuous hold into the door, with the staging tile and hold
-- direction derived by BFS-ing each neighbour and taking the first one
-- reachable right now.  The neighbour set is all eight (not four) because
-- a door at the head of a staircase can only be entered diagonally; a
-- diagonal candidate must also be a move the engine would actually
-- produce there (H.canStep).
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, fixed)
  local pick, startMap
  local function stage()
    if not pick then
      pick = fixed
      if not pick then
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            pick = { cx, cy, press }; break
          end
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    -- A staircase entrance sits on an ordinary walkable tile, so BFS may
    -- route straight across it before the hold starts; a map change
    -- counts as arrival, and the far-side assert below still checks it
    -- was the right map.
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical",
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
    H.waitUntil(function()
      return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("%s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Talk to object `obj`.  CheckNPCs activates whatever the object map
-- holds one tile in the party's facing direction while A is held.  A
-- short directional tap does not turn the party; the drive holds the
-- direction until the facing byte reads the wanted value, then edge-taps
-- A.  Facing: 0 up, 1 right, 2 down, 3 left.
local FACE = { up = 0, right = 1, down = 2, left = 3 }

local function talkTo(obj, what, maxFrames)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local function facing()
    return H.readByte(0x087f + H.readWord(0x0803))
  end
  -- first adjacent tile BFS can currently reach; re-resolved at most every
  -- 30 frames because NPCs wander
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      local cand = { { ox, oy + 1 }, { ox, oy - 1 }, { ox - 1, oy }, { ox + 1, oy } }
      apPick = cand[1]
      for _, c in ipairs(cand) do
        if H.bfsPath(c[1], c[2], NAV.blocked) then apPick = c; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
      maxFrames = maxFrames or 9000, playBattles = "tactical",
    })
  end
  -- One activation attempt.  Soft rounds give up without failing (the NPC
  -- wandered off; walk back and try again); the last round raises.
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting() or menuUp())
        and started + 1 or 0
      if started >= 8 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if waited % 300 == 0 then
          local ox, oy = objAt()
          H.log(string.format("  %s: f%d me=(%d,%d) npc=(%d,%d) adj=%s ctl=%s face=%d",
            what, H.frame, H.fieldX(), H.fieldY(), ox, oy, tostring(adjacent()),
            tostring(H.hasControl()), facing()))
        end
        if not (H.hasControl() and adjacent()) then H.setPad({}); return end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.logStep(function()
      local ox, oy = objAt()
      return string.format("%s: object %d at (%d,%d); party at (%d,%d) f%d",
        what, obj, ox, oy, H.fieldX(), H.fieldY(), H.frame)
    end),
    walkStep(), pokeStep(1, 600, false),
    -- round 2, written out flat: repeatN cannot replay navTo/driveUntil
    -- bodies (their latched state carries over)
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.logStep(function()
      return string.format("%s: engaged at frame %d", what, H.frame)
    end),
  })
end

-- A naming menu is the one scene advanceStory cannot tap through, because
-- it suspends the field module entirely.  START commits the default name,
-- pressed on repeat until the event engine resumes.
local function commitName(tag)
  local running = 0
  return seq({
    H.advanceStory(menuUp, 20000, { playBattles = "tactical" }),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format("%s: naming menu open at f%d ($59=%d, menu state $%02X)",
        tag, H.frame, H.readByte(0x0059), H.readByte(0x0026)))
      H.screenshot(tag)
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

-- ------------------------------------------------------------------ shop --
-- Every press waits for the menu state it expects.  States: $25 options,
-- $26 buy list, $27 quantity, $28 post-buy wait -> $26.  The cursor row is
-- $4B; row r's item id is $7E9D89+r and its price $7E9F09+2r.
local function mstate() return H.readByte(0x0026) end
local function shopRow() return H.readByte(0x004b) end
local function rowItem(r) return H.readByte(0x9d89 + r) end
local function inState(s) return function() return mstate() == s end end

local function shopPress(btn, pred, what)
  return seq({
    H.pressButtons({ btn }, 6),
    H.waitUntil(pred, 900, "shop: " .. what, 2),
  })
end

local function buyItem(id, fromRow, toRow, price)
  local before = 0
  local steps = {}
  local stride = toRow > fromRow and 1 or -1
  for r = fromRow + stride, toRow, stride do
    steps[#steps + 1] = shopPress(stride > 0 and "down" or "up",
      (function(rr) return function() return shopRow() == rr end end)(r),
      string.format("cursor -> row %d", r))
  end
  steps[#steps + 1] = H.call(function()
    before = gil()
    H.assertEq(rowItem(shopRow()), id,
      string.format("shop cursor on item $%02X (row %d)", id, shopRow()))
  end)
  steps[#steps + 1] = shopPress("a", inState(0x27), "quantity window")
  steps[#steps + 1] = shopPress("a", function() return gil() < before end,
    string.format("purchase $%02X", id))
  steps[#steps + 1] = H.waitUntil(inState(0x26), 900, "shop: back to buy list", 2)
  steps[#steps + 1] = H.call(function()
    H.assertEq(before - gil(), price, string.format("$%02X cost", id))
    H.assertEq(invCount(id) >= 1, true, string.format("$%02X in inventory", id))
  end)
  return seq(steps)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(10),
  H.waitUntil(calm(10), 600, "entry point control", 5),
  H.call(function()
    H.assertEq(map(), 55, "boot map is the Figaro courtyard (55)")
    H.assertEq(H.fieldX() == 28 and H.fieldY() == 42, true, "at the gate (28,42)")
    H.assertEq(sw(0x0004), 0, "$0004 clear (Edgar intro unseen)")
    H.assertEq(sw(0x0308), 1, "$0308 set (throne Edgar spawned)")
    H.assertEq(sw(0x030F), 1, "$030F set (matron spawned)")
    H.assertEq(sw(0x0005), 0, "$0005 clear (flashback unseen)")
    H.assertEq(sw(0x0049), 0, "$0049 clear (matron's later branch dark)")
    where("start")
  end),

  -- ==================================================================== --
  -- PHASE 1: gate -> entrance hall -> throne wing.  The first step north
  -- fires the gate scene, which parks the guard NPC on (28,40) for its
  -- two dialogs; navTo's no-path patience rides that out.
  -- ==================================================================== --
  crossDoor(28, 38, 59, 12, 49, "D1 gate -> gatehouse"),
  crossDoor(12, 41, 55, 28, 31, "D2 gatehouse -> inner courtyard"),
  crossDoor(28, 13, 59, 27, 28, "D3 inner courtyard -> throne hall"),
  H.call(function() where("throne hall") end),

  -- ==================================================================== --
  -- PHASE 2a: the ITEM shop restock (owner directive: the route re-shops).
  -- The throne hall has TWO twin shop doors side by side: (32,21) -> tool
  -- alcove (D4 below) and (22,21) -> item shop (10,18).  The item merchant
  -- (obj 24) stands at map 59 (10,13) with a walkable tile directly below,
  -- a plain adjacent talk -- his event _ca67a2 opens shop_menu 4
  -- (TERRA+LOCKE fall past the EDGAR/SABIN refusal cases; $00A4=$0048=0
  -- so it is shop 4, not 64/47).  Shop 4 row 0 is Tonic (50 GP), row 5
  -- Fenix Down (500 GP); it sells no Potion.  This is the ONLY Tonic
  -- vendor anywhere in figaro_cleared's chain from power-on, so the party
  -- arrives Tonic-starved (figaro_entry carries 0) and the shipped fixture
  -- was reddening the item-turn tests (battle_steal/thief/stealmp, which
  -- bank BP off Tonic/Potion turns).  Restock Tonics to 30 here so care's
  -- 0.9 top-off stays sustainable and the fixture ships stocked.  This is
  -- the pre-Edgar window; once EDGAR joins the shop refuses.
  crossDoor(22, 21, 59, 10, 18, "D4a throne hall -> ITEM shop"),
  talkTo(24, "item merchant", 6000),
  H.waitUntil(inState(0x25), 900, "item shop: options menu", 2),
  H.call(function() H.screenshot("edgar_itemshop") end),
  shopPress("a", inState(0x26), "item shop: buy list open"),
  H.call(function()
    local rows = {}
    for r = 0, 7 do
      rows[#rows + 1] = string.format("%d:$%02X@%d", r, rowItem(r),
        H.readWord(0x9f09 + r * 2))
    end
    H.log("shop 4 stock: " .. table.concat(rows, " "))
    H.assertEq(rowItem(0), 0xE8, "item shop row 0 is Tonic")
    H.assertEq(rowItem(5), 0xF0, "item shop row 5 is Fenix Down")
    H.log(string.format("[shop] item shop heading in: gil=%d tonic=%d "
      .. "potion=%d fenix=%d", gil(), invCount(0xE8), invCount(0xE9),
      invCount(0xF0)))
  end),
  -- Tonics are THE field-heal consumable (care heals with them, not by
  -- casting).  Buy to 30 HERE -- proven to stock figaro_cleared for the
  -- steal/thief tests -- and let the LATER, gil-richer shops push toward
  -- the full 99 as the owner wants.  30 fresh Tonics = 1500 GP of ~5338
  -- gil; buying more starves gen_kolts's own South Figaro Fenix/Soft
  -- targets (measured: 60 here left South Figaro too poor to buy 2 Softs,
  -- failing that assertion and blocking the whole downstream tree).
  H.buyItem(0xE8, 0, function() return 30 - invCount(0xE8) end, "TONIC to 30"),
  H.waitUntil(inState(0x26), 2400, "item shop: back at the buy list", 2),
  shopPress("b", inState(0x25), "item shop: back to options"),
  shopPress("b", function() return H.hasControl() and map() == 59 end,
    "item shop: closed"),
  H.call(function()
    H.assertEq(invCount(0xE8) >= 25, true,
      string.format("Tonics restocked at the Figaro item shop (have %d)",
        invCount(0xE8)))
    H.log(string.format("[shop] item shop done: gil=%d tonic=%d potion=%d "
      .. "fenix=%d", gil(), invCount(0xE8), invCount(0xE9), invCount(0xF0)))
    where("item shop done")
  end),
  crossDoor(10, 19, 59, 22, 23, "D4b ITEM shop -> throne hall"),

  -- ==================================================================== --
  -- PHASE 2: the shop, in its only window (TERRA + LOCKE, pre-Edgar).
  -- ==================================================================== --
  crossDoor(32, 21, 59, 44, 18, "D4 throne hall -> shop alcove"),
  talkTo(25, "tool merchant", 6000),
  H.waitUntil(inState(0x25), 900, "shop: options menu", 2),
  H.call(function() H.screenshot("edgar_shop") end),
  shopPress("a", inState(0x26), "buy list open"),
  H.call(function()
    local rows = {}
    for r = 0, 4 do
      rows[#rows + 1] = string.format("%d:$%02X@%d", r, rowItem(r),
        H.readWord(0x9f09 + r * 2))
    end
    H.log("shop 82 stock: " .. table.concat(rows, " "))
    H.assertEq(rowItem(0), 0xAA, "row 0 is AutoCrossbow")
    H.assertEq(rowItem(1), 0xA3, "row 1 is NoiseBlaster")
    H.assertEq(rowItem(2), 0xA4, "row 2 is BioBlaster")
  end),
  buyItem(0xA4, 0, 2, 750),               -- BioBlaster: the poison key
  buyItem(0xA3, 2, 1, 500),               -- NoiseBlaster
  shopPress("b", inState(0x25), "back to options"),
  shopPress("b", function() return H.hasControl() end, "shop closed"),
  H.call(function()
    H.assertEq(invCount(0xA4), 1, "BioBlaster bought")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster bought")
    where("shop done")
  end),
  -- The alcove's two chests: a closed room whose only way in is the D4 door.
  H.openChest{ stand = { 43, 13 }, face = "up", bit = 14, what = "Tonic",
               item = 0xE8 },
  H.openChest{ stand = { 44, 13 }, face = "up", bit = 15, what = "Antidote",
               item = 0xF2 },
  crossDoor(44, 19, 59, 32, 23, "D5 shop alcove -> throne hall"),

  -- ==================================================================== --
  -- PHASE 3: the throne room, first talk: the intro scene, the free
  -- AutoCrossbow and `name_menu EDGAR`.  Done when $0004 flips.
  -- ==================================================================== --
  crossDoor(27, 13, 58, 102, 55, "D6 throne hall -> THRONE ROOM"),
  talkTo(16, "EDGAR (intro)", 9000),
  commitName("edgar_naming"),
  H.advanceStory(calm(30, function() return sw(0x0004) == 1 end), 20000,
    { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x0004), 1, "intro ran ($0004 set)")
    H.assertEq(sw(0x0308), 0, "throne Edgar despawned ($0308 clear)")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow handed over by the intro")
    where("intro done")
    H.screenshot("edgar_intro_done")
  end),

  -- ==================================================================== --
  -- PHASE 4: assert the far side and generate.
  -- ==================================================================== --
  H.call(function()
    H.assertEq(map(), 58, "still in the throne room")
    H.assertEq(sw(0x0004), 1, "$0004 set")
    H.assertEq(sw(0x0308), 0, "$0308 clear")
    H.assertEq(sw(0x0315), 1, "$0315 set (the courtyard guard is armed)")
    H.assertEq(invCount(0xA4), 1, "BioBlaster carried")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow carried")
    -- gil deltas were already asserted at buy time; no absolute check here.
    for c = 0, 5 do
      local base = 0x1600 + 37 * c
      H.log(string.format("char %d: actor=%02X level=%d hp=%d/%d party=%d",
        c, H.readByte(base), H.readByte(base + 8), H.readWord(base + 9),
        H.readWord(base + 11) & 0x3fff, H.readByte(0x1850 + c) & 7))
    end
    H.screenshot("figaro_intro")
  end),
  H.saveState("figaro_intro.mss"),
  H.logStep(function()
    return string.format("figaro_intro generated at frame %d", H.frame)
  end),

  -- ==================================================================== --
  -- PHASE 5: the matron.  Her room (map 57) hangs off the castle's west
  -- ring; the only way onto the ring is the chamber behind 55 (23,24),
  -- whose diagonal staircase leads through the west wing door (66,50).
  -- ==================================================================== --
  crossDoor(102, 56, 59, 27, 15, "D7 throne room -> throne hall"),
  crossDoor(27, 29, 55, 28, 15, "D8 throne hall -> inner courtyard"),
  crossDoor(23, 24, 59, 47, 60, "D9 inner courtyard -> west chamber"),
  -- D10 is the chamber's diagonal staircase; BFS and crossDoor's staging
  -- search handle it like an ordinary door crossing.
  crossDoor(50, 60, 59, 65, 43, "D10 west chamber -> west wing"),
  crossDoor(66, 50, 55, 23, 33, "D12 west wing -> WEST RING"),
  crossDoor(12, 26, 57, 67, 27, "D13 west ring -> matron's room"),
  H.call(function() where("matron's room") end),

  talkTo(17, "MATRON", 9000),
  commitName("sabin_naming"),
  H.advanceStory(calm(30, function()
    return map() == 57 and sw(0x0005) == 1
  end), 30000, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x0005), 1, "flashback ran ($0005 set)")
    H.assertEq(sw(0x0308), 1, "EDGAR RESPAWNED on the throne ($0308 set)")
    H.assertEq(sw(0x0316), 1, "$0316 set (chancellor armed)")
    H.assertEq(map(), 57, "back in the matron's room")
    where("flashback done")
    H.screenshot("figaro_matron")
  end),
  H.saveState("figaro_matron.mss"),
  H.logStep(function()
    return string.format("figaro_matron generated at frame %d", H.frame)
  end),

  -- ==================================================================== --
  -- PHASE 6: back to the throne.  The west arc is a dead end, so the
  -- return re-crosses the chamber staircase (K3) from the other side;
  -- it's reachable only up-left from (65,43).
  -- ==================================================================== --
  crossDoor(67, 28, 55, 12, 28, "K1 matron's room -> WEST RING"),
  crossDoor(23, 31, 59, 66, 49, "K2 west ring -> west wing"),
  crossDoor(64, 42, 59, 49, 59, "K3 west wing -> west chamber (stair)"),
  crossDoor(47, 61, 55, 23, 26, "K4 west chamber -> inner courtyard"),
  crossDoor(28, 13, 59, 27, 28, "K5 inner courtyard -> throne hall"),
  crossDoor(27, 13, 58, 102, 55, "K6 throne hall -> THRONE ROOM"),
  H.call(function() where("second audience") end),

  -- ==================================================================== --
  -- PHASE 7: Kefka.  Talking to EDGAR now triggers his arrival; the party
  -- becomes EDGAR alone and control returns in the courtyard.
  -- ==================================================================== --
  talkTo(16, "EDGAR (second audience)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0311) == 1
  end), 30000, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x0311), 1, "Kefka scene ran ($0311 set)")
    H.assertEq(sw(0x0315), 0, "$0315 cleared by the scene")
    H.assertEq(map(), 55, "control returns in the courtyard")
    where("Kefka arrived")
    H.screenshot("figaro_kefka")
  end),

  -- ==================================================================== --
  -- PHASE 8: the confrontation, then LOCKE's regroup.  Both troopers'
  -- switches are map-local and don't survive a door, so both must be
  -- talked to here, after Kefka arrives, or the confrontation is a
  -- silent no-op.
  -- ==================================================================== --
  talkTo(21, "trooper east", 9000),
  H.advanceStory(calm(20, function() return sw(0x01F0) == 1 end), 9000,
    { playBattles = "tactical" }),
  H.call(function() H.assertEq(sw(0x01F0), 1, "$01F0 set (east trooper)") end),
  talkTo(22, "trooper west", 9000),
  H.advanceStory(calm(20, function() return sw(0x01F1) == 1 end), 9000,
    { playBattles = "tactical" }),
  H.call(function() H.assertEq(sw(0x01F1), 1, "$01F1 set (west trooper)") end),
  talkTo(20, "KEFKA", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0006) == 1
  end), 30000, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x0006), 1, "confrontation done ($0006 set)")
    where("Kefka done")
  end),
  talkTo(27, "LOCKE (regroup)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0313) == 1
  end), 30000, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x0313), 1, "$0313 set (guest-room LOCKE armed)")
    H.assertEq(sw(0x0315), 1, "$0315 set (courtyard guard re-armed)")
    H.assertEq(sw(0x01FF), 1, "$01FF set (regroup done)")
    where("regrouped")
  end),

  -- ==================================================================== --
  -- PHASE 9: the burning night.  The guest-room LOCKE runs the whole
  -- night scene; he's on the east arc, so this crossing uses the map-60
  -- route the west leg never needed.
  -- ==================================================================== --
  crossDoor(33, 24, 60, 103, 29, "K7 inner courtyard -> map 60"),
  crossDoor(96, 26, 59, 81, 11, "K8 map 60 -> east wing (diagonal stair)"),
  crossDoor(80, 18, 55, 33, 33, "K9 east wing -> EAST RING"),
  crossDoor(44, 26, 59, 79, 52, "K10 east ring -> guest wing"),
  talkTo(19, "LOCKE (guest room)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x01F8) == 1
  end), 40000, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(sw(0x01F8), 1, "the burning night ran ($01F8 set)")
    H.assertEq(map(), 55, "back on map 55, at night")
    where("burning night")
    H.screenshot("figaro_night")
  end),

  -- ==================================================================== --
  -- PHASE 10: the submerge.  The courtyard guard triggers the chocobo
  -- ride out onto the world map; from there it is world-module RAM, not
  -- field RAM, so the settle predicate changes too.
  -- ==================================================================== --
  talkTo(19, "courtyard guard (submerge)", 9000),
  H.advanceStory(worldCalm(120), 90000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.assertEq(H.worldHasControl(), true, "and controllable")
    -- roster: TERRA + LOCKE + EDGAR, by party byte, not by slot index
    local inParty = {}
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then inParty[c] = true end
    end
    H.assertEq(inParty[4] or false, true, "EDGAR in the party ($1854)")
    H.assertEq(inParty[0] or false, true, "TERRA in the party ($1850)")
    H.assertEq(inParty[1] or false, true, "LOCKE in the party ($1851)")
    -- the tools bought at the shop survived the chapter
    H.assertEq(invCount(0xA4), 1, "BioBlaster still carried")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster still carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow still carried")
    -- The party lands on a chocobo ($11FA&3=2); InitChoco never
    -- initialises the world tile-position registers $E0/$E2, so
    -- H.worldX/worldY read 0 here and H.worldNavTo cannot be used until
    -- the party dismounts.
    H.assertEq(H.readByte(0x11fa) & 3, 2, "riding a chocobo ($11FA&3=2)")
    H.log(string.format(
      "world id=%d $E0/$E2=(%d,%d) [zero: chocobo, see above] " ..
      "chars=$1EDC=%04X gil=%d",
      H.worldId(), H.worldX(), H.worldY(), H.readWord(0x1edc), gil()))
    for c = 0, 15 do
      if inParty[c] then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d party-byte=%02X",
          c, H.readByte(base), H.readByte(base + 8), H.readWord(base + 9),
          H.readByte(0x1850 + c)))
      end
    end
    H.screenshot("figaro_cleared")
  end),
  H.saveState("figaro_cleared.mss"),
  H.logStep(function()
    return string.format("figaro_cleared generated at frame %d", H.frame)
  end),
})

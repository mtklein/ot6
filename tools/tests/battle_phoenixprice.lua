-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_phoenixprice.lua -- a boost never makes Phoenix cheaper (#293).
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_phoenixprice.lua <log>
--
-- A boosted summon is a multiplier verb and pays 2.5x its base MP per level,
-- capped at 99 because every OT6 price drawer but the summon row prints two
-- digits (Ot6BoostPriceFor).  Phoenix is the one price in the game above
-- that cap: 110 (MagicProp +$05), legal because the summon row, the top row
-- of the battle Magic list, draws three digits.  Capping a boosted Phoenix to 99 would charge less for more,
-- so Ot6BoostPriceFor floors the capped price at the base: a boosted Phoenix
-- costs 110 at every level.  This measures that on every surface that states
-- the price, in a real battle, through real menus:
--   the stamp   the summon row's cost byte in TERRA's spell list (row 0,
--               byte 3), the one number GetMPCost charges from (#251), which
--               Ot6FoldPrices rewrites on every L/R edge;
--   the drawn   the digits the summon row prints beside PHOENIX;
--   the grey    that row's colour: white exactly when TERRA's pool pays the
--               price (her 204 MP pays 110 and 99 alike, so on this pool the
--               colour cannot tell a floored price from a capped one; the
--               other three surfaces can, and a floorless mutant fails them:
--               99 stamped, drawn and charged, build/attempts/wt/
--               battle-fixes-023/);
--   the charge  the cost queued for the summon ($3620-$371f, written while
--               TERRA's action is created) and the MP her pool loses.
-- at boost 0, 1, 2 and 3; the summon is cast at 3, the level where the
-- uncapped price is furthest above the ceiling (110 x 15.6).
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt).  No fixture has
-- Phoenix: the magicite is found in the World of Ruin, past the route.  So
-- after the cold Continue this test writes ONE byte, TERRA's equipped-esper
-- cell in her field record ($1600 + 37*0 + $1e), to Phoenix ($1a).  Battle
-- init builds the summon row from that byte (ValidateSpellList), so
-- everything after is the engine's own: the list, the menus, the queue, the
-- charge.  This is a mechanism measurement of the price, not play and not a
-- claim about Phoenix in the World of Ruin.

local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC, ST_ESPER = 0x05, 0x27, 0x38, 0x0E, 0x16
local BANK, PEND, CURMP, MLISTPTR = 0x3E9C, 0x3E9D, 0x3C08, 0x302C
local CMD_MAGIC = 0x02
local TERRA = 0
local PHOENIX_ESPER, PHOENIX_REC, PHOENIX_MP = 0x1A, 0x50, 110
local ESPER_CELL = 0x1600 + 37 * TERRA + 0x1E
-- PHOENIX as the summon row prints it (FF3-US glyphs: A = $80, a = $9a)
local NAME = { 0x8F, 0xA1, 0xA8, 0x9E, 0xA7, 0xA2, 0xB1 }
local DIGIT0 = 0xB4
local MAXB = 3

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function listBase(s) return H.readWord(MLISTPTR + s * 2) end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function mapWord(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end
local function findName()
  for w = 0x5800, 0x7FF0 do
    local hit = true
    for i = 1, #NAME do
      if (mapWord(w + i - 1) & 0xFF) ~= NAME[i] then hit = false break end
    end
    if hit then return w end
  end
end
-- the number drawn after the name: the first run of digit glyphs within
-- the next 10 cells, read as decimal; and the attribute byte of its cells
local function drawnPrice(w)
  local n, attr, seen = 0, nil, false
  for i = #NAME, #NAME + 10 do
    local t = mapWord(w + i)
    local g = t & 0xFF
    if g >= DIGIT0 and g <= DIGIT0 + 9 then
      n = n * 10 + (g - DIGIT0); attr = attr or (t >> 8); seen = true
    elseif seen then break end
  end
  return seen and n or nil, attr, mapWord(w) >> 8
end

-- ---- observers --------------------------------------------------------------
local terraS = nil
local queued = {}        -- cost-queue stores made for TERRA
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  emu.addMemoryCallback(function(_, v)
    if terraS and (emu.getState()["cpu.x"] & 0xFF) == terraS * 2 then
      queued[#queued + 1] = { f = H.frame, v = v, cmd = H.readByte(0x3A7A),
                              atk = H.readByte(0x3A7B), pend = pend(terraS) }
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E371F)
end

-- ---- the walk to an encounter ----------------------------------------------
local home, away
local function lap()
  local goal, plan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then plan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if plan == nil or idx > #plan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        plan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}) return end
      end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

-- ---- the menu policy --------------------------------------------------------
local rows = {}          -- [boost] = { stamp, drawn, attr, nameAttr, mp }
local phase = "bank"     -- bank -> sweep -> cast -> done
local want, tick, held = 0, 0, nil
local castMp0, castF = nil, nil
local lastSig = nil

local function decide()
  if H.readByte(MENU) == 0 then return nil end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a ~= terraS then
    if st == ST_CMD then return "right" end        -- Fight -> Defend
    if st == ST_DEF then return "a" end
    return nil
  end
  if phase == "bank" then
    if bank(terraS) >= MAXB and st == ST_CMD then phase = "sweep"; want = 0
    else
      if st == ST_CMD then return "right" end
      if st == ST_DEF then return "a" end
      return nil
    end
  end
  if phase == "sweep" or phase == "cast" then
    if st == ST_CMD then
      if pend(terraS) < want then return "r" end
      if pend(terraS) > want then return "l" end
      local r, cur = cmdRow(terraS, CMD_MAGIC), H.readByte(CMDROW + terraS) & 3
      if cur ~= r then return cur < r and "down" or "up" end
      return "a"
    end
    -- back out to the command window whenever the pending is not yet the
    -- level being read: the summon row is the top of the Magic list, B does
    -- nothing there, and DOWN steps back into the spell grid, where B closes
    if st == ST_ESPER and pend(terraS) ~= want then return "down" end
    if st == ST_MAGIC and pend(terraS) ~= want then return "b" end
    if st == ST_MAGIC then return "up" end         -- the top of the list: summon
    if st == ST_ESPER then
      if phase == "sweep" then
        if rows[want] == nil then
          local w = findName()
          local drawn, attr, nameAttr
          if w then drawn, attr, nameAttr = drawnPrice(w) end
          rows[want] = { stamp = H.readByte(listBase(terraS) + 3), drawn = drawn,
                         attr = attr, nameAttr = nameAttr, mp = mp(terraS),
                         pend = pend(terraS), at = w }
          H.log(string.format("[phoenix] boost %d (pending %d): stamp %d, drawn %s, "
            .. "digit attr %s, name attr %s, TERRA %d MP, name at $%04X", want,
            pend(terraS), rows[want].stamp, tostring(drawn),
            attr and string.format("$%02X", attr) or "-",
            nameAttr and string.format("$%02X", nameAttr) or "-", mp(terraS), w or 0))
          H.screenshot(string.format("phoenixprice_b%d", want))
          if want < MAXB then want = want + 1 else phase = "cast" end
        end
        return "down"
      end
      castMp0 = castMp0 or mp(terraS)
      return "a"
    end
    if st == ST_TGT then return "a" end
    return nil
  end
  return nil
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.worldMode() and bright() >= 15 and H.worldHasControl()
    end, 6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    H.assertEq((H.readByte(0x1850 + TERRA) & 7) ~= 0, true, "TERRA is in the party")
    local old = H.readByte(ESPER_CELL)
    H.writeByte(ESPER_CELL, PHOENIX_ESPER)
    H.log(string.format("[phoenix] EXPEDIENT: TERRA's equipped esper $%02X -> $%02X "
      .. "(Phoenix); her pool %d MP", old, PHOENIX_ESPER, H.charMp(TERRA)))
    H.assertEq(H.readRomByte((H.sym("MagicProp") & 0x3FFFFF) + PHOENIX_REC * 14 + 5),
      PHOENIX_MP, "Phoenix's MagicProp record prices it at 110 MP")
    installObservers()
  end),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    local x, y = H.worldX(), H.worldY()
    home = { x, y }
    for dx = -8, 8, 2 do
      for dy = -8, 8, 2 do
        local p = H.worldBfs(x + dx, y + dy)
        if not away and p and #p >= 6 and #p <= 12 then away = { x + dx, y + dy } end
      end
    end
    assert(away, "a tile 6-12 steps from the Continue tile, on the settled map")
  end),
  lap(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == TERRA then terraS = s end
    end
    assert(terraS, "TERRA is in the battle")
    local b = listBase(terraS)
    H.log(string.format("[phoenix] TERRA slot %d: list row 0 = esper $%02X cost %d; "
      .. "%d MP, %d BP", terraS, H.readByte(b), H.readByte(b + 3), mp(terraS), bank(terraS)))
    H.assertEq(H.readByte(b), PHOENIX_ESPER, "TERRA's summon row is Phoenix")
    H.assertEq(mp(terraS) >= PHOENIX_MP, true,
      "TERRA's real pool pays Phoenix (so the charge can be measured)")
  end),
  H.driveUntil(function() return phase == "cast" and castF ~= nil and H.frame >= castF + 30 end,
    40000, {
    H.call(function()
      tick = tick + 1
      local ph = tick % 12
      if ph == 0 then
        held = decide()
        local sig = string.format("%s st=%02X actor=%d pend=%d bank=%d want=%d press=%s",
          phase, H.readByte(MSTATE), H.readByte(ACTOR) & 3, terraS and pend(terraS) or -1,
          terraS and bank(terraS) or -1, want, tostring(held))
        if sig ~= lastSig then lastSig = sig; H.log("[phoenix] f" .. H.frame .. " " .. sig) end
      end
      if castMp0 and not castF and mp(terraS) ~= castMp0 then castF = H.frame end
      H.setPad((held and ph < 6) and { [held] = true } or {})
    end),
  }, "the price sweep at boost 0..3 and a boost-3 Phoenix"),
  H.call(function()
    H.setPad({})
    local charged = castMp0 - mp(terraS)
    local qs = {}
    for _, q in ipairs(queued) do
      qs[#qs + 1] = string.format("[f%d %d cmd=$%02X atk=$%02X pend=%d]", q.f, q.v, q.cmd, q.atk, q.pend)
    end
    H.log("[phoenix] TERRA's cost-queue stores: " .. table.concat(qs, " "))
    H.log(string.format("[phoenix] cast at boost %d: MP %d -> %d, charged %d",
      MAXB, castMp0, mp(terraS), charged))
    for n = 0, MAXB do
      local r = rows[n]
      H.assertEq(r ~= nil, true, "the summon row was read at boost " .. n)
      local price = H.boostPrice(PHOENIX_MP, n)
      H.assertEq(price, PHOENIX_MP, "the rule: Phoenix costs 110 at boost " .. n)
      H.assertEq(r.pend, n, "pending boost " .. n .. " when the summon row was read")
      H.assertEq(r.stamp, price, "boost " .. n .. ": the row's stamped cost (what is charged)")
      H.assertEq(r.drawn, price, "boost " .. n .. ": the number the summon row prints")
      H.assertEq(r.attr, r.nameAttr, "boost " .. n .. ": the price is drawn in its row's colour")
      H.assertEq(r.attr, rows[0].attr, string.format(
        "boost %d: the row's colour matches boost 0's -- TERRA's %d MP pays %d at "
        .. "every level, so nothing greys and nothing whitens", n, r.mp, price))
    end
    local last = queued[#queued]
    H.assertEq(last ~= nil and last.cmd == 0x19, true,
      "TERRA's summon was queued (command $19)")
    H.assertEq(last.v, PHOENIX_MP, "the boost-3 summon was queued at 110")
    H.assertEq(charged, PHOENIX_MP, "and TERRA's pool lost 110: a boost never makes Phoenix cheaper")
  end),
})

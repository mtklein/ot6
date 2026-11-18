-- @suite savestate=worldmap_narshe
-- battle_lateboost: where the boost window closes.
--
-- A pick from a list freezes its boost (#555): the list draws the tier's
-- name, its price and its grey from the pending boost, and it stays on
-- screen, unchanged, through the target select, so a boost moved there
-- would cast and charge something the list did not show.  And at the target
-- select of a spell that can be spread over a group, L and R are FF6's
-- spread keys: the owner (v0.47) picked Fire 3 at two points, spread it with
-- L, and cast Fire 2 for one.  So once a row is picked from a list, Ot6Boost
-- leaves the pending boost alone at its target select (silently on a spread,
-- with the buzz elsewhere); an action picked straight off the command window
-- keeps L/R there (battle_spellboost case 4).
--
-- After the target is confirmed, points must not be taken either:
-- CreateAction has already frozen the tier, but Ot6ActionEnd charges
-- whatever pending reads when the action ends, so Ot6Boost gates on $32cc,y
-- = $ff, the actor's pending-action command-list pointer ($ff = nothing
-- queued).
--
-- This test pins the three moments: R in the list is the accepted spend
-- (Fire -> Fire 2, 20 MP against her real pool, a ching), R at the target
-- cursor after that pick moves nothing and makes no ching (#555), and R
-- after the confirm moves neither pending nor bp and stays silent; the cast
-- is the Fire 2 the list showed, charged the 1 point it used.  The bank is
-- earned (1 bp at open plus 1 regen from a real zero-MP Tonic turn = 2), so
-- bp 2 > pending 1 leaves headroom: a refused R can only be the gate under
-- test and not the bp cap.
--
-- On worldmap_narshe TERRA owns Magic with Fire, cast through the real
-- menu, cursor walking to Fire by real d-pad edges against the live
-- $8913/$8917/$891B bytes.
--
--   asserts: R on Fire in the list raises pending to 1 (and chings); the
--   target select opens with it at 1 and $32cc still $ff; R at the target
--   cursor leaves it at 1 with no ching; the committed action really freezes
--   ($32cc leaves $ff) with the menu still open; post-commit R moves neither
--   pending nor bp and stays silent; the list's spend folded the executed
--   spell (Fire -> Fire 2) and charged exactly the 1 point the fold used.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_MAGIC, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x0E, 0x38, 0x01
local CMD_MAGIC, CMD_ITEM = 0x02, 0x01
local FIRE, FIRE2, FIRE2_MP = 0x00, 0x05, 20
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function pend(s) return H.readByte(0x3e9d + s*2) end
local function bp(s) return H.readByte(0x3e9c + s*2) end
local function mp(s) return H.readWord(0x3c08 + s*2) end
local function cmdptr(s) return H.readByte(0x32cc + s*2) end
local function st() return H.readByte(MSTATE) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function spellIndexOf(slot, id)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[slot] + i*4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end

local terra, execd = nil, {}
local pendAtTarget, bpAtTarget
local ching, chingRef = 0, nil

-- The battle item-menu row of a zero-cost restorative to spend the banking
-- turn on (Tonic first, then Potion).  #143's mog-gear route unequips MOG's
-- Mithril Pike/Shld into the bag ahead of the consumables, so the Tonic is no
-- longer the top row: walk the cursor to it by id ($2686 is the menu-order
-- battle bag, stride 5: +0 id, +3 count) rather than to row 0.  The bag
-- has holes: a used-up stack leaves its row $FF (worldmap_narshe's draw
-- at 4748d741: "bag FF:0 E9:2 F6:3 ...", the Tonics spent), so every row
-- is read rather than stopping at the first empty one.
local function bankItemRow()
  for _, want in ipairs({ 0xE8, 0xE9 }) do
    for r = 0, 255 do
      if H.readByte(0x2686 + r * 5) == want and H.readByte(0x2686 + r * 5 + 3) > 0 then return r end
    end
  end
  return nil
end

-- bank one real Tonic turn (Locke defers with X); 6-on/24-off, because the
-- item window refuses a faster edge train
local mf = 0
local function bankDecide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  if (mf - 1) % 30 >= 6 then return {} end
  local act = H.readByte(ACTOR) & 3
  local s = st()
  if s == ST_TRANS then return {} end
  local btn
  if act ~= terra then
    btn = (s == ST_CMD) and "x" or "b"
  elseif s == ST_CMD then
    local want = cmdRowOf(terra, CMD_ITEM)
    local cur = H.readByte(CMDROW + terra) & 3
    if cur == want then btn = "a"
    else btn = (cur < want) and "down" or "up" end
  elseif s == ST_ITEM then
    local cur = H.readByte(0x8947 + terra) + H.readByte(0x894F + terra)
    local want = bankItemRow()
    if want == nil then btn = "b"
    elseif cur < want then btn = "down"
    elseif cur > want then btn = "up"
    else btn = "a" end
  elseif s == ST_TGT then
    btn = "a"
  else
    btn = "b"
  end
  return btn and { [btn] = true } or {}
end

local plan, idx, goal = nil, 1, { 82, 56 }

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then
        if H.worldX() == goal[1] and H.worldY() == goal[2] then
          goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
        end
        plan = H.worldBfs(goal[1], goal[2]); idx = 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
      end
      local dir = plan[idx]; idx = idx + 1
      if not dir then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, "grass-area encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot*2) == 0x00 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "TERRA is really in this party")
    H.assertEq(spellIndexOf(terra, FIRE) ~= nil, true,
      "her real list holds Fire")
    H.assertEq(mp(terra) >= FIRE2_MP, true,
      "the real pool pays the tier the accepted spend will buy")
    H.log(string.format("terra slot %d: bp=%d mp=%d", terra, bp(terra), mp(terra)))
  end),
  H.driveUntil(function() return bp(terra) >= 2 end, 20000, {
    H.call(function() H.setPad(bankDecide()) end),
  }, "second bp banked by a real Tonic turn"),
  -- her next window: walk to Magic, open the list, park the cursor on
  -- Fire by real d-pad edges against $8913/$8917/$891B
  H.driveUntil(function()
    if H.readByte(MENU) == 0 or (H.readByte(ACTOR) & 3) ~= terra then
      return false
    end
    if st() ~= ST_MAGIC then return false end
    local i = spellIndexOf(terra, FIRE)
    local absRow = H.readByte(0x8913 + terra) + H.readByte(0x891B + terra)
    return absRow == i // 2 and H.readByte(0x8917 + terra) == i % 2
  end, 20000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      mf = mf + 1
      if (mf - 1) % 8 >= 4 then H.setPad({}); return end
      local act = H.readByte(ACTOR) & 3
      local s = st()
      if s == ST_TRANS then H.setPad({}); return end
      local btn
      if act ~= terra then
        btn = (s == ST_CMD) and "x" or "b"
      elseif s == ST_CMD then
        local want = cmdRowOf(terra, CMD_MAGIC)
        local cur = H.readByte(CMDROW + terra) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif s == ST_MAGIC then
        local i = spellIndexOf(terra, FIRE)
        local wantRow, wantCol = i // 2, i % 2
        local absRow = H.readByte(0x8913 + terra) + H.readByte(0x891B + terra)
        local col = H.readByte(0x8917 + terra)
        if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
        elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left"
        else btn = nil end
      else
        btn = "b"
      end
      H.setPad(btn and { [btn] = true } or {})
    end),
  }, "her open list parked on Fire"),
  H.call(function()
    emu.addMemoryCallback(function(_, v) execd[#execd+1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    -- $6281 is the "ching" sfx request Ot6Boost fires on a committed
    -- boost; a refused press must stay silent
    chingRef = emu.addMemoryCallback(function(_, v)
      if v ~= 0 then ching = ching + 1 end
    end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  end),
  -- accepted: R on Fire in the open list buys Fire 2, which her pool pays
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.log(string.format("in the list on Fire: pend=%d bp=%d ching=%d", pend(terra), bp(terra), ching))
    H.assertEq(pend(terra), 1, "R on Fire in the list raises pending")
    H.assertEq(ching, 1, "...and the accepted boost chings")
  end),
  H.driveUntil(function() return st() == ST_TGT end, 600, {
    H.pressButtons({ "a" }, 6), H.waitFrames(24),
  }, "target select up"),
  H.call(function()
    H.assertEq(pend(terra), 1, "the pick carries its boost into target select")
    H.assertEq(cmdptr(terra), 0xff,
      "action still uncommitted at the target cursor ($32cc = $ff)")
  end),
  -- frozen (#555): the list's pick keeps the boost it showed
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    pendAtTarget, bpAtTarget = pend(terra), bp(terra)
    H.log(string.format("at target cursor after R: pend=%d bp=%d ching=%d",
      pendAtTarget, bpAtTarget, ching))
    H.assertEq(pendAtTarget, 1, "R at the target cursor of a list pick leaves the boost the list showed (#555)")
    H.assertEq(ching, 1, "...and makes no ching")
    H.assertEq(bpAtTarget > pendAtTarget, true,
      "bp headroom remains -- the refusals here can only be the gates under test")
  end),
  H.driveUntil(function() return st() ~= ST_TGT end, 600, {
    H.pressButtons({ "a" }, 6), H.waitFrames(24),
  }, "target confirmed"),
  H.call(function()
    H.assertEq(cmdptr(terra) ~= 0xff, true,
      "positive control: the action really did commit ($32cc left $ff)")
    H.assertEq(H.readByte(MENU) ~= 0, true,
      "positive control: the menu is still open, so input still reaches us")
  end),
  -- refused: the tier is frozen; these presses must buy and cost nothing
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.call(function()
    H.log(string.format("after post-confirm R x2: pend=%d bp=%d ching=%d",
      pend(terra), bp(terra), ching))
    H.assertEq(pend(terra), pendAtTarget,
      "NEGATIVE CONTROL: post-commit R does not raise pending")
    H.assertEq(bp(terra), bpAtTarget,
      "NEGATIVE CONTROL: post-commit R does not touch bp")
    H.assertEq(ching, 1, "NEGATIVE CONTROL: a refused boost makes no sound")
  end),
  H.waitUntil(function() return #execd > 0 end, 1800, "an action executed", 5),
  H.waitUntilSoft(function() return pend(terra) == 0 end, 1800,
    "pending consumed", 10),
  H.waitFrames(60),
  H.call(function()
    emu.removeMemoryCallback(chingRef, emu.callbackType.write, 0x7e6281, 0x7e6281)
    local ids = {}
    for _, v in ipairs(execd) do ids[#ids+1] = string.format("%02x", v) end
    H.log("executed attack ids: " .. table.concat(ids, " "))
    H.log(string.format("bp %d -> %d", bpAtTarget, bp(terra)))
    local folded = false
    for _, v in ipairs(execd) do if v == FIRE2 then folded = true end end
    H.assertEq(folded, true,
      "the list's spend DID fold the spell (Fire -> Fire 2)")
    -- charged for one point, which is what was delivered.
    H.assertEq(bp(terra), bpAtTarget - 1,
      "charged exactly the 1 point the fold used, no post-commit theft")
    H.assertEq(pend(terra), 0, "pending cleared after the action")
    H.screenshot("lateboost")
  end),
})

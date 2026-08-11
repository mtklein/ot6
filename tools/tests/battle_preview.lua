-- @suite savestate=worldmap_narshe
-- battle_preview: the un-made choice telegraphs its boost.  With BP
-- pending, opening Terra's magic list renders the folded tier in Fire's
-- row (Ot6PreviewList_ext folds the render-scoped id) — and since #64 the
-- rest of the row tells the same story: the PRICE is the folded tier's,
-- and the row GREYS when she cannot pay it.
--
-- WHY THE ROW HAD TO CATCH UP WITH THE NAME.  The preview shipped in v0.1
-- folding only the render-scoped id, with cost and selectability left on the
-- base spell.  That was fine while the fold also CHARGED the base spell.
-- #64 made the fold cost the tier's real MP, and the moment it did, a row
-- reading "Fire 3" beside Fire's 4 MP — and confirming happily however broke
-- Terra was — became the lying-surface class we have spent three releases
-- removing.  Ot6FoldPrices (ot6_boost.asm) moves spell-list byte 3, the one
-- cell the grey, the number, the confirm gate and GetMPCost all read, so the
-- four cannot disagree.
--
-- Issue #75 conversion.  On worldmap_narshe Terra really owns Magic with
-- Fire, so every write is gone: no guard stops, no bp/pending pokes, no
-- 300-MP solvency pumps, no 20-MP poverty pokes.  Her REAL pool is the
-- test's whole price ladder: 29 MP pays Fire's 4 and Fire 2's 20 but can
-- never pay Fire 3's 51 — so pending 2 is the grey phase for free, and
-- the grey provably marks the FOLD's price and not poverty (the same
-- wallet pays both cheaper tiers, asserted un-greyed either side of it).
-- The bank is earned: one real Tonic turn (zero MP, so the ladder's
-- arithmetic never moves) banks the second bp; pending only ever comes
-- from real R/L edges at her open list.  The one assertion that cannot
-- survive on real inputs is the old "a poked pending has not re-priced anything
-- yet" control — its subject was the poke itself.  Its replacement is the
-- pending-0 baseline read before any R edge: price 4, tier 1, ungreyed.
--
--   asserts: pending 0/1/2 render tier 1/2/3 with prices 4/20/51 live in
--   the same open list; the unaffordable folded row is greyed AND refuses
--   the confirm (state stays in-list, $32cc stays $ff); both cheaper
--   tiers stay ungreyed on the same wallet; the walk is self-restoring
--   and idempotent (L back down restores each price exactly); and the
--   menu still works — a re-folded cast lands at the tier the wallet
--   buys (Fire 2, $05).  Screenshots for the eyeball record.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_MAGIC, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x0E, 0x38, 0x01
local CMD_MAGIC, CMD_ITEM = 0x02, 0x01
local FIRE, FIRE2 = 0x00, 0x05
local FIRE_MP, FIRE2_MP, FIRE3_MP = 4, 20, 51   -- MagicProp+5;
                                     -- battle_foldcost.lua pins the ladder
local TONIC = 0xE8
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local function mp(slot) return H.readWord(0x3c08 + slot*2) end
local function cmdptr(slot) return H.readByte(0x32cc + slot*2) end

-- One magic-list ROW, read exactly the way the ROM reaches it: the master
-- spell list ($3084, spell id -> entry index) into the caster's own list
-- ($302c,entity -> $208e/$21ca/$2306/$2442), stride 4.  GetMPCost walks this
-- (battle_main.asm:13201-13210) and so does CheckMagicEnabled (:14692).
--   +0 id   +1 flags (bit 7 = disabled)   +2 targeting   +3 MP cost
local function row(slot, spellId)
  local idx = H.readByte(0x3084 + spellId)
  if idx == 0xff then return nil end
  return H.readWord(0x302c + slot * 2) + idx * 4
end
local function rowCost(slot, spellId)
  local r = row(slot, spellId)
  return r and H.readByte(r + 3)
end
local function rowGreyed(slot, spellId)
  local r = row(slot, spellId)
  return r and (H.readByte(r + 1) & 0x80) ~= 0
end

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

-- Fire's rendered tier in the ability-list staging rows (map rows 32+).
-- Names render spaces as $fe and pad with $ff: "Fire 2" = F,i,r,e,$fe,$b6
-- and plain "Fire" = F,i,r,e,$ff… — cell 4 being a true pad ($ff) also
-- cleanly excludes any stale "Fire Beam"-shaped rows (space+B).
local function fireTier()
  local vr = emu.memType.snesVideoRam
  for w = 0x400, 0x51c do
    local base = (0x7800 + w) * 2
    if emu.read(base, vr) == 0x85 and emu.read(base+2, vr) == 0xa2 and
       emu.read(base+4, vr) == 0xab and emu.read(base+6, vr) == 0x9e then
      local digit = nil
      for k = 4, 6 do
        local c = emu.read(base + k*2, vr)
        if c == 0xb6 then digit = 2 end
        if c == 0xb7 then digit = 3 end
      end
      if digit then return digit end
      if emu.read(base + 8, vr) == 0xff then return 1 end
    end
  end
  return 0
end

local terra, sawFold
local spells = {}

-- Drive L/R until the PENDING BOOST reaches `want`.
--
-- Deliberately NOT keyed on fireTier().  The list restages one row-pair per
-- frame (Ot6RestageGate_ext, ot6_hud.asm), so a VRAM read taken mid-cycle can
-- momentarily report a neighbouring tier -- measured: a `driveUntil fireTier()
-- == 2` loop reported itself satisfied after 4 frames without ever pressing
-- L, and every price assertion downstream then passed or failed for reasons
-- that had nothing to do with the price.  The pending byte is the ground
-- truth for "an L/R edge really happened", which is what these phases are
-- about; the rendered tier is then ASSERTED at each stop rather than waited
-- on, which is the stronger statement anyway.
local function boostTo(want, label)
  return H.driveUntil(function() return pend(terra) == want end, 3000, {
    H.call(function()
      local p = pend(terra)
      if p < want then H.setPad({ "r" })
      elseif p > want then H.setPad({ "l" }) end
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, label)
end

-- the banking machine: Locke defers with X, Terra takes one real Tonic
-- turn (zero MP -- the price ladder's arithmetic never moves), which with
-- the opening Ot6InitBP bp banks the 2 the pending phases need.
-- cadence note: the ITEM window refuses a 4-on/4-off edge train (measured:
-- 995 A presses at st=0a moved nothing) -- newFightDriver's 6-held pace is
-- the proven one, so the bank machine presses 6-on/24-off.
local mf = 0
local function bankDecide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  if (mf - 1) % 30 >= 6 then return {} end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local btn
  if act ~= terra then
    btn = (st == ST_CMD) and "x" or "b"
  elseif st == ST_CMD then
    local want = cmdRowOf(terra, CMD_ITEM)
    local cur = H.readByte(CMDROW + terra) & 3
    if cur == want then btn = "a"
    else btn = (cur < want) and "down" or "up" end
  elseif st == ST_ITEM then
    -- Tonic sits at bag index 0 (measured: E8 x5 heads the battle bag)
    local cur = H.readByte(0x8947 + terra) + H.readByte(0x894F + terra)
    if cur > 0 then btn = "up" else btn = "a" end
  elseif st == ST_TGT then
    btn = "a"
  else
    btn = "b"
  end
  if btn and (mf - 1) % 30 == 0 then
    H.log(string.format("bank: f%d st=%02x act=%d press %s (bp=%d cur=%d)",
      H.frame, st, act, btn, bp(terra),
      H.readByte(0x8947 + terra) + H.readByte(0x894F + terra)))
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
    H.assertEq(rowCost(terra, FIRE) ~= nil, true,
      "Terra's list really has a Fire row to price")
    -- the wallet facts the whole ladder leans on
    H.log(string.format("terra slot %d: bp=%d mp=%d", terra, bp(terra), mp(terra)))
    H.assertEq(mp(terra) >= FIRE2_MP, true, "the real pool pays Fire 2...")
    H.assertEq(mp(terra) < FIRE3_MP, true,
      "...but not Fire 3 -- the grey phase needs no poverty poke")
  end),
  -- bank the second bp with one real zero-MP Tonic turn
  H.driveUntil(function() return bp(terra) >= 2 end, 20000, {
    H.call(function() H.setPad(bankDecide()) end),
  }, "second bp banked by a real Tonic turn"),
  H.call(function()
    H.assertEq(bp(terra) >= 2, true, "bp 2 banked (1 open + 1 real action)")
    H.assertEq(mp(terra) >= FIRE2_MP, true,
      "and the bank cost no MP -- the ladder's wallet is untouched")
  end),
  -- wait for her next window and park her open list's cursor on Fire
  H.driveUntil(function()
    if H.readByte(MENU) == 0 then return false end
    if (H.readByte(ACTOR) & 3) ~= terra then return false end
    if H.readByte(MSTATE) ~= ST_MAGIC then return false end
    local i = spellIndexOf(terra, FIRE)
    local absRow = H.readByte(0x8913 + terra) + H.readByte(0x891B + terra)
    return absRow == i // 2 and H.readByte(0x8917 + terra) == i % 2
  end, 20000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      mf = mf + 1
      if (mf - 1) % 8 >= 4 then H.setPad({}); return end
      local act = H.readByte(ACTOR) & 3
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      local btn
      if act ~= terra then
        btn = (st == ST_CMD) and "x" or "b"
      elseif st == ST_CMD then
        local want = cmdRowOf(terra, CMD_MAGIC)
        local cur = H.readByte(CMDROW + terra) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then
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
  H.waitFrames(30),
  -- ------------------------------------------------ pending 0: the baseline --
  -- the input-driven replacement for the old poked-pending control: before any R
  -- edge the row must carry Fire's own name and price, ungreyed.
  H.call(function()
    H.assertEq(pend(terra), 0, "no pending before any R edge")
    H.log(string.format("baseline: tier %d, price %d MP", fireTier(),
      rowCost(terra, FIRE)))
    H.assertEq(fireTier(), 1, "unboosted list renders plain Fire")
    H.assertEq(rowCost(terra, FIRE), FIRE_MP, "priced at Fire's own 4")
    H.assertEq(rowGreyed(terra, FIRE), false,
      "and an unboosted Fire is affordable, so it is not greyed")
    H.screenshot("preview_list")
  end),
  -- ------------------------------- the list is open: real L/R edges re-fold --
  -- Each stop asserts BOTH halves of the row: the name the player reads and
  -- the price the game will charge.  Before #64 only the first moved.
  boostTo(1, "R raises the pending to 1"),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("pending 1: Fire's row renders tier %d, prices %d MP",
      fireTier(), rowCost(terra, FIRE)))
    H.assertEq(fireTier(), 2, "one boost re-folds the NAME to Fire 2, live")
    -- and the price, live in the same open list.  Ot6Boost sets OT6_RESTAGE
    -- for the name AND bit 7 of $3204 for the price; the main loop's
    -- `asl $3204,x / bcc / jsr UpdateEnabledMagic` (battle_main.asm:1367-1369)
    -- runs the walk.  That the recheck lands WITH A LIST OPEN is the thing
    -- this assert really establishes -- it is the whole live half of #64.
    H.assertEq(rowCost(terra, FIRE), FIRE2_MP,
      "...and PRICES it as Fire 2 -- 20 MP, not Fire's 4")
    H.assertEq(rowGreyed(terra, FIRE), false,
      "a solvent caster's folded row is NOT greyed")
  end),
  boostTo(2, "R climbs to 2"),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("pending 2: tier %d, price %d MP, greyed=%s (mp=%d)",
      fireTier(), rowCost(terra, FIRE), tostring(rowGreyed(terra, FIRE)),
      mp(terra)))
    H.assertEq(fireTier(), 3, "two boosts preview Fire 3")
    H.assertEq(pend(terra), 2, "still just a preview: boost not consumed")
    H.assertEq(rowCost(terra, FIRE), FIRE3_MP,
      "...priced as Fire 3 -- 51 MP")
    -- #64's GREY, on the REAL wallet: 29 MP pays base Fire and Fire 2 but
    -- not Fire 3, so the grey is about the FOLD and not about being broke.
    -- bit 7 of list entry+1 is the bit GetTextColor turns into the $04 the
    -- drawer ORs into the row's $21 white palette to make $25 grey
    -- (btlgfx_main.asm:11271-11278, :10704) AND the bit the A-button
    -- refuses on (:19659-19663).
    H.assertEq(rowGreyed(terra, FIRE), true,
      "the real pool cannot pay Fire 3's 51, so the boosted row is greyed")
    H.screenshot("preview_grey")
  end),
  -- ...and the refusal is behavioral, not just a palette bit: A on the
  -- greyed row must leave the list open and commit nothing.
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_MAGIC,
      "A on the greyed folded row is refused -- the list stays open")
    H.assertEq(cmdptr(terra), 0xff,
      "and nothing was committed ($32cc still $ff)")
  end),
  boostTo(1, "L drops back to 1 (the recheck must un-grey, live)"),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(rowCost(terra, FIRE), FIRE2_MP, "re-priced as Fire 2")
    H.assertEq(rowGreyed(terra, FIRE), false,
      "...and un-greyed: the SAME wallet pays Fire 2, so the grey was the "
      .. "fold's price and not the caster's poverty (live both ways)")
  end),
  boostTo(0, "L drops the pending to 0"),
  H.waitFrames(40),
  H.call(function()
    -- THE FALLBACK.  Ot6FoldPrices recomputes absolutely from MagicProp every
    -- pass rather than mutating the previous value, so 0 tier steps restores
    -- the base price by the same code path that raised it.  There is no
    -- stale folded price that can leak into the next turn.
    H.log(string.format("pending 0: Fire's row renders tier %d, prices %d MP",
      fireTier(), rowCost(terra, FIRE)))
    H.assertEq(fireTier(), 1, "no boost re-folds the NAME back to plain Fire")
    H.assertEq(rowCost(terra, FIRE), FIRE_MP,
      "...and restores Fire's own 4 MP -- the walk is self-restoring")
    H.assertEq(rowGreyed(terra, FIRE), false, "and stays ungreyed")
  end),
  boostTo(1, "R climbs back to 1"),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(pend(terra), 1, "round trip landed back on 1 pending")
    H.assertEq(fireTier(), 2, "and the settled list reads Fire 2")
    H.assertEq(rowCost(terra, FIRE), FIRE2_MP,
      "...priced as Fire 2 again -- the round trip is idempotent")
    H.assertEq(rowGreyed(terra, FIRE), false, "and affordable, so ungreyed")
    H.screenshot("preview_live")
    emu.addMemoryCallback(function(addr, value)
      spells[#spells + 1] = value
      if value == FIRE2 then sawFold = true end
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- the menu must still be fully functional: confirm the (re-folded) fire
  -- and a target, and the fold lands at execution -- at the tier the
  -- wallet buys
  H.driveUntil(function() return pend(terra) == 0 end, 4000, {
    H.call(function() if pend(terra) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "cast lands after live re-folds"),
  H.waitFrames(60),
  H.call(function()
    local vals = {}
    for _, v in ipairs(spells) do vals[#vals + 1] = string.format("%02x", v) end
    H.log("spells executed: " .. table.concat(vals, " "))
    H.assertEq(sawFold, true, "a re-folded spell executed at its tier ($05)")
  end),
})

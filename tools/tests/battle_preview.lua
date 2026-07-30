-- @suite
-- battle_preview: the un-made choice telegraphs its boost. With 2 BP
-- pending, opening Terra's magic list renders "Fire 3" in Fire's row
-- (Ot6PreviewList_ext folds the render-scoped id) — and since #64 the
-- rest of the row tells the same story: the PRICE is Fire 3's, and the row
-- GREYS when she cannot pay it.
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
--   asserts: with pending=2 the open list shows Fire's name with a '3';
--   the list price for Fire's row reads Fire 3's 51 and falls back to
--   Fire's 4 when L takes the boost away, live, in the same open list;
--   a caster who cannot pay the folded tier has that row marked disabled
--   (the bit GetTextColor turns into the grey palette) while the unboosted
--   row stays enabled; and the menu still works — a re-folded cast lands.
--   Screenshots for the eyeball record.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local terra, sawFold

local FIRE, FIRE3 = 0x00, 0x09
local FIRE_MP, FIRE2_MP, FIRE3_MP = 4, 20, 51   -- MagicProp+5;
                                     -- battle_foldcost.lua pins the ladder

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


local function findTerra()
  for slot = 0, 3 do
    if H.readByte(0x3ed8 + slot*2) == 0 then return slot end
  end
end

-- Fire's rendered tier in the ability-list staging rows (map rows 32+).
-- Names render spaces as $fe and pad with $ff: "Fire 2" = F,i,r,e,$fe,$b6
-- and plain "Fire" = F,i,r,e,$ff… — cell 4 being a true pad ($ff) also
-- cleanly excludes the magitek list's stale "Fire Beam" rows (space+B).
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
local function fire3InList() return fireTier() == 3 end

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

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    terra = findTerra()
    H.log("terra is slot " .. terra)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)  -- stop the guards
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
  end),
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == terra
  end, 10000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= terra then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "terra's menu up"),
  H.call(function()
    H.writeByte(0x3e9c + terra*2, 3)
    H.writeByte(0x3e9d + terra*2, 2)
    -- #64: solvent for the price phases, so a greyed row can only mean the
    -- fold priced it.  The grey phase below takes this away again on purpose.
    H.writeWord(0x3c30 + terra*2, 300)
    H.writeWord(0x3c08 + terra*2, 300)
    H.assertEq(rowCost(terra, FIRE) ~= nil, true,
      "Terra's list really has a Fire row to price")
  end),
  -- the cursor's start row and any stray-open list are mint-dependent, so
  -- walk by goal: close whatever's open, step one row, open, and check
  -- for the folded name — converges from any start state within a lap
  H.driveUntil(function() return fire3InList() end, 4000, {
    H.call(function() if not fire3InList() then H.setPad({ "b" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
    H.call(function() if not fire3InList() then H.setPad({ "down" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
    H.call(function() if not fire3InList() then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(34),
  }, "list shows Fire 3 preview"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(fire3InList(), true, "boosted list previews Fire 3")
    H.assertEq(pend(terra), 2, "still just a preview: boost not consumed")
    -- #64 BASELINE, and the non-vacuity control for every price assert below.
    -- The pending above was POKED into $3e9d, not pressed: Ot6Boost never
    -- ran, so nothing asked for the magic recheck that folds the prices, and
    -- the row still carries Fire's own 4.  That is correct -- the re-price is
    -- driven by the L/R edge, which is the only way a real player ever gets a
    -- pending boost -- and it means the 20 / 4 / 51 ladder below cannot be
    -- passing on a price that was already there.
    H.log(string.format("Fire's row prices at %d MP (pending poked, not "
      .. "pressed: no recheck requested yet)", rowCost(terra, FIRE)))
    H.assertEq(rowCost(terra, FIRE), FIRE_MP,
      "a poked pending has not re-priced anything yet (the control)")
    H.screenshot("preview_list")
  end),
  -- ------------------------------- the list is still open: L/R re-fold it --
  -- Each stop asserts BOTH halves of the row: the name the player reads and
  -- the price the game will charge.  Before #64 only the first moved.
  boostTo(1, "L drops the pending to 1"),
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
    H.assertEq(rowGreyed(terra, FIRE), false,
      "and an unboosted Fire is affordable, so it is not greyed")
  end),
  boostTo(2, "R climbs back to 2"),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(pend(terra), 2, "round trip landed back on 2 pending")
    H.assertEq(fireTier(), 3, "and the settled list reads Fire 3")
    H.assertEq(rowCost(terra, FIRE), FIRE3_MP,
      "...priced as Fire 3 again -- the round trip is idempotent")
    H.assertEq(rowGreyed(terra, FIRE), false,
      "a solvent caster's folded row is NOT greyed")
    H.screenshot("preview_live")
  end),

  -- --------------------------------------- #64: and the GREY follows too --
  -- Take the pool away.  Terra can pay Fire's 4 but not Fire 3's 51, so the
  -- boosted row must go disabled: bit 7 of list entry+1, which is the bit
  -- GetTextColor turns into the $04 the drawer ORs into the row's $21 white
  -- palette to make $25 grey (btlgfx_main.asm:11271-11278, :10704) AND the
  -- bit the A-button refuses on (:19659-19663).  Without it the list offers
  -- a cast the universal insufficient-MP gate then fizzles -- exactly the
  -- lying surface #64 says not to ship.
  --
  -- 20 MP is chosen to separate the two answers: it pays base Fire and not
  -- Fire 3, so the grey is about the FOLD and not about being broke.
  H.call(function() H.writeWord(0x3c08 + terra*2, 20) end),
  boostTo(1, "L to 1 (forces a recheck against the new pool)"),
  boostTo(2, "R back to 2"),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("poor Terra: mp=%d, Fire's row costs %d, greyed=%s",
      H.readWord(0x3c08 + terra*2), rowCost(terra, FIRE),
      tostring(rowGreyed(terra, FIRE))))
    H.assertEq(rowCost(terra, FIRE), FIRE3_MP, "still priced as Fire 3")
    H.assertEq(rowGreyed(terra, FIRE), true,
      "20 MP cannot pay Fire 3's 51, so the boosted row is greyed/refused")
    H.screenshot("preview_grey")
  end),
  boostTo(0, "L all the way back to unboosted"),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(rowCost(terra, FIRE), FIRE_MP, "priced as Fire again")
    H.assertEq(rowGreyed(terra, FIRE), false,
      "...and un-greyed: the SAME 20 MP pays base Fire, so the grey was the "
      .. "fold's price and not the caster's poverty")
  end),

  -- put her back in funds and re-boost, so the confirm below is testing the
  -- menu rather than the refusal we just proved works
  H.call(function() H.writeWord(0x3c08 + terra*2, 300) end),
  boostTo(2, "R back to 2 with a full pool"),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(rowGreyed(terra, FIRE), false,
      "refunding the pool un-greys the folded row (the recheck is live both "
      .. "ways, not a one-shot)")
    emu.addMemoryCallback(function(addr, value)
      if value == 0x09 or value == 0x2f then sawFold = true end
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- the menu must still be fully functional: confirm the (re-folded)
  -- fire and a target, and the fold lands at execution
  H.driveUntil(function() return pend(terra) == 0 end, 4000, {
    H.call(function() if pend(terra) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  }, "cast lands after live re-folds"),
  H.waitFrames(60),
  H.call(function()
    -- the cursor rests wherever the walk left it: Cure and Fire both
    -- fold, and either tier-3 executing proves the post-refold cast
    H.assertEq(sawFold, true, "a re-folded spell executed at tier 3")
  end),
})

-- @suite
-- battle_boost: L/R boost-select in the battle menu, end to end.
--   R raises the active character's pending boost (cap 3, never past bp),
--   L lowers it, the party-window pip cell tracks live, and the boosted
--   action consumes the points (and skips that turn's +1 regen).
--   ...and the repaint request that press raises (OT6_RESTAGE) is spent or
--   dropped rather than left standing (see the first R press below).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local MSTATE, RESTAGE = 0x7BC2, 0x57D4   -- menu state; the gate's request byte
local ST_CMD = 0x05                      -- the battle command window
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local actor
local cellSeen, cellFrames = {}, 0
local markSeen, parkFrames = {}, 0
local restageTrace = {}                  -- OT6_RESTAGE, sampled per frame

-- sfx request counters: boost feedback must be audible. Each request is an
-- inc (nonzero write) consumed by UpdateSfx's stz, so count nonzero writes.
local sfx = { ching = 0, click = 0, error = 0 }
local sfxRefs = {}
local function sfxWatch()
  sfxRefs[1] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x7e6281 then sfx.ching = sfx.ching + 1 end
  end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  -- $94/$95 are direct-page writes: the cpu issues them in bank 0's wram
  -- mirror, so the callback must watch $000094, not $7e0094
  sfxRefs[2] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x000094 then sfx.click = sfx.click + 1 end
    if addr == 0x000095 then sfx.error = sfx.error + 1 end
  end, emu.callbackType.write, 0x000094, 0x000095)
end
local function sfxUnwatch()
  emu.removeMemoryCallback(sfxRefs[1], emu.callbackType.write, 0x7e6281, 0x7e6281)
  emu.removeMemoryCallback(sfxRefs[2], emu.callbackType.write, 0x000094, 0x000095)
end
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  -- every character opens with 1 bp (Ot6InitBP) and an unboosted action
  -- regens +1 (Ot6ActionEnd), so the first slot whose menu opens takes two
  -- real actions and arrives at this test's window holding 3.  The submit
  -- is driven by menu state ($7BC2) rather than by a fixed button
  -- sequence.  The bank action is the row-2 beam (Heal Force, row 3, is
  -- priced out of the opening MP).  The item window fails two ways: the
  -- intro bag is empty, and Wait mode stops time while a list is open, so
  -- holding A in state $0a freezes the fight.  Any other ready character
  -- defers focus with X, vanilla's own turn-cycling key.  Two beams into
  -- shielded guards cannot end the fight (shielded damage is halved), and
  -- each is an ordinary unboosted action worth +1 bp (Ot6ActionEnd), twice,
  -- on top of the 1 bp the actor opened with (Ot6InitBP).  $01 is
  -- transitional, so the driver leaves the pad alone; anything unknown
  -- gets B to back out.
  (function()
    local mf, downs = 0, 0
    return H.driveUntil(function()
      if H.readByte(0x7bca) == 0 then return false end
      local act = H.readByte(0x62ca)
      if actor == nil then
        actor = act
        H.log("banking bp on the first active slot: " .. actor)
      end
      return act == actor and bp(actor) >= 3
    end, 12000, {
      H.call(function()
        if H.readByte(0x7bca) == 0 then mf, downs = 0, 0; H.setPad({}); return end
        local act = H.readByte(0x62ca)
        if actor ~= nil and act == actor and bp(actor) >= 3 then
          H.setPad({}); return
        end
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local st = H.readByte(0x7bc2)
        local btn
        if actor ~= nil and act ~= actor then
          btn = st == 0x05 and "x" or "b"   -- defer focus; back out first
        elseif st == 0x05 then btn = "a"    -- open the magitek list
        elseif st == 0x2a then
          if downs < 2 then
            if (mf - 1) % 8 == 0 then downs = downs + 1 end
            btn = "down"
          else btn = "a" end                -- the row-2 beam
        elseif st == 0x38 then btn = "a"    -- confirm the default target
        -- (an offensive confirm defaults to the enemy-side pick, never the
        -- party, and this fixture stages one monster)
        elseif st == 0x01 then H.setPad({}); return
        else btn = "b" end
        if (mf - 1) % 8 == 0 then
          H.log(string.format("bank: f%d st=%02x press %s (act=%d bp=%d)",
            H.frame, st, btn, act, bp(act)))
        end
        H.setPad({ [btn] = true })
      end),
    }, "bank 3 bp by real beam turns")
  end)(),
  H.call(function()
    H.assertEq(bp(actor), 3, "3 bp banked by real turns (1 open + 2 regen)")
    H.log(string.format("banked: slot %d bp=%d hp %d %d %d", actor, bp(actor),
      H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8)))
    sfxWatch()
  end),
  -- The first R press, sampled per frame.
  --
  -- Ot6Boost's @refold arm raises OT6_RESTAGE = $80 on every L/R edge,
  -- whatever window is up (ot6_hud.asm, `sta OT6_RESTAGE ; open lists
  -- re-fold their names`), because the two windows that draw a folded name
  -- have to redraw it.  Here no such window is open: the press lands at the
  -- command window ($7bc2 = $05), so nothing can consume the request.
  --
  -- Ot6RestageGate_ext is polled once per battle frame from bank C1's frame
  -- loop (btlgfx_main.asm:1749).  It early-outs in ~14 cycles while the byte
  -- is zero and takes ~40 while a request stands, and the battle loop's
  -- per-iteration budget is close enough to full that the difference costs a
  -- missed vblank per battle-loop iteration for the rest of the menu.
  --
  -- The trace below is the discriminator: a single reading cannot tell
  -- "spent" from "never raised", because both are 0.  The values in between
  -- are the signal.
  H.call(function()
    restageTrace = {}
    H.assertEq(H.readByte(RESTAGE), 0,
      "no repaint request is outstanding before the press")
  end),
  H.hold({ r = true }),
  H.repeatN(6, {
    H.call(function() restageTrace[#restageTrace + 1] = H.readByte(RESTAGE) end),
    H.waitFrames(1),
  }),
  H.release(),
  H.repeatN(22, {
    H.call(function() restageTrace[#restageTrace + 1] = H.readByte(RESTAGE) end),
    H.waitFrames(1),
  }),
  H.call(function()
    local seen, sawFresh = {}, false
    for _, v in ipairs(restageTrace) do
      seen[#seen + 1] = string.format("%02x", v)
      if v == 0x80 then sawFresh = true end
    end
    H.log(string.format("[#87] restage across the press: %s -> %02x "
      .. "(mstate=%02x next=%02x)", table.concat(seen, " "),
      H.readByte(RESTAGE), H.readByte(MSTATE), H.readByte(MSTATE + 1)))
    -- positive control: the press has to have reached Ot6Boost at all.  The
    -- pending bank and the request are the same instruction stream, so a
    -- pending of 1 proves the request was raised even on a build that then
    -- drops it, and it is the original assertion of this step.
    H.assertEq(pend(actor), 1, "R raises pending to 1")
    H.assertEq(H.readByte(MSTATE), ST_CMD,
      "the press landed at the command window, where no list can consume a "
      .. "repaint request")
    H.assertEq(sawFresh, true,
      "and the fresh request ($80) was visible in the trace, so this step "
      .. "cannot pass by the raise having been removed")
    H.assertEq(H.readByte(RESTAGE), 0, string.format(
      "#87: the request is gone 28 frames later (trace %s).  A request no "
      .. "open window can consume must be dropped, not held: the gate's long "
      .. "path is ~26 cycles more than its idle path and it runs once per "
      .. "battle frame, which is a missed vblank per battle-loop iteration "
      .. "for the rest of the menu (see battle_trueknight phase 4b)",
      table.concat(seen, " ")))
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() H.assertEq(pend(actor), 3, "pending reaches 3") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 3, "cap: spend at most 3 (and never past bp)")
  end),
  -- live cell while boosting: the arrow-3 glyph, pulsing yellow and white, in
  -- both window bands (rows 1+2r and 9+2r; the visible copy alternates).
  -- This is a temporal sample, because single frames cannot see a pulse or a
  -- strobe.  The same window checks that the retired over-character sprite
  -- mark stays retired: oam entry 96+slot must remain parked (y $e0).  It used
  -- to carry the pending-3 tile $cc at attr $36, out of obj tiles that are
  -- vanilla's damage-numeral vram, which caused the bug where chevrons turned
  -- into numbers; battle_dmgnum.lua is the dedicated test.
  H.waitUntil(function()
    local reg = H.readByte(0x897f)
    local base = ((reg - (reg % 4)) * 256) * 2
    local row
    for r = 0, 3 do if H.readByte(0x64d6 + r) == actor then row = r end end
    local lo = emu.readWord(base + (1 + row*2)*0x40 + 40, emu.memType.snesVideoRam)
    local hi = emu.readWord(base + (9 + row*2)*0x40 + 40, emu.memType.snesVideoRam)
    cellSeen[lo] = (cellSeen[lo] or 0) + 1
    if hi ~= lo then cellSeen[hi] = (cellSeen[hi] or 0) + 1 end
    local oam = 0x0300 + (96 + actor) * 4
    local key = string.format("%02x/%02x/y%s", H.readByte(oam + 2),
      H.readByte(oam + 3), H.readByte(oam + 1) < 0xe0 and "on" or "off")
    markSeen[key] = (markSeen[key] or 0) + 1
    cellFrames = cellFrames + 1
    return cellFrames >= 40
  end, 160, "arrow pulse sampled", 1),
  H.call(function()
    local parts = {}
    for w, n in pairs(cellSeen) do
      parts[#parts + 1] = string.format("%04x x%d", w, n)
    end
    H.log("boost cell words seen: " .. table.concat(parts, ", "))
    H.assertEq(cellSeen[0x216d] ~= nil, true, "arrow-3 in white seen")
    H.assertEq(cellSeen[0x296d] ~= nil, true, "arrow-3 in yellow seen (pulse alive)")
    for w in pairs(cellSeen) do
      H.assertEq(w == 0x216d or w == 0x296d, true,
        string.format("only arrow-3 words in the live cell, both row ranges (got %04x)", w))
    end
    local mparts, other = {}, 0
    for k, n in pairs(markSeen) do
      mparts[#mparts + 1] = k .. " x" .. n
      -- tile/attr bytes are vanilla's leftovers now; only whether the entry
      -- is on screen matters, and it never may be
      if k:sub(-3) == "yon" then other = other + n end
    end
    H.log("sprite mark states seen: " .. table.concat(mparts, ", "))
    H.assertEq(other, 0,
      "the retired boost-mark oam entry stays parked and unused")
  end),
  H.pressButtons({ "l" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 2, "L lowers pending")
    sfxUnwatch()
    H.log(string.format("sfx: ching=%d click=%d error=%d",
      sfx.ching, sfx.click, sfx.error))
    H.assertEq(sfx.ching, 3, "each committed boost chings")
    H.assertEq(sfx.error, 1, "the denied 4th R buzzes")
    H.assertEq(sfx.click, 1, "L takeback clicks")
    H.screenshot("boost_selected")
  end),
  -- fire the boosted action; drive by menu state until it lands
  H.driveUntil(function() return bp(actor) ~= 3 end, 10000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "boosted action lands"),
  H.call(function()
    -- 3 bp - 2 spent, no regen on a boosted turn
    H.assertEq(bp(actor), 1, "boost consumed (3-2), regen skipped")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
  end),
  -- with no pending left, the mark must leave the field (parked at $e0)
  H.waitUntil(function()
    parkFrames = (parkFrames or 0) + 1
    return parkFrames >= 20 and H.readByte(0x0300 + (96 + actor)*4 + 1) == 0xe0
  end, 300, "mark parked after the action", 1),
})

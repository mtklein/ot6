-- probe_iaf.lua -- the airship-driver: drive the Thamasa stop line all the
-- way into the IAF's first battle (formation 126), headless, and confirm
-- the survey's offline formation decode live.
--
-- THE ENTRY CHAIN (all driven and asserted below):
--   1. BOARD: from the stop line (world (249,128), party of 4), nudge UP onto
--      the airship tile (249,127) and press A. Because $009D=1 && $009E=0 the
--      AirshipGround handler (no coord gate) diverts straight into the
--      FC-discovery cutscene -- no fly-to-a-spot needed.
--   2. DISCOVERY: a ~6500-frame auto-cutscene that ends on the Blackjack DECK
--      (map 6) and sets $009E=1.
--   3. HELM: walk onto the helm step-trigger at deck (14,6)/(15,8) -> dlg $0527;
--      pick option 0 "Find the Floating Continent".
--   4. PARTY-SELECT: `party_menu 1, RESET` (menu/party.asm, ZMENUSTATE $26)
--      empties the party; the FC needs EXACTLY 3 ($01A2=1 in _ca5817). It is
--      FF6's swap/arrange UI: a RESERVE column ($4a=0) and a GROUP 2x2
--      ($4a=$10: idx $10=g0/TL, $11=g1/BL, $12=g2/TR, $13=g3/BR; left/right
--      swap columns, up/down swap rows). Grab a reserve char (A in state $2d),
--      move into the group column and to the first empty slot, place (A in
--      $2e -- placing writes $7e9d99; A on an already-placed char opens Status,
--      the trap to avoid). Fill 3 slots, then START confirms (_c37296).
--   5. IAF: -> ambush -> dlg $084F -> battle 126, formation 175/176
--      (Sky Armor $043 + Spit Fire $0e3), which we read live and assert.

local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function idx() return H.readByte(0x4b) + H.readByte(0x4a) + H.readByte(0x5a) end
local function charAt(i) return rd(0x7e9d89 + i) end
local function grpCount()
  local n = 0
  for i = 0, 3 do if rd(0x7e9d99 + i) ~= 0xFF then n = n + 1 end end
  return n
end
local function firstEmptyGroupSlot()
  for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do if charAt(i) == 0xFF then return i end end
  return nil
end
-- edge-press one button per ~9-frame phase so the menu registers discrete taps
local phase = 0
local function tap(btn) phase = (phase + 1) % 9; H.setPad(phase < 3 and { btn } or {}) end

H.run({ maxFrames = 14000 }, {
  H.loadState("build/states/thamasa_done.mss.lua"),
  H.driveUntil(function() return H.worldHasControl() end, 3000, {}, "world control"),
  -- 0. stop-line preconditions
  H.call(function()
    H.assertEq(H.worldX(), 249, "stop-line world X = 249")
    H.assertEq(H.worldY(), 128, "stop-line world Y = 128")
    H.assertEq(sw(0x009D), 1, "$009D=1 -- control on the WoB map post-massacre")
    H.assertEq(sw(0x009E), 0, "$009E=0 -- FC not yet discovered")
  end),
  -- 1. board: up onto the airship tile (249,127), then A
  H.hold({ "up" }), H.waitFrames(12), H.release(), H.waitFrames(6),
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  -- 2. ride the discovery cutscene until $009E flips (advance any dialogs)
  H.driveUntil(function() return sw(0x009E) == 1 end, 10000, {
    H.call(function() H.setPad(H.dialogWaiting() and (H.frame % 24 < 4 and { "a" } or {}) or {}) end)
  }, "FC discovery ($009E=1)"),
  H.call(function()
    H.assertEq(H.readWord(0x1f64) & 0x3ff, 6, "landed on the Blackjack deck (map 6)")
  end),
  -- 3. helm step-trigger -> dlg $0527; pick "Find the Floating Continent"
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  -- 4. wait for the party-select menu, then build a 3-char group and confirm
  H.driveUntil(function() local s = H.readByte(0x26); return s >= 0x2c and s <= 0x2f end, 1200, {
    H.call(function() H.setPad(H.dialogWaiting() and (H.frame % 16 < 4 and { "a" } or {}) or {}) end)
  }, "party-select menu"),
  H.driveUntil(function() return grpCount() >= 3 end, 3000, {
    H.call(function()
      local s = H.readByte(0x26)
      if s == 0x2d then                    -- not holding: reach the reserve, grab a char
        if H.readByte(0x4a) ~= 0 then tap("up")
        elseif charAt(idx()) == 0xFF then tap("right")   -- scan the reserve for a char
        else tap("a") end
      elseif s == 0x2e then                -- holding: place in the first empty group slot
        if H.readByte(0x4a) ~= 0x10 then tap("down")     -- into the group column
        else
          local tgt = firstEmptyGroupSlot()
          if not tgt then tap("a") else
            local cc, cr = (idx() >> 1) & 1, idx() & 1
            local tc, tr = (tgt >> 1) & 1, tgt & 1
            if cc < tc then tap("right") elseif cc > tc then tap("left")
            elseif cr < tr then tap("down") elseif cr > tr then tap("up")
            else tap("a") end
          end
        end
      else tap("b") end                    -- escape a stray Status screen
    end)
  }, "3-char group formed"),
  H.driveUntil(function() return H.battleLoadStarted() end, 1500, {
    H.call(function()
      local s = H.readByte(0x26)
      if s == 0x2d then tap("start")
      elseif s == 0x2e or s == 0x2f then tap("b")
      elseif H.dialogWaiting() then H.setPad(H.frame % 8 < 4 and { "a" } or {})
      else tap("b") end
    end)
  }, "IAF battle 126"),
  -- 5. read the IAF formation live and assert the survey's decode
  H.waitFrames(40),
  H.call(function()
    local f = H.formationWords()
    local set = {}
    for _, s in ipairs(f) do set[s] = true end
    H.log(string.format("IAF battle 126: species=%s",
      table.concat({ f[1] or "?", f[2] or "?", f[3] or "?", f[4] or "?" }, ",")))
    -- formation 175/176 = Sky Armor ($043) + Spit Fire ($0e3), per the survey
    H.assertEq(set[0x043] and true or false, true, "Sky Armor ($043) present in the IAF wave")
    H.assertEq(set[0x0e3] and true or false, true, "Spit Fire ($0e3) present in the IAF wave")
    H.screenshot("iaf_battle126")
  end),
  H.logStep(function() return "airship-driver reached IAF battle 126; formation confirmed" end),
})

-- gen_wor_nikeah.lua -- the World of Ruin from Tzen to Nikeah's door:
-- cold-Continue the `wor-sabin-v1` battery (CELES and SABIN at world
-- (131,179), outside Tzen), walk north across the continent -- the plains,
-- the grass and plains north-east and north, and the Black Drgn's desert,
-- which no on-foot path avoids -- fighting everything that comes, and save
-- one step east of Nikeah's door, (148,76): the `wor-nikeah-v1` battery,
-- the boot for Nikeah, the ship and South Figaro.  Generates
-- wor_nikeah.mss, and its capture run (OT6_CAPTURE_SRM) cuts
-- `wor-nikeah-v1`.  docs/design/route-wor-edgar.md has the plan (sections
-- 2.2, 3.1, 5, 7) and what this measured (section 10).
--
-- The route:
--   1. The pools: every group the walk can roll, read from the ROM
--      (H.worldPathGroups) and asserted to deal only species with
--      authored break rows designed for this party (DESIGNED) -- the
--      plains' (route-wor-sabin 8.3), north of Tzen's (route-wor-edgar
--      8.2) and the Black Drgn.
--   2. The walk: H.worldNavTo straight to (148,76), the shortest on-foot
--      path (206 steps, walks.txt), off Tzen's, Albrook's and Nikeah's
--      doors.  Every random is fought by the tactical driver (boost-Fight,
--      the designed keys, its heal policy); field care follows each; nothing
--      flees.  The Black Drgn's desert (world group 40) is walked, not
--      avoided: a person does not know the sand deals it, and no path
--      misses it.
--   3. The save: the real Save UI into slot 3 at (148,76).
-- Every battle's [outcome] is asserted said, judged on the battle's own end
-- reading, and paid as due (as gen_wor_sabin does).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN = 6, 5
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, GREEN_CHERRY = 0xF1, 0xF8
local SAVE_TILE = { 148, 76 }                       -- one step east of Nikeah's door
local DOORS = { { 130, 179 }, { 140, 209 }, { 141, 209 }, { 146, 76 }, { 147, 76 } }
-- The species a walk here may meet, each with an authored Ot6ShieldTbl row
-- designed for this party: the plains six (route-wor-sabin 8.3), north of
-- Tzen's four (route-wor-edgar 8.2) and the deserts' three (route-wor-sabin
-- 8.2; H.worldPathGroups pairs every zone the walk crosses with every
-- terrain it crosses, so Tzen's desert pool (group 36) is in the set).
local DESIGNED = {
  [0x072] = "Peepers", [0x0B2] = "EarthGuard",
  [0x021] = "Mesosaur", [0x031] = "Gilomantis", [0x07C] = "Chitonid", [0x098] = "Gigan Toad",
  [0x0CA] = "Lunaris", [0x0E6] = "Osprey",
  [0x035] = "Bloompire", [0x058] = "Buffalax", [0x03C] = "Lizard", [0x030] = "Delta Bug",
  [0x0D5] = "Black Drgn",
}
local BLACK_DRGN_FORM = 195

local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch, 8)) end
local function xp(ch) return H.readByte(c(ch, 0x11)) + H.readByte(c(ch, 0x12)) * 256 + H.readByte(c(ch, 0x13)) * 65536 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d revivify=%d greencherry=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(GREEN_CHERRY), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d xp %d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), xp(ch),
    H.charHp(ch), H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine() return member(CELES, "CELES") .. "; " .. member(SABIN, "SABIN") end

-- ---- the pools ---------------------------------------------------------
local poolCache = {}
local function poolVerdict(g)
  if poolCache[g] == nil then
    local bad = nil
    if g == 0xFF then
      bad = { species = 0, form = 0 }
    else
      local pool = H.encounterPool(g)
      for slot = 1, 4 do
        for _, f in ipairs(pool[slot].formations) do
          for _, sp in ipairs(f.species) do
            if not DESIGNED[sp] and bad == nil then bad = { species = sp, form = f.id } end
          end
        end
      end
    end
    poolCache[g] = bad or false
  end
  return poolCache[g] == false, poolCache[g] or nil
end
local AVOID = nil
local function avoid()
  if AVOID == nil then AVOID = H.worldAvoidSet(DOORS) end
  return AVOID
end
local function assertLegPools(what, waypoints)
  local order, entry = H.worldPathGroups(waypoints, avoid())
  local zx, zy = H.worldZonePos()
  H.log(string.format("[route] %s: the walk can roll groups {%s}; its first encounter also {%s} "
    .. "(the saved position (%d,%d)'s zone)", what, table.concat(order, ", "),
    table.concat(entry, ", "), zx, zy))
  for _, list in ipairs({ order, entry }) do
    for _, g in ipairs(list) do
      local ok, bad = poolVerdict(g)
      H.assertEq(ok, true, string.format("%s: group %d deals only species with designed rows (not $%03X, formation %d)",
        what, g, bad and bad.species or 0, bad and bad.form or 0))
    end
  end
end

-- ---- the battles --------------------------------------------------------
local seen, tally, outcome0, battles0
local function tallyReset()
  tally = { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {}, drgn = 0 }
  outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
  seen = outcome0
end
tallyReset()
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own "
        .. "end reading (the UpdateSRAM hook), not the last per-frame one", what, i - outcome0,
        o.form & 0x1FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
      if (o.form & 0x1FF) == BLACK_DRGN_FORM then tally.drgn = tally.drgn + 1 end
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far, %d [outcome] line(s) (%d won, %d the "
        .. "party left, %d monster escape(s), %d Black Drgn); %s; %s", what, H.absorbGuardBattles - battles0,
        seen - outcome0, tally.won, tally["party left"], tally.escaped, tally.drgn, whereLine(), supplies()))
    end
  end)
end

local fenix0 = 0
H.run({ maxFrames = 300000 }, {
  -- ---- 0. cold Continue of wor-sabin-v1 --------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin outside Tzen", 10),
  H.waitUntil(function() return (emu.getState()["ppu.screenBrightness"] or 0) >= 15 end, 900,
    "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract("wor-sabin-v1")
    tallyReset()
    fenix0 = H.invCountOf(FENIX)
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s; kit CELES %s, SABIN %s; %s", H.frame,
      H.worldId(), H.worldX(), H.worldY(), whereLine(), kit(CELES), kit(SABIN), supplies()))
  end),

  -- ---- 1. the pools the walk may meet ------------------------------------------
  H.waitUntil(function() return H.worldSettled() end, 600, "the world map settled", 5),
  H.call(function()
    assertLegPools("Tzen -> Nikeah", { { H.worldX(), H.worldY() }, SAVE_TILE })
  end),

  -- ---- 2. the walk --------------------------------------------------------------
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 40000, playBattles = "tactical",
    avoid = avoid }),
  -- The step onto (148,76) can roll an encounter that opens only after the
  -- walker has seen the tile, aligned and in control (measured: K=12's
  -- battle opened during the save's menu press, the save timed out on its
  -- reward screen, build/attempts/wt/wor-edgar/leg1/var2/k12_s0.log).  Stand
  -- 90 frames, then walk to the tile again: a battle that came is fought
  -- there by the walker's driver, and none leaves it a no-op.
  (function()
    local n = 0
    return H.withReset(H.driveUntil(function()
      n = n + 1
      return n >= 90 or H.battleLoadStarted()
    end, 200, { H.release() }, "stand on the save tile"), function() n = 0 end)
  end)(),
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 3000, playBattles = "tactical",
    avoid = avoid }),
  -- A battle fought on the goal tile ends the walker at once, before its
  -- after-battle care (measured: K=12 shift 41's last battle, the Bloompire
  -- pair on (148,76), left CELES zombied at the save's assertion,
  -- build/attempts/wt/wor-edgar/leg1/var3/k12_s41.log), so the care runs
  -- here too: a no-op when nothing is owed.
  H.fieldCare({ tag = "care at Nikeah's door" }),
  checkOutcomes("the walk to Nikeah"),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "at Nikeah's door", 5),
  H.call(function()
    H.log(string.format("[nikeah] at the door f%d: world %d (%d,%d); %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), supplies()))
    H.assertEq(H.worldMode() and H.worldId() == 1, true, "on the World of Ruin map, not in Nikeah")
    H.assertEq(H.worldX() == SAVE_TILE[1] and H.worldY() == SAVE_TILE[2], true,
      "one step east of Nikeah's door (148,76)")
    H.assertEq(H.charStatus1(CELES) & 0xC2, 0, "CELES is not dead, petrified or zombied")
    H.assertEq(H.charStatus1(SABIN) & 0xC2, 0, "SABIN is not dead, petrified or zombied")
  end),

  -- ---- 3. the save ---------------------------------------------------------------
  H.saveGame({ slot = 3, tag = "wor-nikeah-v1 save" }),
  H.call(function()
    H.assertSavedSlotWorld(SAVE_TILE[1], SAVE_TILE[2], "wor-nikeah-v1", 3, 1)
    H.assertExitContract("wor-nikeah-v1")
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the stretch: %d battles (%s): %d won, %d the party left, %d monster "
      .. "escape(s), %d Black Drgn; Fenix Downs %d -> %d; %s; %s", seen - outcome0,
      table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped, tally.drgn, fenix0,
      H.invCountOf(FENIX), whereLine(), supplies()))
    H.screenshot("wor_nikeah")
  end),
  H.saveState("wor_nikeah.mss"),
  H.logStep(function()
    return string.format("wor_nikeah generated: CELES L%d and SABIN L%d on the World of Ruin at (%d,%d), outside Nikeah, saved in slot 3",
      level(CELES), level(SABIN), H.worldX(), H.worldY())
  end),
})

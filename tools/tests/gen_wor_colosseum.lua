-- gen_wor_colosseum.lua -- the Colosseum & Shadow arc's leg (docs/design/route-wor-colosseum.md): Continue the
-- `wor-ancient-v1` battery (CELES, RELM, CYAN and TERRA beside the Falcon by Figaro Castle), Kohlingen's counter,
-- the Falcon down by the Colosseum (world (50,17) -> map 413), the wagers: the Striker against SHADOW himself, who
-- joins (_cb78d9: $02F3), then the bag's gear the Colosseum trades up (section 2); out, the cabin (SHADOW, CELES,
-- CYAN, TERRA), the gear and relic care, Maranda's weapon counter for SHADOW's throwing kit and the gear stop,
-- and the save on the Falcon's tile by Maranda: the `wor-colosseum-v1` battery, the next arc's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR",
  [SABIN] = "SABIN", [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG",
  [GAU] = "GAU", [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local LINKS = {}
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, outToWorld, board, watches = K.say, K.kitLine, K.outToWorld, K.board, K.watches
local regroup, liftOff, landNear, partyOf = K.regroup, K.liftOff, K.landNear, K.partyOf
local kohlingenStop = K.kohlingenStop

local MAP_COL, COL_DOOR = 413, { 50, 17 }            -- the Colosseum's world door (its long exit lands on (50,18))
local MAP_MARANDA, MAP_MARANDA_WEAPON = 284, 289
local MARANDA_DOOR = { 69, 184 }
local MARANDA_WORLD = { { 69, 184 }, { 70, 184 } }
local SHOP_MARANDA_WEAPON = 80                       -- the World of Ruin's (_cc656f: $00A4 -> shop 80)
local FOUR = { SHADOW, CELES, CYAN, TERRA }
local BEFORE = { CELES, RELM, CYAN, TERRA }
-- the wagers after the Striker (route-wor-colosseum.md section 2): what the bag holds that the Colosseum trades up
-- into gear the party wears, each against an opponent the fighter beats (the labs' measured rates there)
local STRIKER, STRATO = 0x29, 0x31
local ECONOMIZER, RIBBON = 0xCE, 0xCA
local WAGERS = {
  { 0x05, "the Assassin for a SwordBreaker, LOCKE's blade (vs Test Rider)" },
  { 0x2A, "the Stunner for CYAN's second Strato (vs Test Rider)" },
  { 0x7B, "the Regal Crown for a Genji Helmet (vs Opinicus)" },
  { 0x16, "the Soul Sabre for a Falchion (vs Opinicus)" },
  -- last, since its fighter may go in armed for it: CELES (TERRA's random Magic casts Drain and Merton on
  -- herself), with the bag's Flame Sabres in her Genji Glove's hands against the SrBehemoth's fire weakness when
  -- the bag holds them (section 2).  The bag holds one Gem Box and the Colosseum takes it on a loss, so a loss
  -- is a lost attempt, which a person reloads (`reload`: "LOST: ...", the runner's retry from the boot)
  { 0xD8, "the Gem Box for the Economizer, TERRA's (vs SrBehemoth)", fighter = CELES, arm = 0x0D, reload = true },
}
-- SHADOW's throwing kit (kits.md "Shadow"): the skeans and edges his Throw lists, from Maranda's weapon counter
local THROWN = {
  { 0xAB, 9, "FIRE SKEAN" }, { 0xAC, 9, "WATER EDGE" }, { 0xAD, 9, "BOLT EDGE" },
  { 0xAF, 4, "SHADOW EDGE (the smoke)" }, { 0xAE, 4, "INVIZ EDGE (the exit)" },
}

local FIRST_FIGHTS, firstFights = 3, 0
local function joined() return sw(0x02F3) == 1 end
local function via(points, what, avoid)
  local steps = {}
  for _, p in ipairs(points) do
    steps[#steps + 1] = H.navTo(p[1], p[2], { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid })
  end
  steps[#steps + 1] = H.call(function() H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY())) end)
  return H.seqStep(steps)
end

H.run({ maxFrames = 1600000 }, {
  H.bootCheckpoint("wor-ancient-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(BEFORE))
    H.assertEq(sw(0x019F), 1, "SHADOW left Thamasa for the Colosseum ($019F, _cb7d69)")
    H.assertEq(sw(0x01EF), 1, "SHADOW waits at the Colosseum ($01EF: CheckColosseumShadow)")
    H.assertEq(joined(), false, "SHADOW not yet recruited ($02F3 clear)")
    H.assertEq(H.invCountOf(STRIKER) > 0, true, "the Striker is in the bag (the Veldt cave's chest)")
  end),
  -- @@setup-end

  -- ---- 1. Kohlingen's counter, the Colosseum -------------------------------------------------------------
  -- @@stage colosseum
  board(),
  kohlingenStop("the top-up before the Colosseum"),
  landNear(COL_DOOR[1], COL_DOOR[2], "the Falcon down by the Colosseum"),
  H.worldNavTo(COL_DOOR[1], COL_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_COL and settled() end, 2400, "the Colosseum: map 413", 1),
  H.call(function() say("route", "the Colosseum") end),
  H.saveState("wor_colosseum_in.mss"),

  -- ---- 2. the wagers -------------------------------------------------------------------------------------------
  -- @@stage wagers
  -- the Striker: SHADOW himself is the opponent while $01EF stands (CheckColosseumShadow), and the win is his
  -- joining (_cb78d9).  A loss would take the Striker and SHADOW with it: the leg fails there (an assertion,
  -- which the runner does not retry), and a person reloads
  H.colosseumBet(STRIKER, { what = "the Colosseum: the Striker against SHADOW", fight = FIGHT, want = "won",
    wonIf = joined }),
  H.call(function()
    H.assertEq(joined(), true, "SHADOW joined ($02F3)")
    H.assertEq(sw(0x01EF), 0, "SHADOW no longer waits at the Colosseum ($01EF)")
    H.log(string.format("[shadow] SHADOW joined at L%d (norm_lvl), party byte $%02X, commands %02X %02X %02X %02X",
      lv(SHADOW), H.readByte(0x1850 + SHADOW), H.readByte(c(SHADOW, 0x16)), H.readByte(c(SHADOW, 0x17)),
      H.readByte(c(SHADOW, 0x18)), H.readByte(c(SHADOW, 0x19))))
  end),
  H.fieldCare({ threshold = 1.0, tag = "after the Striker" }),
  H.lazy(function()
    local steps = {}
    for _, w in ipairs(WAGERS) do
      local arm, held = {}, {}
      if w.arm then
        -- the fighter's hands take the wager's weapon, as many as the bag holds (two at most), and get their own
        -- blades back after the fight (the gear policy leaves a Genji Glove's two hands to the kit, #434)
        arm[1] = H.lazy(function()
          held = { H.readByte(c(w.fighter, 0x1F)), H.readByte(c(w.fighter, 0x20)) }
          local hands = {}
          for h = 0, math.min(1, H.invCountOf(w.arm) - 1) do hands[#hands + 1] = { h, w.arm } end
          if #hands == 0 then
            return H.call(function() H.log(string.format("[colosseum] %s: no $%02X in the bag to arm %s", w[2],
              w.arm, NAMES[w.fighter])) end)
          end
          return H.equipKit(w.fighter, hands, { tag = string.format("%s armed for the wager", NAMES[w.fighter]) })
        end)
        arm[2] = H.call(function() H.log("[kit] " .. kitLine({ w.fighter })) end)
        arm[3] = H.lazy(function()
          local back = {}
          for h = 0, 1 do
            if held[h + 1] ~= 0xFF and H.readByte(c(w.fighter, 0x1F + h)) ~= held[h + 1] then
              back[#back + 1] = { h, held[h + 1] }
            end
          end
          if #back == 0 then return H.call(function() end) end
          return H.equipKit(w.fighter, back, { tag = string.format("%s's own blades back", NAMES[w.fighter]) })
        end)
      end
      steps[#steps + 1] = H.cond(function() return H.invCountOf(w[1]) > 0 end, {
        arm[1] or H.call(function() end),
        arm[2] or H.call(function() end),
        H.colosseumBet(w[1], { what = "the Colosseum: " .. w[2], fight = FIGHT, fighter = w.fighter }),
        H.call(function()
          local b = H.colosseumLog[#H.colosseumLog]
          if w.reload and not b.won then
            error(string.format("LOST: %s -- %s lost the wager at f%d, and the bag held one", w[2],
              NAMES[w.fighter], b.frame), 0)
          end
        end),
        arm[3] or H.call(function() end),
        H.fieldCare({ threshold = 1.0, tag = "after the wager" }),
      }, { H.call(function() H.log(string.format("[colosseum] %s: $%02X is not in the bag", w[2], w[1])) end) })
    end
    return H.seqStep(steps)
  end),
  H.call(function()
    local won, n = 0, #H.colosseumLog
    for _, b in ipairs(H.colosseumLog) do if b.won then won = won + 1 end end
    say("colosseum", string.format("the wagers done: %d of %d won", won, n))
  end),
  -- out by the long exit (22,16) onto the world (50,18)
  H.navTo(23, 16, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, arrive = function() return H.worldMode() end }),
  H.waitWorldSettled("out of the Colosseum", 1800, 30),

  -- ---- 3. the cabin: SHADOW seated; the gear --------------------------------------------------------------
  -- @@stage cabin
  regroup(FOUR),
  H.gearDress({ tag = "gear with SHADOW" }),
  H.dressRelics({ { SHADOW, "SHADOW" }, { CELES, "CELES" }, { CYAN, "CYAN" }, { TERRA, "TERRA" } },
    { tag = "relics with SHADOW" }),
  -- the Colosseum's Strato makes CYAN's pair: the gear policy leaves a Genji Glove's two hands to the kit
  -- (#434), so the kit puts it in his second hand, over the Aura
  H.lazy(function()
    if H.invCountOf(STRATO) > 0 and H.readByte(c(CYAN, 0x1F)) == STRATO and H.readByte(c(CYAN, 0x20)) ~= STRATO then
      return H.equipKit(CYAN, { { 1, STRATO } }, { tag = "CYAN: the Colosseum's Strato in his second hand" })
    end
    return H.call(function() H.log("[kit] CYAN's second Strato: not in the bag, or worn") end)
  end),
  -- the Colosseum's Economizer (every spell 1 MP, boosts included: Ot6SpellMP) goes on TERRA, the party's caster:
  -- her Magic carries the Cure and Life the party leans on and the Fire ladder to Ultima, where CELES's Runic
  -- refills her own MP (route-wor-colosseum.md section 5, kits.md "Terra").  It takes the slot that does not hold
  -- her Ribbon; the relic rule leaves a worn relic it does not rank where it is (H.relicPlan step 1)
  H.lazy(function()
    if H.invCountOf(ECONOMIZER) < 1 then
      return H.call(function() H.log("[kit] TERRA's Economizer: not in the bag, or worn") end)
    end
    local slot = H.readByte(c(TERRA, 0x23)) == RIBBON and 5 or 4
    return H.equipKit(TERRA, { { slot, ECONOMIZER } }, { tag = "TERRA: the Colosseum's Economizer" })
  end),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  liftOff(),

  -- ---- 4. Maranda: SHADOW's throwing kit, the gear stop ---------------------------------------------------
  -- @@stage maranda
  landNear(MARANDA_DOOR[1], MARANDA_DOOR[2], "the Falcon down by Maranda"),
  H.worldNavTo(MARANDA_DOOR[1], MARANDA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_MARANDA and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_MARANDA and settled() end, 2400, "Maranda: map 284", 1),
  via({ { 14, 27 }, { 13, 23 }, { 9, 25 } }, "Maranda's street"),
  H.crossDoor(18, 9, MAP_MARANDA_WEAPON, 54, 22, "Maranda -> the weapon shop (289)", { fight = FIGHT }),
  H.shopTalk(54, 16, "Maranda's weapon counter", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), SHOP_MARANDA_WEAPON, "the counter opened shop 80 ($0201)") end),
  H.lazy(function()
    local steps = {}
    for _, t in ipairs(THROWN) do
      steps[#steps + 1] = H.buyItem(t[1], function() return math.max(0, t[2] - H.invCountOf(t[1])) end,
        t[3] .. " to " .. t[2])
    end
    return H.seqStep(steps)
  end),
  H.shopClose("Maranda's weapon counter"),
  H.navTo(54, 22, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return map() == MAP_MARANDA end, 900, { H.hold({ "down" }) }, "the weapon shop -> Maranda"),
  H.release(),
  H.waitUntil(function() return map() == MAP_MARANDA and settled() end, 2400, "Maranda's street", 5),
  H.gearStop({ tag = "gear Maranda", fight = FIGHT }),
  H.dressRelics({ { SHADOW, "SHADOW" }, { CELES, "CELES" }, { CYAN, "CYAN" }, { TERRA, "TERRA" } },
    { tag = "relics after Maranda" }),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top" }),
  H.call(function()
    say("shop", "Maranda")
    H.log("[kit] " .. kitLine(FOUR))
    local t = {}
    for _, x in ipairs(THROWN) do t[#t + 1] = string.format("%s %d", x[3], H.invCountOf(x[1])) end
    H.log("[shadow] the throwing kit: " .. table.concat(t, ", "))
  end),
  via({ { 9, 25 }, { 13, 23 }, { 14, 27 }, { 11, 29 } }, "Maranda's street to the gate"),
  H.navTo(11, 31, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, arrive = function() return H.worldMode() end }),
  H.waitWorldSettled("out of Maranda", 1800, 30),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, avoid = MARANDA_WORLD }),

  -- ---- 5. SHADOW's first fights, and the save -----------------------------------------------------------
  -- @@stage save
  -- the plain by Maranda's Falcon (world group 49: the Crawler trio, Mantodea with Sprinter and Spek Tor):
  -- every body there but the Mantodea takes pierce, and the Crawler takes no slash, so SHADOW's blade keys what
  -- CELES, CYAN and TERRA's cannot (route-wor-colosseum.md section 3)
  H.call(function() firstFights = #H.outcomes end),
  K.pace(function() return #H.outcomes - firstFights >= FIRST_FIGHTS end, FIRST_FIGHTS + 1,
    "SHADOW's first fights on the plain by Maranda"),
  H.call(function() say("wor", string.format("after SHADOW's first %d fights", #H.outcomes - firstFights)) end),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, avoid = MARANDA_WORLD }),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    for _, ch in ipairs(FOUR) do
      H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated")
    end
    H.assertEq(H.readByte(c(SHADOW, 0x1F)) ~= 0xFF, true, "SHADOW holds a weapon")
    H.assertEq(H.readByte(c(TERRA, 0x23)) == ECONOMIZER or H.readByte(c(TERRA, 0x24)) == ECONOMIZER, true,
      "TERRA wears the Colosseum's Economizer")
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-colosseum-v1"),
  H.saveState("wor_colosseum.mss"),
  H.logStep(function()
    return string.format("wor_colosseum generated: SHADOW L%d, CELES L%d, CYAN L%d and TERRA L%d beside the Falcon by "
      .. "Maranda, world (%d,%d), saved in slot 3", lv(SHADOW), lv(CELES), lv(CYAN), lv(TERRA), H.worldX(), H.worldY())
  end),
})

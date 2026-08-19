-- probe_dancefreeze.lua -- #129: reproduce the dance-kill battle freeze
-- and dump the engine wait-state mid-freeze.  NOT in the suite.
-- Derived from battle_dancemp.lua at the failing alignment (no HP pin).
-- battle_dancemp.lua -- issue #34: Dance costs MP, a flat amount paid at
-- dance start, per docs/design/mp-economy.md's verb survey (Dance: "flat,
-- paid at start", 4-10).
--
-- Ot6AbilityCost's cmd-$13 arm charges Ot6DanceCost (8 MP) when the
-- actor's DANCE status ($3ef8 bit 0) is still clear, which is the commit
-- moment, and 0 on every mid-dance turn (RandDanceAction re-queues cmd $13
-- through
-- the same CreateAction with the bit set).  The Dance menu shows the cost
-- through the #35 display pattern's second consumer: Ot6DanceRowDecorate
-- re-lays each column to [font][cost][name] (the Ot6ToolRowDecorate
-- transform) and greys an unaffordable row via Ot6AbilityGrey; the #35
-- wallet paints the actor's current MP on the window's top edge.
--
-- Issue #75 conversion: the real Mog, and the game's own dance-learning.
-- The old header said Mog was not reachable yet; that is no longer true,
-- because he leads P2 of the Narshe moogle defense (gen_moogle,
-- moogle_defense.mss, generated en route to moogle_cleared, hence the
-- savestate=moogle_cleared line above, whose run refreshes both).  So every
-- staging is gone: no CHAR::MOG installs, no command-row writes, no monster
-- stop, HP or death-proof pins, no $1d4c pin, no $267e rebuild.  In their
-- place, the game's own setup:
--   * the defense is deployed as gen_moogle deploys it (P3 east,
--     P2 west, P1 back to the choke), and the wave storm is fought with
--     plain tap-A, except P2's battles, which are this test's subject;
--   * P2's first wave battle is won with plain Fights, and the victory is
--     what teaches Mog his first dance: the battle-end path sets the
--     current background's dance in $1d4c ("mastered a new dance!",
--     battle_main.asm:15842), asserted as a delta, 0 before and the
--     BattleBGDance bit after.  Until then Mog has no Dance command at all
--     (InitCmd_02 removes it on a zero mask, battle_main.asm:14129), which
--     is also asserted, because it is the reason no earlier fixture could
--     host this file with real inputs;
--   * P2's second wave battle is the measurement: the known dance now
--     matches the battle background by construction, since it was learned on
--     this terrain, so Cmd_13's 50% bg-mismatch stumble never fires
--     and the multi-turn phases are deterministic.  That is the property the
--     old file bought with a pinned mask, obtained here from the game's own
--     rule.
--
-- Asserted (phases 1-3 in P2's second wave battle, with no writes):
--   1. menu: the learned dance's row renders [cost 8][name] with the #35
--      pattern, in white because it is affordable at Mog's real pool; the
--      wallet paints his real MP; and the name is DanceName's own record,
--      read from the ROM.
--   2. charge at start: the cost queue prices the commit at 8, MP drops
--      exactly 8 from the real pool, and the dance status locks in.
--   3. free steps: two further auto-queued dance turns price at 0 and MP
--      stays put, so there is one payment per battle.
--
-- One labeled isolation arm (issue #75): two writes stay.
--   4. refusal: the below-price fizzle, where the row greys $25, the commit
--      still queues at 8, and the universal insufficient-MP gate refuses, so
--      there is no dance status and MP is unmoved.  The input-driven case is
--      a Mog whose pool is under 8, which is reachable in open play by
--      dancing across fights but not inside this set piece: the defense gives
--      P2 exactly two wave battles, the first is spent learning the dance
--      (the game's own precondition), and once Mog is dancing his turns
--      auto-queue and his menu never reopens.  Per the burn-down plan's
--      observation-window ruling (systemic call 2), the arm runs before the
--      real dance in the same battle: Mog's pool is written to 7, the refusal
--      is measured, and the pool is restored to the value read at battle
--      start.  Both writes are this file's .writeWord( waiver, and it may
--      never produce fixtures.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/moogle_defense.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_TGT = 0x05, 0x21, 0x38
-- The bystanders' "right swaps Fight->Def, then A" turn consumption passes
-- through menu state $27, the def. confirmation (btlgfx_main.asm:19186:
-- right on Fight enters it, A there queues command $15).  Measured
-- 2026-08-18 on the re-made moogle_defense: the old catch-all "b on any
-- non-command state" canceled $27 before the A of the 40-frame cadence
-- could land, so a bystander whose Def the arm needed oscillated
-- $05 <-> $27 without ever consuming its turn, MOG's window never came
-- back, and the input-driven phases timed out.  $27 takes the A instead.
local ST_DEF = 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local FIGHTPARTY = 0x1A6D               -- which party a defense battle engaged
local DANCE_COST = 8                    -- Ot6DanceCost (asserted vs the queue)
local WALLET = 0x7C16
local WHITE, GREY = 0x21, 0x25

-- DanceName: 12-byte records, read from the ROM the drawer streams.
local DANCENAME = H.sym("DanceName") & 0x3FFFFF
local function danceNameSeq(id)
  local t = {}
  for i = 0, 11 do t[#t + 1] = H.readRomByte(DANCENAME + id * 12 + i) end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function danceNameText(id)
  local s = ""
  for _, b in ipairs(danceNameSeq(id)) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    elseif b == 0xfe then s = s .. " "
    else s = s .. "?" end
  end
  return s
end

-- find a glyph run in the $7c00 menu map (the dance window stages there,
-- on rows 1/3/5/7).  Returns the word address, or nil.
local function findInMap(seq)
  for w = 0x7C00, 0x7CF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, emu.memType.snesVideoRam) & 0xFF) ~= seq[i] then
        hit = false; break
      end
    end
    if hit then return w end
  end
  return nil
end
local function mapWord(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end

-- squads (gen_moogle's tables): P2 = MOG + three moogles, leader obj $019A
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }

local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

local mogSlot = nil
local function mpOf(slot) return H.readWord(0x3C08 + slot * 2) end

-- ------------------------------------------------------------------------
-- the storm driver: fight every non-P2 battle with plain tap-A, and stop the
-- moment a battle engages P2, which is this test's subject.  Off-battle it
-- keeps hands off, because the defense sequence moves the waves itself;
-- dialogs are paged.
-- ------------------------------------------------------------------------
local ph, hb = 0, -600
local function untilP2Battle(what)
  local battN = 0
  return H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 30 and H.readByte(FIGHTPARTY) == 2
  end, 60000, {
    H.call(function()
      ph = ph + 1
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[hb f%d] batt=%s party=%d menu=%02x guards=%02x",
          H.frame, tostring(H.battleLoadStarted()), H.readByte(FIGHTPARTY),
          H.readByte(MENU), H.readByte(0x1f41)))
      end
      if H.battleLoadStarted() and H.readByte(FIGHTPARTY) ~= 2 then
        H.setPad(ph % 8 < 4 and { a = true } or {})   -- plain tap-A win
      elseif not H.battleLoadStarted() then
        H.setPad(ph % 8 < 4 and { a = true } or {})   -- page dialogs/victory
      else
        H.setPad({})
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- tap-A through a whole P2 battle (battle 1: plain moogle Fights win it)
local function winByTapA(what)
  return H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
    H.call(function()
      ph = ph + 1
      H.setPad(ph % 8 < 4 and { a = true } or {})
    end),
    H.waitFrames(1),
  }, what)
end

-- wait for MOG's own menu; bystander moogles Defend, since the pack must live
-- through the dance turns; dialogs are paged.
local function mogMenu(what)
  return H.driveUntil(function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[mogmenu f%d] batt=%s mons=%d menu=%02x actor=%d "
          .. "mstate=%02x party=%d mogHp=%d", H.frame,
          tostring(H.battleLoadStarted()), H.monstersPresent(),
          H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
          H.readByte(FIGHTPARTY),
          mogSlot and H.readWord(0x3BF4 + mogSlot * 2) or -1))
      end
      if not H.battleLoadStarted() then H.setPad({}) return end
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
        return
      end
      local a = H.readByte(ACTOR)
      if a ~= mogSlot then
        local st = H.readByte(MSTATE)
        local step = ph % 40
        if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
        elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
        elseif step < 4 then H.setPad({ right = true })    -- Fight -> Def
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- from Mog's command window: walk onto Dance and open the list ($21)
local function openDance(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_DANCE end,
    1200, {
      H.call(function()
        ph = ph + 1
        local edge = ph % 10 < 5
        local a = H.readByte(ACTOR)
        if H.readByte(MSTATE) ~= ST_CMD then H.setPad({}) return end
        local wantCell = nil
        for i = 0, 3 do
          if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_DANCE then wantCell = i end
        end
        assert(wantCell, "MOG's real battle command list carries Dance now")
        local cur = H.readByte(0x890F + a)
        if cur == wantCell then H.setPad(edge and { a = true } or {})
        elseif cur < wantCell then H.setPad(edge and { down = true } or {})
        else H.setPad(edge and { up = true } or {}) end
      end),
      H.waitFrames(1),
    }, what)
end

local danceId, mp0 = nil, nil
local costs = {}                        -- cost-queue stores while cmd $13 queues

-- walk the dance cursor onto the known dance's cell.  The $267e list is
-- positional: entry i holds dance i or $ff (UpdateMenuState_21's confirm
-- reads $267e,x and buzzes on a $ff cell), so the one learned dance sits
-- at cell danceId (row danceId//2, col danceId%2 on the 2-column grid) and
-- not at cell 0.  Cursor vars: col $8937+slot, row $893b+slot (the state's own
-- w7e8937,y and w7e893b,y).  Measured: an A-mash at cell 0
-- buzzed indefinitely on the first run of this conversion.
local function danceCursorToKnown(what)
  -- danceId is discovered at runtime, so the target row/col are computed
  -- inside the callbacks, not at step-construction time.
  return H.driveUntil(function()
    local a = H.readByte(ACTOR)
    return H.readByte(MSTATE) == ST_DANCE
       and H.readByte(0x8937 + a) == danceId % 2
       and H.readByte(0x893B + a) == danceId // 2
  end, 900, {
    H.call(function()
      ph = ph + 1
      local edge = ph % 10 < 5
      local a = H.readByte(ACTOR)
      if H.readByte(MSTATE) ~= ST_DANCE then H.setPad({}) return end
      local row, col = danceId // 2, danceId % 2
      local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
      if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
      elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

H.run({ maxFrames = 250000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "control on the defense map"),
  H.call(function()
    H.assertEq(H.mapId(), 51, "moogle_defense on map 51")
    H.assertEq(H.readByte(DANCES), 0,
      "a real WoB Mog has learned NO dance yet -- $1d4c is zero as saved, "
      .. "which is why the learn must be earned before anything can be measured")
    emu.addMemoryCallback(function(_, v)
      if H.readByte(0x3A7A) == CMD_DANCE then costs[#costs + 1] = v end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  end),

  -- deployment, gen_moogle's exact march order: P1 unboxes the mound, P3
  -- east, P2 (MOG's squad) west, P1 back to the choke.
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  H.logStep("deployed; letting the storm come"),

  -- ---- P2's first wave battle: win it, and the win teaches the dance ----
  untilP2Battle("the west arm's first wave engages MOG's squad"),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
    end
    assert(mogSlot, "MOG is in P2's battle party")
    -- the reason this file needed the defense: with no dance known there is
    -- no Dance command at all (InitCmd_02's zero-mask removal)
    local hasDance = false
    for i = 0, 3 do
      if H.readByte(CMDTBL + mogSlot * 12 + i * 3) == CMD_DANCE then hasDance = true end
    end
    H.assertEq(hasDance, false,
      "before the first win MOG has NO Dance command -- InitCmd_02 removed "
      .. "it on the zero mask (battle_main.asm:14129)")
    -- the dance this battle's background will teach
    local bg = H.readByte(0x11E2)
    danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg)
    H.log(string.format("battle bg %02x teaches dance %d '%s' on a win",
      bg, danceId, danceNameText(danceId)))
    H.assertEq(danceId < 8, true, "this background HAS a dance to teach")
  end),
  winByTapA("P2's first wave won with plain Fights"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(DANCES), 1 << danceId,
      "the VICTORY taught exactly the background's dance -- battle_main.asm"
      .. ":15842's tsb $1d4c, the game's own learning rule, zero writes")
    H.log(string.format("MOG mastered '%s' ($1d4c = $%02x)",
      danceNameText(danceId), H.readByte(DANCES)))
  end),

  -- ---- P2's second wave battle: the measurement -------------------------
  untilP2Battle("the west arm's second wave engages MOG's squad"),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
    end
    assert(mogSlot, "MOG is in P2's second battle")
    mp0 = mpOf(mogSlot)
    H.log(string.format("MOG slot %d, real pool %d MP", mogSlot, mp0))
    H.assertEq(mp0 >= DANCE_COST, true,
      "positive control: the real pool funds the dance-start charge")
    -- the learned dance matches this background by construction: same
    -- terrain, same BattleBGDance row, which gives the determinism the old
    -- file bought with a pinned mask.
    local bg = H.readByte(0x11E2)
    H.assertEq(H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg), danceId,
      "same terrain, same dance: the bg-mismatch stumble cannot fire")
  end),

  -- ======================================================================
  -- The labeled isolation arm (see header): the below-price refusal.
  -- Mog's pool is written to 7, the refusal is measured through the
  -- standard surfaces, and the pool is restored to the value read above.
  -- This runs before the real dance because a dancing Mog's menu never
  -- reopens (RandDanceAction auto-queues his turns).
  -- ======================================================================
  mogMenu("mog's command window (isolation arm)"),
  H.call(function()
    -- #129 staging (2026-08-19, a labeled unit-style expedient): a dance
    -- auto-turn that kills the LAST monster trips the battle-end freeze
    -- #129 tracks (the fight provably never ends), and the #122 RNG
    -- reshuffle put this file's kill exactly on Mog's first free turn.
    -- The ledger under test needs the pack ALIVE for two more auto-turns
    -- and nothing after needs the battle to end, so the pack is pinned
    -- tall (3000 HP) -- no kill, no freeze, the queue fills, the tail
    -- asserts run.  #129 carries its own deterministic repro recipe; a
    -- +300 nudge was tried first and the kill still landed.
    -- PROBE: no HP pin -- this file exists to LET the first-turn kill land
    -- and then dump the frozen engine's wait-state.
    H.writeWord(0x3C08 + mogSlot * 2, DANCE_COST - 1)
    H.log("[isolation arm] MOG's pool := 7 -- below the flat price")
  end),
  openDance("the poor dancer's list opens"),
  H.waitFrames(20),
  H.call(function()
    costs = {}
    -- the one learned dance's row: cost tile and name, both grey ($25)
    local w = findInMap(danceNameSeq(danceId))
    H.assertEq(w ~= nil, true, "the learned dance's name is drawn in the list")
    H.assertEq(mapWord(w) >> 8, GREY,
      "the unaffordable row's name greys ($25 -- Ot6AbilityGrey)")
    H.assertEq(mapWord(w - 1) & 0xFF, 0xb4 + DANCE_COST,
      "the row leads with its cost (8) -- the #35 [font][cost][name] layout")
    H.assertEq(mapWord(w - 1) >> 8, GREY,
      "...and the cost greys with it (one font colors the pair)")
    H.screenshot("dancemp_grey")
  end),
  -- the menu lets the commit through, since the block stays out of
  -- C1 (see Ot6AbilityGrey's scope comment); the refusal is the universal
  -- execution-time fizzle.
  danceCursorToKnown("cursor onto the learned dance's cell (isolation arm)"),
  H.driveUntil(function()
    return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF
  end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
        H.setPad(ph % 10 < 5 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "the refused dance still commits (action queued)"),
  H.driveUntil(function()
    return H.readByte(0x32CC + mogSlot * 2) == 0xFF
  end, 12000, {
    H.call(function()
      ph = ph + 1
      -- bystanders keep the clock moving with Defends
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= mogSlot then
        local st = H.readByte(MSTATE)
        local step = ph % 40
        if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
        elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
        elseif step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      elseif H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "the queued dance drains (fizzles at execution)"),
  H.waitFrames(120),
  H.call(function()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = tostring(v) end
    H.log("refusal cost queue: {" .. table.concat(c, ",") .. "}")
    H.assertEq(costs[1], DANCE_COST,
      "the commit was priced at 8 (it reached the queue -- not a vacuous pass)")
    H.assertEq(mpOf(mogSlot), DANCE_COST - 1,
      "the universal insufficient-MP gate refused: MP unmoved")
    H.assertEq(H.readByte(0x3EF8 + mogSlot * 2) & 0x01, 0,
      "and the dance never started (no whole-battle state for free)")
    -- restore the real pool read at battle start; the arm's second write
    H.writeWord(0x3C08 + mogSlot * 2, mp0)
    H.log("[isolation arm] MOG's pool restored to the real " .. mp0)
  end),

  -- ---- 1. the menu, at the real pool: white row, cost, wallet ----------
  mogMenu("mog's command window (input-driven phases)"),
  openDance("the dance list opens"),
  H.waitFrames(20),
  H.call(function()
    costs = {}
    local w = findInMap(danceNameSeq(danceId))
    H.assertEq(w ~= nil, true, "the learned dance's name is drawn in the list")
    H.assertEq(mapWord(w) >> 8, WHITE, "affordable at the real pool: white")
    H.assertEq(mapWord(w - 1) & 0xFF, 0xb4 + DANCE_COST,
      "the row leads with its cost (8), white -- the #35 pattern")
    H.assertEq(mapWord(w - 2) & 0xFF, 0xFF,
      "the tens place is blank, not '0' (one-digit price)")
    -- the wallet paints MOG's real MP
    H.assertEq(mapWord(WALLET) & 0xFF, 0x8C, "wallet 'M' on the dance window")
    H.assertEq(mapWord(WALLET + 1) & 0xFF, 0x8F, "wallet 'P'")
    H.assertEq(mapWord(WALLET + 3) & 0xFF,
      (mp0 >= 10) and (0xb4 + math.floor(mp0 / 10) % 10) or 0xFF,
      "wallet tens digit = the real pool's")
    H.assertEq(mapWord(WALLET + 4) & 0xFF, 0xb4 + mp0 % 10,
      "wallet ones digit = the real pool's")
    H.screenshot("dancemp_menu")
  end),

  -- ---- 2. charge at dance start ----------------------------------------
  -- walk onto the known dance's positional cell (see danceCursorToKnown)
  -- and confirm; the dance self-targets, so one confirm queues it.
  danceCursorToKnown("cursor onto the learned dance's cell"),
  H.driveUntil(function()
    return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF
           or (H.readByte(0x3EF8 + mogSlot * 2) & 0x01) == 1
  end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
        H.setPad(ph % 10 < 5 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "the dance commits (action queued)"),
  H.driveUntil(function()
    return mpOf(mogSlot) ~= mp0
  end, 12000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= mogSlot then
        local st = H.readByte(MSTATE)
        local step = ph % 40
        if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
        elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
        elseif step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      elseif H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "the dance-start charge lands"),
  H.call(function()
    H.assertEq(mpOf(mogSlot), mp0 - DANCE_COST,
      "dance-start charged exactly the flat 8 from the REAL pool")
    H.assertEq(costs[1], DANCE_COST,
      "the cost queue priced the commit at 8 (Ot6AbilityCost cmd $13)")
    H.assertEq(H.readByte(0x3EF8 + mogSlot * 2) & 0x01, 1,
      "the DANCE status locked in (whole-battle state bought)")
  end),

  -- ---- 3. PROBE: let the kill land, catch the freeze, dump the engine ----
  H.call(function()
    -- exec-hit counters: does the engine still RUN these during the freeze?
    probeHits = {}
    -- exec callbacks take the SNES CPU address RAW (the seed ladder's own
    -- convention); the first draft masked to file offsets and every counter
    -- read zero even mid-fight.
    probeTrace = {}
    local watch = {
      CheckBattleEnd  = H.sym("CheckBattleEnd"),
      Ot6ActionEnd    = H.sym("Ot6ActionEnd"),
      GfxCmd_0f       = H.sym("GfxCmd_0f"),
      BtlGfx_04       = H.sym("BtlGfx_04"),
      WinBattle       = H.sym("WinBattle"),
      GfxCmd_02       = H.sym("GfxCmd_02"),
      TerminateBattle = H.sym("TerminateBattle"),
      EndAction       = H.sym("EndAction"),
      HudFlush        = H.sym("Ot6BgHudFlush_ext"),
      RestageGate     = H.sym("Ot6RestageGate_ext"),
      UpdateMenuState = H.sym("UpdateMenuState"),
      UpdateSprites   = H.sym("UpdateSprites"),
      ClearSpriteData = H.sym("ClearSpriteData"),
      UpdateSfx       = H.sym("UpdateSfx"),
      -- #129 round 9: the message machinery's own internals, per the
      -- issue's corrected evidence trail -- which of these still executes
      -- during the freeze names the loop.
      mess_wait        = H.sym("mess_wait"),
      DrawDlgText      = H.sym("DrawDlgText@btlgfx_code"),
      InitWideMsgWindow = H.sym("InitWideMsgWindow"),
      GetAttackMsgPtr  = H.sym("GetAttackMsgPtr"),
      c19917           = H.sym("_c19917"),
      ShowMsg          = H.sym("ShowMsg"),
      DlgTextCmd_07    = H.sym("DlgTextCmd_07"),
      UpdateCtrlBattle = H.sym("UpdateCtrlBattle"),
    }
    for name, cpu in pairs(watch) do
      probeHits[name] = 0
      emu.addMemoryCallback(function()
        probeHits[name] = probeHits[name] + 1
        if #probeTrace < 60 then
          probeTrace[#probeTrace + 1] =
            string.format("f%d:%s", H.frame, name)
        end
      end, emu.callbackType.exec, cpu, cpu)
    end
    probe46w = {}
    emu.addMemoryCallback(function()
      local st = emu.getState()
      if #probe46w < 40 then
        probe46w[#probe46w + 1] = string.format("f%d:%02X%04X",
          H.frame, st["cpu.k"], st["cpu.pc"])
      else
        table.remove(probe46w, 1)
        probe46w[#probe46w + 1] = string.format("f%d:%02X%04X",
          H.frame, st["cpu.k"], st["cpu.pc"])
      end
    end, emu.callbackType.write, 0x000046, 0x000046)
    probe47 = 0
    emu.addMemoryCallback(function()
      probe47 = probe47 + 1
      if probe47 % 65536 == 1 then
        local st = emu.getState()
        probePC = st["cpu.pc"]
        probeSP = st["cpu.sp"]
        probeK  = st["cpu.k"]
      end
    end, emu.callbackType.read, 0x000047, 0x000047)
    H.log("[probe] exec watches armed (CPU addrs)")
  end),
  H.driveUntil(function()
    -- freeze signature: both monsters read 0 HP while battleLoadStarted
    local dead = true
    for s = 0, 1 do
      if H.readWord(0x3BFC + s * 2) ~= 0 then dead = false end
    end
    return H.battleLoadStarted() and dead
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if not H.battleLoadStarted() then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= mogSlot then
        local st = H.readByte(MSTATE)
        local step = ph % 40
        if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
        elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
        elseif step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "both monsters at 0 HP (the kill landed)"),
  H.call(function()
    H.log("[probe] kill landed -- sampling the freeze")
    for name, n in pairs(probeHits) do
      H.log(string.format("[probe] pre-freeze exec hits %s=%d", name, n))
      probeHits[name] = 0
    end
    probeTrace = {}   -- restart the sequence trace at the kill
  end),
  H.waitFrames(1200),
  H.call(function()
    -- 20 seconds later: what still executes, and what does state say?
    for name, n in pairs(probeHits) do
      H.log(string.format("[probe] FROZEN-window exec hits %s=%d (1200 frames)",
        name, n))
    end
    for s = 0, 2 do
      local e = 4 + s
      H.log(string.format(
        "[probe] mon s%d: hp=%d st1=%02X st4=%02X present($3AA8)=%02X",
        s, H.readWord(0x3BFC + s * 2), H.readByte(0x3EE4 + e * 2),
        H.readByte(0x3EF8 + e * 2), H.readByte(0x3AA8 + s * 2)))
    end
    H.log(string.format(
      "[probe] alive: $3A74=%02X $3A75=%02X $3A76=%d $3A77=%d $3A79=%02X",
      H.readByte(0x3A74), H.readByte(0x3A75), H.readByte(0x3A76),
      H.readByte(0x3A77), H.readByte(0x3A79)))
    H.log(string.format(
      "[probe] pause flags: timeStopped($E9EF)=%02X menusShut($629A)=%02X " ..
      "$00B1=%02X $2F4B=%02X MENU=%02X MSTATE=%02X ACTOR=%02X",
      H.readByte(0x7EE9EF), H.readByte(0x7E629A), H.readByte(0x00B1),
      H.readByte(0x2F4B), H.readByte(MENU), H.readByte(MSTATE),
      H.readByte(ACTOR)))
    -- #129 round 9: message-wait state ($7ee9f5 = "skip mess_wait's own
    -- delay, DlgTextCmd_07 already waited"; $7e629e = InitMsgWindow's own
    -- nesting counter) and the raw controller latches DlgTextCmd_07 polls
    -- ($04 = last-swapped repeat-mode buttons, $0a = this frame's raw read,
    -- both via UpdateCtrl / UpdateCtrlBattle).
    H.log(string.format(
      "[probe] msg-wait state: $7ee9f5=%02X $7e629e=%02X  ctrl: $04=%02X " ..
      "$0a=%02X $6266=%02X $6268=%02X",
      H.readByte(0x7EE9F5), H.readByte(0x7E629E), H.readByte(0x04),
      H.readByte(0x0A), H.readByte(0x7E6266), H.readByte(0x7E6268)))
    local w = {}
    for a = 0x3A70, 0x3AA7 do w[#w + 1] = string.format("%02X", H.readByte(a)) end
    H.log("[probe] $3A70-3AA7: " .. table.concat(w, " "))
    -- where in the victory machinery are we parked?
    H.log(string.format(
      "[probe] gfx queue ptr $76=%04X  event ptr $8f=%02X%02X%02X  " ..
      "animBusy($62A5)=%02X %02X %02X %02X  bgIdx($ECB8)=%02X",
      H.readWord(0x76), H.readByte(0x91), H.readByte(0x90), H.readByte(0x8f),
      H.readByte(0x7E62A5), H.readByte(0x7E62A6),
      H.readByte(0x7E62A7), H.readByte(0x7E62A8), H.readByte(0x7EECB8)))
    local q = {}
    for a = 0x2D6E, 0x2D7D do q[#q + 1] = string.format("%02X", H.readByte(a)) end
    H.log("[probe] script queue $2D6E+: " .. table.concat(q, " "))
    H.log(string.format(
      "[probe] end-gates: $3EE0=%02X $3A6E=%02X $3A95=%02X $3EBC=%02X " ..
      "$2F49=%02X colosseum($3A97)=%02X",
      H.readByte(0x3EE0), H.readByte(0x3A6E), H.readByte(0x3A95),
      H.readByte(0x3EBC), H.readByte(0x2F49), H.readByte(0x3A97)))
    H.log("[probe] hit sequence since kill: " ..
      table.concat(probeTrace, " "))
    H.log(string.format("[probe] NMI flags: $46=%02X $47=%02X",
      H.readByte(0x46), H.readByte(0x47)))
    H.log(string.format("[probe] $47 reads in window: %d (spin proof)",
      probe47 or -1))
    H.log(string.format("[probe] spin site: K=%02X PC=%04X SP=%04X",
      probeK or 0xFF, probePC or 0, probeSP or 0))
    H.log("[probe] last $46 writes (PC): " .. table.concat(probe46w, " "))
    local st = {}
    for e = 0, 3 do
      st[#st + 1] = string.format("e%d:st1=%02X st4=%02X", e,
        H.readByte(0x3EE4 + e * 2), H.readByte(0x3EF8 + e * 2))
    end
    H.log("[probe] party status: " .. table.concat(st, "  "))
    H.screenshot("dancefreeze")
    H.log("[probe] DONE -- this probe always exits 0; the dump above is the deliverable")
  end),
})

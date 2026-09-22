-- @suite savestate=moogle_cleared slow
-- battle_dancemp.lua -- Dance costs MP, a flat amount paid at dance start,
-- and a pool that cannot pay it is greyed AND refused at the confirm.
--
-- The isolation arm below used to assert the opposite of that second clause:
-- the greyed row committed, the turn was spent, and the universal
-- insufficient-MP gate ate the action at execution with no feedback.  That
-- was the defect mp-economy.md ruling 2 always described as fixed
-- ("greyed and refused"); v0.19 made the ROM match the doc.  The dance
-- confirm (btlgfx UpdateMenuState_21 @85f0) now calls Ot6DanceConfirmMP,
-- which prices the row through Ot6DanceRowCost -- the leaf that drew the
-- number -- and takes its verdict from the same Ot6AbilityGrey that greyed
-- it.  battle_kitrefuse carries the same mechanism on the three kit windows.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/moogle_defense.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE, ST_TGT = 0x05, 0x21, 0x38
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
-- The two menu sounds, watched so the confirm refusal below is OBSERVED and
-- not inferred from an absence: $95 is the error buzz (magic's own, and the
-- dance window's own for an unavailable row) and $96 is the confirm sound.
-- Direct-page stores land in bank $00, so both the $0000xx and the $7e00xx
-- views are counted together.
local buzzes, confirms = 0, 0
local refused = nil

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
    -- The engine's MP-cost queue is the CIRCULAR buffer $3620-$371F
    -- (battle_main.asm "add to mp cost queue"), appended by its own
    -- counter -- a single-cell watch only worked while the fixture's
    -- battle happened to land the dance's cost at that exact position
    -- (the fled fixture parked it at $371E; the re-cut one does not).
    -- Watch the whole queue and let the command gate pick the dance's
    -- own stores.
    emu.addMemoryCallback(function(_, v)
      if v ~= 0xFF and H.readByte(0x3A7A) == CMD_DANCE then
        costs[#costs + 1] = v
      end
    end, emu.callbackType.write, 0x7E3620, 0x7E371F)
    for _, base in ipairs({ 0x000000, 0x7E0000 }) do
      emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
        emu.callbackType.write, base + 0x95, base + 0x95)
      emu.addMemoryCallback(function() confirms = confirms + 1 end,
        emu.callbackType.write, base + 0x96, base + 0x96)
    end
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
    -- terrain, same BattleBGDance row.
    local bg = H.readByte(0x11E2)
    H.assertEq(H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg), danceId,
      "same terrain, same dance: the bg-mismatch stumble cannot fire")
  end),

  mogMenu("mog's command window (isolation arm)"),
  H.call(function()
    for s = 0, 5 do
      local mhp = H.readWord(0x3BFC + s * 2)
      if mhp > 0 and mhp < 2000 then
        H.writeWord(0x3BFC + s * 2, 3000)
      end
    end
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
  -- ...and the confirm REFUSES it.  Since v0.19 the dance window carries the
  -- other half of magic's affordance: Ot6DanceConfirmMP sits in the dance
  -- confirm (btlgfx UpdateMenuState_21 @85f0) and prices the row through
  -- Ot6DanceRowCost -- the leaf that drew the 8 above -- then takes its
  -- verdict from the same Ot6AbilityGrey the colour took.  A greyed row and
  -- a refused row are therefore one row.  The refusal lands on vanilla's own
  -- @8609 buzz, which sits BEFORE the confirm sound, exactly magic's shape.
  --
  -- What this arm used to assert -- that the commit went through and the
  -- universal insufficient-MP fizzle ate it at execution -- was the defect:
  -- the turn went with it and the player was told nothing
  -- (mp-economy.md ruling 2, docs/design/narshe-descent.md).  The
  -- execution-side fizzle is still there as the backstop for a pool that
  -- moves between the commit and the resolve; battle_mpcost exercises it on
  -- that hook point now.
  danceCursorToKnown("cursor onto the learned dance's cell (isolation arm)"),
  H.call(function()
    refused = {
      mp = mpOf(mogSlot), queue = H.readByte(0x32CC + mogSlot * 2),
      state = H.readByte(0x3EF8 + mogSlot * 2) & 0x01,
      buzzes = buzzes, confirms = confirms,
    }
    costs = {}
    H.log(string.format("[isolation arm] parked on the greyed row: mp=%d "
      .. "queue=%02x", refused.mp, refused.queue))
  end),
  H.driveUntil(function() return buzzes > refused.buzzes end, 1800, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
        H.setPad(ph % 10 < 5 and { a = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "the greyed dance is confirmed and buzzes"),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = tostring(v) end
    H.log(string.format("[isolation arm] after the confirm: mp=%d state=%02x "
      .. "queue=%02x buzz(+%d) confirm(+%d) costqueue={%s}",
      mpOf(mogSlot), H.readByte(MSTATE), H.readByte(0x32CC + mogSlot * 2),
      buzzes - refused.buzzes, confirms - refused.confirms,
      table.concat(c, ",")))
    H.assertEq(buzzes > refused.buzzes, true,
      "the confirm BUZZED ($95, magic's own error sound) -- the refusal is "
      .. "observed, not inferred from an absence")
    H.assertEq(confirms, refused.confirms,
      "...and the confirm sound did NOT play: the dance window refuses "
      .. "BEFORE `inc $96`, which is vanilla magic's own shape at @81ae")
    H.assertEq(H.readByte(MSTATE), ST_DANCE,
      "the dance list is still open -- MOG is still choosing, and his turn "
      .. "is still his")
    H.assertEq(#costs, 0,
      "no action was created: nothing reached the mp-cost queue, so the "
      .. "refusal cost no turn (it used to cost one -- ruling 2)")
    H.assertEq(H.readByte(0x32CC + mogSlot * 2), refused.queue,
      "and nothing was queued for MOG")
    H.assertEq(mpOf(mogSlot), DANCE_COST - 1,
      "the pool is unmoved, and was never driven negative")
    H.assertEq(H.readByte(0x3EF8 + mogSlot * 2) & 0x01, 0,
      "the dance never started (no whole-battle state for free)")
    H.screenshot("dancemp_refused")
    -- back out of the list, then restore the real pool read at battle start;
    -- the arm's second write
    H.writeWord(0x3C08 + mogSlot * 2, mp0)
    H.log("[isolation arm] MOG's pool restored to the real " .. mp0)
  end),
  H.driveUntil(function() return H.readByte(MSTATE) == ST_CMD end, 900, {
    H.call(function()
      ph = ph + 1
      H.setPad(ph % 10 < 5 and { b = true } or {})
    end),
    H.waitFrames(1),
  }, "back out of the refused list"),

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

  H.driveUntil(function() return #costs >= 2 end, 30000, {
    H.call(function()
      ph = ph + 1
      -- Mog auto-dances; bystanders Defend to keep the pack alive; dialogs
      -- and victory pages get A.

      if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= mogSlot then
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
  }, "one more dance turn queues (free)"),
  H.call(function()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = tostring(v) end
    H.log("cmd-$13 cost queue: {" .. table.concat(c, ",") .. "}")
    H.assertEq(costs[2], 0, "a mid-dance turn queues at 0 MP -- free afterwards")
    H.screenshot("dancemp_locked")
    H.log("PASSED: the real MOG learned his dance by WINNING on this terrain, "
      .. "paid the flat 8 once from his real pool, danced the rest for free; "
      .. "the refusal below the price lives in the labeled isolation arm")
  end),
})

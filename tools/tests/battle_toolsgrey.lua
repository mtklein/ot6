-- @suite savestate=kolts_cave slow
-- battle_toolsgrey.lua -- v0.5 MP costs: the Tools window greys what Edgar
-- cannot afford, the counterpart to battle_blitzgrey on the real tools window.
--
-- Same mechanism as Blitz (see battle_blitzgrey's header): Ot6AbilityGrey
-- (ot6.asm) compares each row's MP cost to the active caster's current MP
-- ($3c08,slot*2) and returns magic's $04/$00, which Ot6ToolRowDecorate OR's into
-- the column's $21 font byte to give $25 grey.  The tools decorator also lays
-- each column out [font][cost][name] so the one font command colors the price
-- and the name together; the price display that landed just before had put the
-- cost tile ahead of the font, outside greying's reach.
--
-- Issue #75 conversion: the boundary is spent to rather than written.  This
-- file used to install an all-Edgar party into the magitek intro fight,
-- hand-write the tool records, and pin current MP to 8, which only showed the
-- grey follows a poked number.  It now boots kolts_cave (real TERRA, LOCKE and
-- EDGAR, real bag: AutoCrossbow 4, NoiseBlaster 6, Bio Blaster 8, with
-- Ot6AbilityCostTbl prices read from the ROM), fights real encounters, and
-- drives the pool to the affordability line using the tools themselves: Bio
-- Blaster casts while the pool is rich, one AutoCrossbow to finish, until
-- current MP lands in [4,7], where Bio Blaster (8) is unaffordable and
-- AutoCrossbow (4) is still affordable.
-- That is stronger than the pin: it shows the charge and the grey
-- agree, because the cell CalcAttackEffect debits is the cell the decorator
-- reads.  If a fight ends before the pool is down, the lane is paced to the
-- next natural encounter and the spend continues (MP writes back to the
-- field and loads again, battle_naturalmp's path).
--
-- What is asserted (attribute = the odd byte of a name tile's tilemap word,
-- $21 white / $25 grey):
--   1. rich pool: every owned tool the pool can afford renders white at the
--      first open, and those are the same rows that later grey, so the grey
--      is affordability-driven rather than unconditional.
--   2. spent-to boundary: with MP spent into [4,7], Bio Blaster
--      renders grey and AutoCrossbow white on one screen; NoiseBlaster
--      follows its own line (white iff mp >= 6).
--   3. the grey is the disabled bit: grey - white == $04, magic's own delta.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT = 0x05, 0x0A, 0x30, 0x38
local CMD_TOOLS, CMD_ITEM = 0x09, 0x01
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local EDGAR = 0x04
local WHITE, GREY = 0x21, 0x25
local BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW = 0xA4, 0xA3, 0xAA
local TONIC, POTION = 0xE8, 0xE9

-- the medics' battle-bag scan and target steerer (battle_magicite's medic
-- line; see the bystander branch in pulse below)
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })

local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- "Bio Blaster" spells its space as the narrow-space glyph $fe in item-name
-- records (battle_toolslist's finding); the other two are contiguous.
local function seqJoin(a, mid, b)
  local t = {}
  for _, v in ipairs(a) do t[#t + 1] = v end
  t[#t + 1] = mid
  for _, v in ipairs(b) do t[#t + 1] = v end
  return t
end
local NM = {
  [BIOBLASTER]   = { name = "Bio Blaster",
                     g = seqJoin(glyphs("Bio"), 0xfe, glyphs("Blaster")) },
  [NOISEBLASTER] = { name = "NoiseBlaster", g = glyphs("NoiseBlaster") },
  [AUTOCROSSBOW] = { name = "AutoCrossbow", g = glyphs("AutoCrossbow") },
}

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

local function map() return H.mapId() & 0x1ff end

local edgarSlot, edgarOfs = nil, nil
-- Edgar's live pool: the battle cell when a battle is up, else his field MP
-- (writeback keeps them one number; see battle_naturalmp phase 3).
local function pool()
  if H.battleLoadStarted() and edgarSlot then
    return H.readWord(0x3C08 + edgarSlot * 2)
  end
  return edgarOfs and H.readWord(0x160d + edgarOfs) or 0xFFFF
end

-- the spend plan, from the pool as read: park the pool in [4,7].
--   while mp >= 12: Bio Blaster (8), which ends in [4,11]
--   then if mp >= 8: AutoCrossbow (4), which takes [8,11] to [4,7]
local function planCast(mp)
  if mp >= 12 then return BIOBLASTER end
  if mp >= 8 then return AUTOCROSSBOW end
  return nil
end

-- ------------------------------------------------------------------------
-- The per-frame driver.  mode "spend": on Edgar's menu, walk the real
-- cursors to planCast's tool and confirm it; everyone else Defends (right
-- swaps Fight->Def, then A, which is battle_naturalmp's turn consumption).
-- mode "open": walk to the Tools list and hold it open, which is the window
-- the asserts run in.
-- Off-battle: pace the detected lane until the next natural encounter.
-- ------------------------------------------------------------------------
local mode = "spend"
local ph, lane, hb = 0, nil, -600
local lastMap = nil                     -- names any walk off map 96 (see pulse)
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then           -- heartbeat: where is the machine?
    hb = H.frame
    H.log(string.format("[hb f%d] mode=%s pool=%d batt=%s menu=%02x actor=%d "
      .. "mstate=%02x map=%d", H.frame, mode, pool(),
      tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
      H.readByte(MSTATE), map()))
  end
  local edge = ph % 10 < 5              -- 5-on/5-off press edges
  if not H.battleLoadStarted() then
    -- field: pace the lane for the next encounter; page victory/EXP dialogs
    -- with A until control returns (the battle_walletmp run-4 hazard)
    -- a map change off 96 is how the 2026-08-18 wipe surfaced (game over,
    -- then the attract-mode intro maps); name it when it happens again
    if map() ~= lastMap then
      H.log(string.format("[mapchg f%d] map %d -> %d at (%d,%d) ctl=%s "
        .. "aligned=%s lane=%s", H.frame, lastMap or -1, map(),
        H.fieldX(), H.fieldY(), tostring(H.hasControl()),
        tostring(H.tileAligned()),
        lane and string.format("(%d,%d)%s", lane.ax, lane.ay, lane.out) or "nil"))
      lastMap = map()
    end
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil          -- re-anchor at the next field return (the walletmp
                      -- run-5 hazard, where a stale anchor walks off the map)
  if H.readByte(MENU) == 0 then
    -- no menu up: page any battle dialog with A.  Measured on the first run
    -- of this conversion, this is the battle_vargas hazard: a monster's dialog
    -- blocked the whole queue for 20k+ frames of menu=00/mstate=00 with the
    -- fight otherwise alive and this driver's hands off.
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= edgarSlot then
    -- A bystander's window: heal a hurting party with real Item turns
    -- first, then real Defend (right, then A), slow cadence.  The medic
    -- half follows the re-made fixture (2026-08-18): kolts_cave now
    -- arrives at 69/160, 130/194, 170/222 -- gen_kolts's #84 chest detours
    -- walk more fights before the save -- and the defend-only version of
    -- this branch was ground down mid-spend: the run ended in a game over
    -- and the attract-mode intro march (the "paced off map 96 (now 19)"
    -- red).  Heals keep the file's design intact: the driver's only attack
    -- stays EDGAR's tools.  The plan is battle_magicite's medic line:
    -- Potion for somebody badly hurt, Tonic for the rest, worst-HP target.
    local st = H.readByte(MSTATE)
    tc.observe()
    local worst, wpct = nil, 101
    for s = 0, 3 do
      local h, m = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
      if h > 0 and m > 0 then
        local pct = h * 100 // m
        if pct < wpct then worst, wpct = s, pct end
      end
    end
    -- ST_ITEM and ST_TGT are read from the real menu, not decided by us, so
    -- once the game is actually sitting in one of them the medic finishes
    -- the heal it already opened, regardless of what wpct reads THIS frame.
    -- Measured 2026-08-19 (#122 fallout): re-gating every frame on a live
    -- wpct<55 check let a heal in flight get abandoned the moment the
    -- target's percentage ticked back above 55 mid-navigation (a real
    -- possibility once damage-per-hit changed) -- the outer branch would
    -- then fall to the plain Defend cadence while the actual screen was
    -- still the item list, so "right"/"a" landed on item-grid navigation
    -- instead of the command list, and the submenu never closed: the pool
    -- spend then sat forever at menu=01 mstate=$0a with nothing driving it.
    if st == ST_ITEM then
      local slow = ph % 30 < 5
      local want = (wpct < 45) and bagIdxOf({ POTION }) or nil
      want = want or bagIdxOf({ TONIC, POTION })
      if want == nil then H.setPad(slow and { b = true } or {}) return end
      local cur = H.readByte(0x8947 + a) + H.readByte(0x894F + a)
      if cur < want then H.setPad(slow and { down = true } or {})
      elseif cur > want then H.setPad(slow and { up = true } or {})
      else H.setPad(slow and { a = true } or {}) end
      return
    elseif st == ST_TGT then
      local btn = tc.steer(worst, ph)
      H.setPad(btn and { [btn] = true } or {})
      return
    end
    if wpct < 55 then                   -- somebody needs the heal
      if st == ST_CMD then
        local want = nil
        for i = 0, 3 do
          if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_ITEM then want = i end
        end
        if want == nil then H.setPad(edge and { x = true } or {}) return end
        local cur = H.readByte(0x890F + a)
        if cur == want then H.setPad(edge and { a = true } or {})
        elseif cur < want then H.setPad(edge and { down = true } or {})
        else H.setPad(edge and { up = true } or {}) end
      elseif st == 0x01 then
        H.setPad({})
      else
        H.setPad(edge and { b = true } or {})
      end
      return
    end
    local step = ph % 40
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local st = H.readByte(MSTATE)
  local wantTool = (mode == "spend") and planCast(pool()) or AUTOCROSSBOW
  if mode == "spend" and wantTool == nil then
    -- pool already parked: hands off, the driver's predicate ends the phase
    H.setPad({})
    return
  end
  if st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_TOOLS then wantCell = i end
    end
    assert(wantCell, "EDGAR's real command list carries Tools")
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  elseif st == ST_TOOLS then
    if mode == "open" then H.setPad({}) return end   -- window up: hold it
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == wantTool then entry = i end
    end
    if entry == nil then H.setPad({}) return end     -- list still building
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else H.setPad(edge and { a = true } or {}) end
  elseif st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == 0x01 then
    H.setPad({})                        -- transitional: hands off
  else
    H.setPad(edge and { b = true } or {})
  end
end

-- drive until Edgar's Tools window is open and settled (for the asserts)
local function openToolsWindow(what)
  return H.repeatN(1, {
    H.call(function() mode = "open" end),
    H.driveUntil(function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == edgarSlot and H.readByte(MSTATE) == ST_TOOLS
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),                   -- let every row finish drawing
  })
end

local function liveBattle()
  return H.battleLoadStarted() and H.monstersPresent() > 0
end

-- Pin the live pack tall ($3BFC is battle current-HP, dancemp's staging) so the
-- spend can actually reach the boundary.  #124's re-rolled RNG made EDGAR's
-- tool target die under him mid-spend: with no live target the cast cannot
-- confirm and the pool stalls in target-select (measured 2026-08-20: parked at
-- 27 MP in ST_TGT for the whole 150000-frame budget), and every kill that DOES
-- land levels EDGAR and refills his pool, undoing the walk down.  Keeping the
-- pack alive gives every cast a target and stops the refills, so the pool
-- drains straight into [4,7]; the bystander medic already in `pulse` keeps the
-- party standing through the extra rounds.
local function pinPackTall()
  for s = 0, 5 do
    local hp = H.readWord(0x3BFC + s * 2)
    if hp > 0 and hp < 3000 then H.writeWord(0x3BFC + s * 2, 3000) end
  end
end

-- the same open, but it gives up the moment the battle ends rather than
-- burning its whole budget: the boundary arm below retries on a fresh fight
local function openToolsWindowOrEnd(what)
  return H.repeatN(1, {
    H.call(function() mode = "open" end),
    H.driveUntil(function()
      return not liveBattle()
        or (H.readByte(MENU) ~= 0
            and H.readByte(ACTOR) == edgarSlot
            and H.readByte(MSTATE) == ST_TOOLS)
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),
  })
end

H.run({ maxFrames = 300000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function()
    H.assertEq(map(), 96, "kolts_cave on map 96")
    -- Edgar's field record: $1600 offsets via the character id, so the pool
    -- can be read before the first battle seeds slot indices.
    for c = 0, 15 do
      if H.readByte(0x1850 + c) & 0x07 ~= 0 and c == EDGAR then
        edgarOfs = 37 * c               -- $160d + 37*char (kolts party layout)
      end
    end
    -- $160d stride: the field record is 37 bytes from $1600; MP cur at +$0d.
    edgarOfs = 37 * EDGAR
    H.log(string.format("EDGAR field MP as saved: %d", H.readWord(0x160d + edgarOfs)))
    H.assertEq(H.readWord(0x160d + edgarOfs) >= 8, true,
      "positive control: the saved pool can afford a Bio Blaster, so the "
      .. "first open has at least one white row that will later grey")
  end),

  -- first natural encounter
  H.driveUntil(function() return H.battleLoadStarted() end, 8600,
    { H.call(pulse), H.waitFrames(1) }, "a cave encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == EDGAR then edgarSlot = s end
    end
    assert(edgarSlot, "EDGAR present (kolts party)")
    H.log(string.format("EDGAR slot %d, battle pool %d", edgarSlot, pool()))
  end),

  -- 1. rich pool: the first open, everything affordable renders white -------
  openToolsWindow("edgar's tools window, rich pool"),
  H.call(function()
    local mp = pool()
    H.screenshot("tools_grey_rich")
    for _, id in ipairs({ BIOBLASTER, NOISEBLASTER, AUTOCROSSBOW }) do
      local a = attrOf(NM[id].g)
      local want = (mp >= costOf(id)) and WHITE or GREY
      H.log(string.format("  rich pool (%d MP): %-12s attr=%s want $%02x",
        mp, NM[id].name, a and string.format("$%02x", a) or "nil", want))
      H.assertEq(a, want, string.format(
        "%s (cost %d, MP %d) renders %s at the rich pool",
        NM[id].name, costOf(id), mp, want == WHITE and "white" or "grey"))
    end
    H.assertEq(pool() >= 8, true,
      "the rich-pool pass had Bio Blaster white -- the row that must grey below")
  end),

  -- 2. spend to the boundary with the tools themselves, and read the window
  --    WHILE the pool is still there ---------------------------------------
  --
  -- The spend and the read have to happen inside the same fight.  OT6 gives
  -- back HP and MP in full on a level up (ot6_progression.asm:3-6, called
  -- from battle_main.asm:16251), and a level up lands on the victory screen,
  -- so a boundary reached on the last turn of a fight is gone before the
  -- next window opens.  Measured 2026-08-13 on the failing run: the pool was
  -- parked at 7, the fight ended, EDGAR levelled, and the window that the
  -- assertion read was drawn on a refilled 68 -- correctly white, against an
  -- assertion that had been told the pool was 7.  The old code asserted the
  -- pool at one moment and read the window at another with a battle boundary
  -- allowed in between.
  --
  -- There is no step that just waits for that fight to end, either.  This
  -- driver's only attack is EDGAR's tools, and planCast stops casting once
  -- the pool is parked, so with the boundary reached nobody left in the
  -- party can kill anything: two versions that tried to "let the fight
  -- finish" simply burned their budget with a submenu held open, which
  -- freezes battle time on top of it.
  --
  -- So each attempt reads twice: once in the fight that reached the
  -- boundary, and, if that fight has already ended (the cast that parks the
  -- pool is often the one that kills the last monster), once at the start of
  -- the next fight, where EDGAR has a full turn cycle and nothing has died.
  -- MP persists across battles; the only thing that undoes the boundary is a
  -- level up on the way out, and then the next attempt spends again.
  --
  -- Three attempts, the house limit.
  (function()
    local done = false
    local function inWindow() local m = pool() return m >= 4 and m <= 7 end
    local function reseat()
      -- a fresh fight can seat EDGAR in a different slot
      for s = 0, 3 do
        if H.readByte(0x3ED8 + s * 2) == EDGAR then edgarSlot = s end
      end
    end
    local function tryRead(tag)
      return H.cond(function() return not done and liveBattle() and inWindow() end, {
        H.call(function()
          reseat()
          H.log(string.format("%s: EDGAR slot %d, pool %d MP",
            tag, edgarSlot, pool()))
          mode = "open"
        end),
        openToolsWindowOrEnd("edgar's tools window, " .. tag),
        H.cond(function()
          return liveBattle() and H.readByte(MSTATE) == ST_TOOLS
            and H.readByte(ACTOR) == edgarSlot and inWindow()
        end, {
          H.call(function()
            local mp = pool()
            H.screenshot("tools_grey_display")
            local aBio = attrOf(NM[BIOBLASTER].g)
            local aNoise = attrOf(NM[NOISEBLASTER].g)
            local aXbow = attrOf(NM[AUTOCROSSBOW].g)
            local fmt = function(a)
              return a and string.format("$%02x", a) or "nil"
            end
            H.log(string.format("spent pool (%d MP): Bio=%s Noise=%s Xbow=%s",
              mp, fmt(aBio), fmt(aNoise), fmt(aXbow)))
            H.assertEq(mp >= 4 and mp <= 7, true,
              "the pool is STILL in [4,7] at the read: Bio Blaster "
              .. "unaffordable, AutoCrossbow affordable, both on one screen")
            H.assertEq(aBio, GREY, string.format(
              "Bio Blaster (cost 8, MP %d) renders grey -- the charge "
              .. "priced it out", mp))
            H.assertEq(aXbow, WHITE, string.format(
              "AutoCrossbow (cost 4, MP %d) renders white -- still "
              .. "affordable", mp))
            H.assertEq(aNoise, (mp >= 6) and WHITE or GREY,
              "NoiseBlaster follows its own affordability line")
            H.assertEq(aBio - aXbow, 0x04,
              "grey - white == $04, magic's own disabled-bit delta")
            done = true
          end),
        }, {}),
      }, {})
    end
    local function attempt(n)
      return H.cond(function() return done end, {}, {
        -- spend across as many fights as it takes: a cave fight is about one
        -- EDGAR turn long and the pool starts at 51, so the walk down is not
        -- something one fight can do.
        H.call(function() mode = "spend" end),
        H.driveUntil(function() return pool() <= 7 end, 150000,
          { H.call(function() pinPackTall(); pulse() end), H.waitFrames(1) },
          "the pool is spent into the boundary (attempt " .. n .. ")"),
        tryRead("the fight that spent it (attempt " .. n .. ")"),
        H.cond(function() return done end, {}, {
          H.call(function() mode = "spend" end),
          H.driveUntil(function() return liveBattle() end, 40000,
            { H.call(pulse), H.waitFrames(1) },
            "the next battle to read the boundary in (attempt " .. n .. ")"),
          tryRead("the next fight's first turn (attempt " .. n .. ")"),
        }),
      })
    end
    return H.repeatN(1, {
      attempt(1), attempt(2), attempt(3),
      H.call(function()
        H.assertEq(done, true,
          "the boundary window was read while the pool was still parked in "
          .. "[4,7], within three attempts")
        H.log("PASSED: the tools window greys exactly what the SPENT pool "
          .. "cannot afford -- the charge and the grey read the same cell")
      end),
    })
  end)(),
})

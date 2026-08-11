-- @suite savestate=vargas_won slow
-- battle_walletmp.lua -- issue #35: the costed submenus carry a wallet, which
-- is the actor's current MP painted at the top of the open list window,
-- beside the per-row costs those windows already show.
--
-- Placement (measured, probe_wallet): the ability-list windows stage their
-- rows into the $7c00 menu map at rows 1/3/5/7, cols 2-26; row 0 is never
-- staged and renders on the window's top edge.  The wallet is
-- [M][P][d][d][d] at row 0 cols 22-26, which is vram words $7c16-$7c1a, staged
-- by Ot6WalletStage from $3c08, the cell CalcAttackEffect's universal
-- charge debits, and painted every nmi by the flush (blanked one-shot on
-- close or switch so Magic and Item lists never inherit it).
--
-- Issue #75 conversion: the wallet follows spent MP, and real casters.
-- This file used to install synthetic all-Sabin and all-Terra parties into the
-- magitek intro, stop the monsters, pin party and monster HP, stage the pools
-- with one labeled poke (47), poke a live change (123) to watch the repaint,
-- and bench bystanders by writing their status bits.  It now boots vargas_won:
-- the real party (TERRA LOCKE EDGAR SABIN), a real ledge encounter, and the
-- pools the save carries.  Poking $3c08 only showed the paint follows a poke;
-- spending MP shows it follows the game, so the live-tracking poke arm
-- is retired in favor of the drop arm, and the old 47 -> 123 mid-run switch
-- becomes two casters with different pools (Sabin's Blitz window,
-- then Edgar's Tools window, both tools-shell $30 consumers of the same
-- wallet).  Bystander turns are consumed with real Defends; battle dialogs
-- are paged with A (the battle_vargas hazard).
--
-- Asserted:
--   1. wallet: SABIN's open Blitz list paints M P <his current MP>, with the
--      value read live from $3c08 at the moment of the assert, in white $21.
--   2. drop: after his real Pummel resolves (4 MP, Ot6AbilityCostTbl),
--      his own reopened Blitz window shows exactly the charge less.  This is
--      the payer's window, and the assertion spent its old life unreachable
--      behind an `if who == actor` guard (see the pre-conversion header).
--   3. two casters: EDGAR's Tools window, opened next, paints EDGAR's pool,
--      a different number (asserted different), read from his cell.  The
--      wallet is per-actor rather than a stale singleton.
--   4. cleanup: the vanilla Magic list, opened after a wallet was up, does
--      not carry the wallet cells (the one-shot blank on switch).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_MAGIC, ST_TGT = 0x05, 0x30, 0x0E, 0x38
local CMD_MAGIC, CMD_TOOLS, CMD_BLITZ = 0x02, 0x09, 0x0A
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local SABIN, EDGAR = 0x05, 0x04
local PUMMEL, PUMMEL_COST = 0x5D, 4     -- Ot6AbilityCostTbl (asserted below)
local WALLET = 0x7C16                    -- vram word: $7c00 map, row 0, col 22
local GLYPH_M, GLYPH_P, BLANK = 0x8C, 0x8F, 0xFF
local ZERO = 0xB4

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

local function map() return H.mapId() & 0x1ff end
local function mpOf(slot) return H.readWord(0x3C08 + slot * 2) end

local function walletWords()
  local t = {}
  for i = 0, 4 do
    t[i + 1] = emu.readWord((WALLET + i) * 2, emu.memType.snesVideoRam)
  end
  return t
end

-- expected wallet glyphs for a value (leading zeros blank, ones always)
local function expect(v)
  local h, t = math.floor(v / 100) % 10, math.floor(v / 10) % 10
  local gh = (h == 0) and BLANK or (ZERO + h)
  local gt = (t == 0 and h == 0) and BLANK or (ZERO + t)
  return { GLYPH_M, GLYPH_P, gh, gt, ZERO + v % 10 }
end

local function assertWallet(tag, v)
  local w, e = walletWords(), expect(v)
  local got = {}
  for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
  H.log(string.format("%s: wallet vram = %s (MP=%d)", tag, table.concat(got, " "), v))
  for i = 1, 5 do
    H.assertEq(w[i] & 0xFF, e[i], string.format("%s: wallet cell %d glyph", tag, i))
    H.assertEq(w[i] >> 8, 0x21, string.format("%s: wallet cell %d white", tag, i))
  end
end

-- ------------------------------------------------------------------------
-- the family driver (battle_toolsgrey's), controlled by a mode table: reach
-- `char`'s window for command `cmd`, then either hold the target state open
-- or pick `entry` and confirm.  Bystanders Defend; dialogs are paged.
-- ------------------------------------------------------------------------
local slotOf = {}
local mode = nil          -- { char=, cmd=, state=, hold=true } or { cast=id }
local ph, hb, lane = 0, -600, nil
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then
    hb = H.frame
    H.log(string.format("[hb f%d] batt=%s menu=%02x actor=%d mstate=%02x",
      H.frame, tostring(H.battleLoadStarted()), H.readByte(MENU),
      H.readByte(ACTOR), H.readByte(MSTATE)))
  end
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    -- a pack died under the drives (measured: run 3's pack ended before the
    -- Edgar arm), so pace the lane to the next natural encounter; the pools
    -- ride the writeback, so every arm continues where it stood.  Until
    -- control returns, page the victory, EXP and level-up dialogs with A
    -- (measured: run 4 sat behind them for 40k frames with hands off).
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
      end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil          -- re-anchor the lane at wherever the next field return
                      -- stands: a stale anchor walks one direction forever
                      -- (measured: run 5 marched off map 98 onto map 19)
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})     -- page battle dialogs
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= slotOf[mode.char] then
    -- bystander: back out of any submenu a previous held-open arm left up
    -- (measured: arm 3 holds Edgar's tools list, and a blind cadence then
    -- oscillates $30 and $38 in it forever), then a real Fight rather than a
    -- Defend, because an all-defend party erodes to a wipe over a long run
    -- (measured, run 6: ~5k frames of victory-screen garbage then map 19),
    -- while Fights end packs fast and the driver re-encounters.
    local st = H.readByte(MSTATE)
    if st == ST_TGT then
      H.setPad(ph % 10 < 5 and { a = true } or {})
    elseif st ~= ST_CMD then
      H.setPad(ph % 10 < 5 and { b = true } or {})
    elseif H.readByte(0x890F + a) > 0 then
      H.setPad(ph % 10 < 5 and { up = true } or {})   -- cursor onto Fight
    else
      H.setPad(ph % 10 < 5 and { a = true } or {})
    end
    return
  end
  local st = H.readByte(MSTATE)
  if st == mode.state and mode.hold then H.setPad({}) return end
  if st == ST_CMD then
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == mode.cmd then wantCell = i end
    end
    assert(wantCell, string.format("char %d's real command list carries $%02x",
      mode.char, mode.cmd))
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then H.setPad(edge and { a = true } or {})
    elseif cur < wantCell then H.setPad(edge and { down = true } or {})
    else H.setPad(edge and { up = true } or {}) end
  elseif st == ST_TOOLS and mode.cast then
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == mode.cast then entry = i end
    end
    if entry == nil then H.setPad({}) return end
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
    elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
    else H.setPad(edge and { a = true } or {}) end
  elseif st == ST_TGT then
    H.setPad(edge and { a = true } or {})
  elseif st == 0x01 then
    H.setPad({})
  else
    H.setPad(edge and { b = true } or {})
  end
end

local function reachWindow(m, what)
  return H.repeatN(1, {
    H.call(function() mode = m end),
    H.driveUntil(function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == slotOf[m.char]
         and H.readByte(MSTATE) == m.state
    end, 30000, { H.call(pulse), H.waitFrames(1) }, what),
    H.waitFrames(20),                   -- let the wallet stage + flush
  })
end

local sabinPre = nil

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    H.assertEq(costOf(PUMMEL), PUMMEL_COST,
      "Pummel's charge-table price is the 4 this file's drop arm counts on")
  end),

  -- natural encounter (battle_naturalmp's lane pacing)
  (function()
    local lane = nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 12600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a ledge encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[SABIN], "SABIN present (vargas_won party)")
    assert(slotOf[EDGAR], "EDGAR present (vargas_won party)")
    assert(slotOf[0x00], "TERRA present (the innate mage for the magic arm)")
    H.log(string.format("SABIN slot %d pool %d, EDGAR slot %d pool %d",
      slotOf[SABIN], mpOf(slotOf[SABIN]), slotOf[EDGAR], mpOf(slotOf[EDGAR])))
    H.assertEq(mpOf(slotOf[SABIN]) ~= mpOf(slotOf[EDGAR]), true,
      "the two casters' REAL pools differ -- the per-actor arm below can "
      .. "tell them apart without a poke")
  end),

  -- 1. the wallet on SABIN's real Blitz window ------------------------------
  reachWindow({ char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, hold = true },
    "sabin's blitz window"),
  H.call(function()
    sabinPre = mpOf(slotOf[SABIN])
    assertWallet("sabin", sabinPre)
    H.screenshot("walletmp_blitz")
  end),

  -- 2. the drop: a real Pummel, then the payer's own reopened window --------
  reachWindow({ char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, cast = PUMMEL },
    "sabin's blitz window (casting)"),
  H.driveUntil(function()
    return mpOf(slotOf[SABIN]) == sabinPre - PUMMEL_COST
  end, 20000, { H.call(pulse), H.waitFrames(1) }, "the Pummel charge lands"),
  H.call(function()
    H.assertEq(mpOf(slotOf[SABIN]), sabinPre - PUMMEL_COST,
      "Pummel charged exactly its table price from the real pool")
  end),
  reachWindow({ char = SABIN, cmd = CMD_BLITZ, state = ST_TOOLS, hold = true },
    "the payer's blitz window reopens"),
  H.call(function()
    H.assertEq(H.readByte(ACTOR), slotOf[SABIN],
      "the reopened list belongs to the character who paid")
    assertWallet("post-charge reopen", mpOf(slotOf[SABIN]))
    H.assertEq(mpOf(slotOf[SABIN]), sabinPre - PUMMEL_COST,
      "the reopened wallet shows the drop -- the real cast's price, in the "
      .. "payer's own window")
  end),

  -- 3. the second caster: EDGAR's Tools window paints EDGAR's pool ----------
  reachWindow({ char = EDGAR, cmd = CMD_TOOLS, state = ST_TOOLS, hold = true },
    "edgar's tools window"),
  H.call(function()
    local e = mpOf(slotOf[EDGAR])
    assertWallet("edgar", e)
    H.assertEq(e ~= mpOf(slotOf[SABIN]), true,
      "and it is a DIFFERENT number than Sabin's -- the wallet is per-actor")
    H.screenshot("walletmp_tools")
  end),

  -- 4. the vanilla Magic list stays wallet-free -----------------------------
  -- TERRA's Magic command (the party's innate mage; measured: a spell-less
  -- Edgar's battle command row carries no $02 even though his field record
  -- does, so only a character who knows a spell can open this list) is the next
  -- window after a wallet was up, so the one-shot blank on switch must have
  -- wiped the wallet cells.
  reachWindow({ char = 0x00, cmd = CMD_MAGIC, state = ST_MAGIC, hold = true },
    "terra's magic list (browse $0e)"),
  H.call(function()
    local w = walletWords()
    local got = {}
    for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
    H.log("magic window wallet cells: " .. table.concat(got, " "))
    for i = 1, 5 do
      -- the magic window paints its own fill over the area ($25ff observed
      -- for an empty list); what must not survive is the wallet's glyphs
      H.assertEq(w[i] & 0xFF, 0xFF, string.format(
        "magic list cell %d carries no wallet glyph -- blanked on switch", i))
    end
    H.screenshot("walletmp_magic_clean")
  end),
  H.logStep(function() return "battle_walletmp complete -- the wallet paints "
    .. "each caster's own SPENT pool and leaves the magic list clean" end),
})

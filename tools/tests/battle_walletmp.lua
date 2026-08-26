-- @suite savestate=vargas_won slow
-- battle_walletmp.lua -- the costed submenus carry a wallet: the actor's
-- current MP painted at the top of the open list window, beside the
-- per-row costs those windows already show.
--
-- Asserts: SABIN's open Blitz list paints his current MP; after his real
-- Pummel resolves, his reopened Blitz window shows the charge deducted;
-- EDGAR's Tools window paints his own (different) pool; the vanilla Magic
-- list carries no wallet cells.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_MAGIC, ST_TGT = 0x05, 0x30, 0x0E, 0x38
local CMD_MAGIC, CMD_TOOLS, CMD_BLITZ = 0x02, 0x09, 0x0A
local CMDTBL, ITEMLIST = 0x202E, 0x4005
local SABIN, EDGAR = 0x05, 0x04
local PUMMEL, PUMMEL_COST = 0x5D, 4     -- Ot6AbilityCostTbl
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
-- driven by a mode table: reach `char`'s window for command `cmd`, then
-- either hold the target state open or pick `entry` and confirm.
-- Bystanders Defend; dialogs are paged.
-- ------------------------------------------------------------------------
local slotOf = {}
local mode = nil          -- { char=, cmd=, state=, hold=true } or { cast=id }
local ph, hb, lane = 0, -600, nil
local holdBlank = 0        -- frames a held costed window has shown a blank wallet
local WALLET_SETTLE = 90   -- frames the wallet needs to settle after a reopen
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local function pulse()
  ph = ph + 1
  if H.frame - hb >= 600 then
    hb = H.frame
    H.log(string.format("[hb f%d] batt=%s menu=%02x actor=%d mstate=%02x wallet=%04x",
      H.frame, tostring(H.battleLoadStarted()), H.readByte(MENU),
      H.readByte(ACTOR), H.readByte(MSTATE), walletWords()[1]))
  end
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
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
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})     -- page battle dialogs
    return
  end
  local a = H.readByte(ACTOR)
  if a ~= slotOf[mode.char] then
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
  if st ~= mode.state then holdBlank = 0 end
  if st == mode.state and mode.hold then
    local w = walletWords()
    if (w[1] & 0xFF) == GLYPH_M and (w[2] & 0xFF) == GLYPH_P then
      holdBlank = 0
      H.setPad({})
      return
    end
    holdBlank = holdBlank + 1
    if holdBlank < WALLET_SETTLE then H.setPad({}) return end
    H.setPad(ph % 10 < 5 and { b = true } or {})   -- reopen fresh to re-stage
    return
  end
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

local function settleWallet(tag)
  return H.driveUntil(function()
    if not (H.battleLoadStarted() and H.readByte(MENU) ~= 0
            and H.readByte(ACTOR) == slotOf[mode.char]
            and H.readByte(MSTATE) == mode.state) then return false end
    local w = walletWords()
    return (w[1] & 0xFF) == GLYPH_M and (w[2] & 0xFF) == GLYPH_P
  end, 30000, { H.call(pulse), H.waitFrames(1) },
    tag .. ": the wallet header paints")
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

  -- natural encounter: walk a lane until a random battle fires
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
  settleWallet("sabin"),
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
  settleWallet("post-charge reopen"),
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
  settleWallet("edgar"),
  H.call(function()
    local e = mpOf(slotOf[EDGAR])
    assertWallet("edgar", e)
    H.assertEq(e ~= mpOf(slotOf[SABIN]), true,
      "and it is a DIFFERENT number than Sabin's -- the wallet is per-actor")
    H.screenshot("walletmp_tools")
  end),

  reachWindow({ char = 0x00, cmd = CMD_MAGIC, state = ST_MAGIC, hold = true },
    "terra's magic list (browse $0e)"),
  H.call(function()
    local w = walletWords()
    local got = {}
    for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
    H.log("magic window wallet cells: " .. table.concat(got, " "))
    for i = 1, 5 do
      -- the magic window fills this area itself; the wallet glyph must not survive
      H.assertEq(w[i] & 0xFF, 0xFF, string.format(
        "magic list cell %d carries no wallet glyph -- blanked on switch", i))
    end
    H.screenshot("walletmp_magic_clean")
  end),
  H.logStep(function() return "battle_walletmp complete -- the wallet paints "
    .. "each caster's own SPENT pool and leaves the magic list clean" end),
})

-- @suite
-- battle_walletmp.lua -- issue #35: the costed submenus carry a WALLET --
-- the actor's CURRENT MP painted at the top of the open list window,
-- beside the per-row costs those windows already show.
--
-- Placement (measured, probe_wallet): the ability-list windows stage their
-- rows into the $7c00 menu map at rows 1/3/5/7, cols 2-26; row 0 is never
-- staged and renders on the window's top edge.  The wallet is
-- [M][P][d][d][d] at row 0 cols 22-26 = vram words $7c16-$7c1a, staged by
-- Ot6WalletStage from $3c08 -- the very cell CalcAttackEffect's universal
-- charge debits -- and painted every nmi by the flush (blanked one-shot on
-- close/switch so Magic/Item lists never inherit it).
--
-- Asserted:
--   1. NON-CASTER: an installed all-Blitz SABIN opens Blitz and the wallet
--      cells spell M P <his current MP> -- the value read live from $3c08,
--      not a constant.  (MP staged once at battle start, battle_naturalmp's
--      no-per-frame-pinning discipline: the fixture's guests carry ~0 MP,
--      so one labeled poke stands in for a real pool.)
--   2. LIVE: while the window is open, a poked $3c08 change repaints the
--      wallet within a few frames (the mechanism that makes the number
--      drop the frame a queued verb's cost is paid).
--   3. CASTER: the same window under an installed TERRA (knows spells)
--      shows her pool the same way -- the wallet is universal.
--   4. DROP: after Sabin's Pummel resolves, reopening Blitz -- THE PAYING
--      CHARACTER'S OWN Blitz -- shows exactly its 4 MP less.  ("two less"
--      here until 2026-07-30: #45 repriced Pummel 2 -> 4 and this half of
--      the file was never updated, because it was never running.  See the
--      note above the phase.)
--   5. CLEANUP: the vanilla Magic list, opened after, does NOT carry the
--      wallet cells (the one-shot blank on switch).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local WALLET = 0x7C16                    -- vram word: $7c00 map, row 0, col 22
local GLYPH_M, GLYPH_P, BLANK = 0x8C, 0x8F, 0xFF
local ZERO = 0xB4

local msPresent = {}
local mode = "sabin"

-- When set to a party slot, every OTHER party slot is STOPped so only that
-- slot's gauge can fill and only that slot can own the next command window.
-- Phase 4 needs it: the wallet paints the OPEN LIST OWNER's pool, so the drop
-- can only be read from the window of the character who actually paid.
local benchTo = nil

local function pinField()
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
      if mode == "sabin" then
        H.writeByte(0x3ED8 + s * 2, 0x05)               -- CHAR::SABIN
        for i = 0, 3 do H.writeByte(0x202E + s * 12 + i * 3, 0x0A) end
      elseif mode == "terra" then
        H.writeByte(0x3ED8 + s * 2, 0x00)               -- CHAR::TERRA (caster)
        H.writeByte(0x202E + s * 12 + 0 * 3, 0x0A)      -- Blitz
        H.writeByte(0x202E + s * 12 + 1 * 3, 0xFF)
        H.writeByte(0x202E + s * 12 + 2 * 3, 0xFF)
        H.writeByte(0x202E + s * 12 + 3 * 3, 0xFF)
      else                                              -- "magic"
        H.writeByte(0x3ED8 + s * 2, 0x00)               -- TERRA, Magic first
        H.writeByte(0x202E + s * 12 + 0 * 3, 0x02)      -- Magic
        H.writeByte(0x202E + s * 12 + 1 * 3, 0xFF)
        H.writeByte(0x202E + s * 12 + 2 * 3, 0xFF)
        H.writeByte(0x202E + s * 12 + 3 * 3, 0xFF)
      end
      H.writeWord(0x3BF4 + s * 2, 999)
    end
  end
  if benchTo then
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
        local st3 = 0x3EF8 + s * 2
        if s == benchTo then
          H.writeByte(st3, H.readByte(st3) & 0xEF)
        else
          H.writeByte(st3, H.readByte(st3) | 0x10)      -- stopped
        end
      end
    end
  end
  H.writeByte(0x1D28, 0x01)                             -- known: Pummel
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)   -- stopped
    if H.readWord(0x3BFC + m * 2) < 0x6000 then
      H.writeWord(0x3BFC + m * 2, 0xF000)
    end
  end
end

local function walletWords()
  local t = {}
  for i = 0, 4 do
    t[i + 1] = emu.readWord((WALLET + i) * 2, emu.memType.snesVideoRam)
  end
  return t
end

-- expected wallet glyphs for a value (leading zeros blank, ones always)
local function expect(v)
  local h, t, o = math.floor(v / 100) % 10, math.floor(v / 10) % 10, v % 10
  local gh = (h == 0) and BLANK or (ZERO + h)
  local gt = (t == 0 and h == 0) and BLANK or (ZERO + t)
  return { GLYPH_M, GLYPH_P, gh, gt, ZERO + o }
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

local function openList(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == 0x30 end, 1500, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, what)
end

local function closeList(what)
  return H.driveUntil(function() return H.readByte(MSTATE) ~= 0x30 end, 300, {
    H.call(function() H.setPad({ "b" }) end), H.waitFrames(2),
    H.call(function() H.setPad({}) end), H.waitFrames(2),
  }, what)
end

local actor, mpPre

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    pinField()
    -- ONE labeled MP staging (the guests' natural pools are ~0); never
    -- re-pinned, so every later read/drop is the machine's own arithmetic
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
        H.writeWord(0x3C30 + s * 2, 99)
        H.writeWord(0x3C08 + s * 2, 47)
      end
    end
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),

  -- 1. non-caster wallet ---------------------------------------------------
  openList("blitz list opens (Sabin, non-caster)"),
  H.waitFrames(20),
  H.call(function()
    actor = H.readByte(ACTOR)
    assertWallet("sabin", H.readWord(0x3C08 + actor * 2))
    H.screenshot("walletmp_blitz")
  end),

  -- 2. live tracking -------------------------------------------------------
  H.call(function() H.writeWord(0x3C08 + actor * 2, 123) end),
  H.waitFrames(6),
  H.call(function()
    assertWallet("live-repaint (poked 123)", 123)
    H.writeWord(0x3C08 + actor * 2, 47)
  end),
  H.waitFrames(6),

  -- 4. the drop: latch Pummel, let it resolve, reopen ----------------------
  H.call(function() mpPre = H.readWord(0x3C08 + actor * 2) end),
  H.driveUntil(function() return H.readByte(MSTATE) ~= 0x30 end, 900, {
    H.call(function() H.setPad({ "a" }) end),   -- pick Pummel + confirm target
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "Pummel latched (list closes)"),
  H.driveUntil(function()
    return H.readWord(0x3C08 + actor * 2) ~= mpPre
  end, 12000, {
    H.waitFrames(2),                            -- hands off: wait mode
  }, "the Pummel resolves (MP charged)"),
  H.call(function()
    H.assertEq(H.readWord(0x3C08 + actor * 2), mpPre - 4,
      "Pummel charged its 4 MP")
  end),
  -- THE REOPEN MUST BE THE PAYER'S OWN WINDOW.  The wallet paints the pool of
  -- whoever owns the open list, so a reopen owned by a bystander carries that
  -- bystander's untouched MP and says nothing about the drop.  This is exactly
  -- how the assertion below spent its life dead: it was guarded by
  -- `if who == actor`, and `who` was never `actor` (measured 2026-07-30:
  -- who=1, actor=2), so the whole of item 4 never ran -- with a stale `- 2`
  -- inside it that #45 had already repriced to 4, i.e. it would have failed
  -- the moment it did run.
  --
  -- Bench the other three so only the payer's gauge fills.  Benching does NOT
  -- close a window a bystander is ALREADY holding, and this fixture runs in
  -- Wait mode where an open window freezes the battle clock (battle_thief.lua:
  -- 388-404 measured the same hazard), so pending windows are walked out with
  -- A first -- each bystander takes row 0 and hands the clock back.
  H.call(function() benchTo = actor end),
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
  end, 12000, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= actor then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(10),
  }, "the paying actor owns the reopened command window"),
  openList("blitz reopens after the charge"),
  H.waitFrames(20),
  H.call(function()
    local who = H.readByte(ACTOR)
    H.assertEq(who, actor, "the reopened list belongs to the character who paid")
    assertWallet("post-charge reopen", H.readWord(0x3C08 + who * 2))
    H.assertEq(H.readWord(0x3C08 + who * 2), mpPre - 4,
      "the reopened wallet shows the drop -- Pummel's 4 MP, the price #45 set")
  end),
  H.call(function() benchTo = nil end),
  closeList("blitz closes"),

  -- 3 + 5. caster wallet, then the Magic list stays wallet-free ------------
  H.call(function() mode = "terra"; pinField() end),
  H.waitFrames(20),
  openList("blitz list opens (Terra, caster)"),
  H.waitFrames(20),
  H.call(function()
    local who = H.readByte(ACTOR)
    assertWallet("terra", H.readWord(0x3C08 + who * 2))
    H.screenshot("walletmp_terra")
  end),
  closeList("terra's blitz closes"),
  H.call(function() mode = "magic"; pinField() end),
  H.waitFrames(20),
  H.driveUntil(function() return H.readByte(MSTATE) == 0x0e end, 1500, {
    H.call(function()
      pinField()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(12),
  }, "the Magic list opens (browse $0e)"),
  H.waitFrames(20),
  H.call(function()
    local w = walletWords()
    local got = {}
    for i = 1, 5 do got[i] = string.format("%04x", w[i]) end
    H.log("magic window wallet cells: " .. table.concat(got, " "))
    for i = 1, 5 do
      -- the magic window paints its own fill over the area ($25ff observed
      -- for an empty list); what must NOT survive is the wallet's glyphs
      H.assertEq(w[i] & 0xFF, 0xFF, string.format(
        "magic list cell %d carries no wallet glyph -- blanked on switch", i))
    end
    H.screenshot("walletmp_magic_clean")
  end),
  H.logStep(function() return "battle_walletmp complete" end),
})

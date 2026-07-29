-- probe_esperdetail_anchor.lua -- issue #27's verification instrument.
--
-- The SAME menu drive and cell-level assertions as menu_esperdetail.lua (the
-- suite test), booted instead from a COLD Continue off the tracked post-Opera
-- battery anchor, which survives ROM changes (issue #9) where savestate
-- fixtures do not.  Run it in a tree whose fixtures are stale against a fresh
-- menu-bank build:
--
--   OT6_SRAM_ANCHOR=tools/tests/anchors/post-opera-v1 \
--     tools/tests/run.sh tools/tests/probe_esperdetail_anchor.lua
--
-- The Continue sequence is gen_vector_doorstep.lua's.  The party is LOCKE
-- CELES SABIN EDGAR on the world map at (137,203); the field menu opens from
-- the world map exactly as from a field map.  The esper inventory is pinned
-- to exactly IFRIT (+5 vigor) and TERRATO (no mod) as in the suite test.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99
local SKILLCOLOR = 0x79
local ESPERS     = 0x1a69
local GENJULIST  = 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local IFRIT, TERRATO = 1, 4

local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

local CH_W, CH_PLUS, CH_5 = 0x96, 0xca, 0xb9
local BLANK = 0xff

local function st() return H.readByte(ZMENUSTATE) end

-- Walk the esper list cursor onto the slot holding esper `idx`.  The list is
-- a TWO-COLUMN grid (GenjuCursorProp `cursor_prop {0,0},{2,8}`, skills.asm):
-- $4b is a linear slot index whose parity is the column, so down/up move by
-- 2 and a parity change needs a left/right press first.  Direction-aware
-- because the slot the list restores after a detail-page exit is not
-- reliably the slot it left from.  4-frames-on/4-off gives clean press
-- edges.
local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return st() == ST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do
        if H.readByte(GENJULIST + r) == idx then target = r; break end
      end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then                -- wrong column: fix parity first
        if row % 2 == 0 then
          H.setPad(row >= 26 and { up = true } or { right = true })
        else
          H.setPad({ left = true })
        end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end

local function assertDeadColumnsGone(tag)
  H.assertEq(cell(13, 15), BLANK, tag .. ": no Learn.Rate caption at {13,15}")
  H.assertEq(cell(24, 15), BLANK, tag .. ": no Skill caption at {24,15}")
  H.assertEq(cell(12, 17), BLANK, tag .. ": no rate colon after spell 1's name")
  H.assertEq(cell(16, 17), BLANK, tag .. ": no {times}NN rate after spell 1")
  H.assertEq(cell(26, 17), BLANK, tag .. ": no Skill%% digits at {26,17}")
  H.assertEq(cell(27, 17), BLANK, tag .. ": no percent sign at {27,17}")
end

H.run({ maxFrames = 80000 }, {
  -- gen_vector_doorstep.lua's cold Continue off the battery anchor.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
      and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world doorstep", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),

  -- Pin the esper inventory to exactly IFRIT + TERRATO (bits 1 and 4).
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning IFRIT+TERRATO",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x12)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x00)
    H.writeByte(ESPERS + 3, 0x00)
  end),

  -- X opens the menu (world map and field share the menu program).
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),

  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),

  H.call(function()
    H.assertEq(H.readByte(SKILLCOLOR), 0x20, "Espers row enabled (color $20)")
  end),
  -- The submenu keeps the caller's cursor row; walk it up onto Espers.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
  end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
    "skills submenu cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "esper list", 5),
  H.call(function()
    H.assertEq(H.readByte(ZLISTTYPE), 4, "list type GENJU (menu_ram.inc)")
  end),

  -- ---- IFRIT: the stone WITH a while-worn mod (+5 vigor) ----------------
  listSeek(IFRIT, "cursor to IFRIT's row"),
  H.waitFrames(20),                     -- let any list scroll finish (A is
                                        -- ignored while ScrollListPage runs)
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Ifrit detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), IFRIT, "detail page is IFRIT's")
    assertDeadColumnsGone("ifrit")
    H.assertEq(cell(5, 17) ~= BLANK, true, "ifrit: spell 1 name drawn at {5,17}")
    H.assertEq(cell(5, 27), CH_W, "ifrit: While worn... starts at {5,27}")
    H.assertEq(cell(25, 27), CH_PLUS, "ifrit: '+' at {25,27}")
    H.assertEq(cell(27, 27), CH_5, "ifrit: magnitude 5 at {27,27}")
    H.screenshot("esper_detail_ifrit_anchor")
    H.log("IFRIT: dead columns gone, 'While worn...Vigor + 5' drawn")
  end),

  H.pressButtons({ "b" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
  H.waitFrames(10),

  -- ---- TERRATO: a stone with NO mod (Ot6EsperStatTbl $00) ---------------
  listSeek(TERRATO, "cursor to TERRATO's row"),
  H.waitFrames(20),                     -- let any list scroll finish (A is
                                        -- ignored while ScrollListPage runs)
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Terrato detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), TERRATO, "detail page is TERRATO's")
    assertDeadColumnsGone("terrato")
    H.assertEq(cell(5, 17) ~= BLANK, true, "terrato: spell 1 name drawn at {5,17}")
    for x = 5, 27 do
      H.assertEq(cell(x, 27), BLANK,
        string.format("terrato: while-worn line blank at {%d,27}", x))
    end
    H.screenshot("esper_detail_terrato_anchor")
    H.log("TERRATO: page clean in the no-mod state, stat line fully blank")
  end),

  H.call(function()
    H.log("PASSED: esper detail shows the while-worn stat mod, hides the "
      .. "dead learn-rate columns, and is correct with and without a mod")
  end),
})

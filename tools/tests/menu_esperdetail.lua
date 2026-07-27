-- @suite frontier=arvis_wake
-- menu_esperdetail.lua -- issue #27: the esper detail page shows the
-- while-worn stat mod and never the dead learn-rate columns.
--
-- M5 made espers while-equipped sub-jobs: every GenjuProp learn rate is 0 and
-- every level-up bonus byte is $ff (ff6/src/menu/genju_prop.asm), but the
-- vanilla esper detail page (skills.asm DrawEsperDetailMenu) still drew the
-- "Learn.Rate"/"Skill" captions, a ":  {times}00" rate after every spell, a
-- "  0%" skill column, and a blank bonus line -- so Ifrit's +5 vigor
-- (Ot6EsperStatTbl, ff6/src/battle/ot6_progression.asm) was invisible in
-- game.  The reworked page draws the spell names bare and replaces the bonus
-- line with "While worn...<stat> +<n>", blank for a stone with no mod.
--
-- This test drives the REAL menu UI (X -> Skills -> character -> Espers ->
-- list -> detail) from the arvis_wake fixture, the same boot
-- menu_bushidoloadout uses.  arvis_wake owns no espers yet, so the esper
-- inventory bits are pinned directly (the battle_bushido "install state"
-- house pattern): exactly IFRIT (esper 1, +5 vigor -- the issue's marquee)
-- and TERRATO (esper 4, Ot6EsperStatTbl $00 = no mod), giving one page of
-- each kind.  Rendering is asserted at cell level in the BG1 screen-B
-- tilemap shadow the menu draws into (wBG1Tiles::ScreenB = $7e4049,
-- ff6-en.dbg; 2 bytes per cell, char then color, 64 bytes per row) and
-- proven visually with screenshots of both pages.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE = 0x26                 -- menu direct-page vars (menu_ram.inc)
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99                 -- detail page's esper index
local SKILLCOLOR = 0x79                 -- zSkillsTextColor[0] = Espers row
local ESPERS     = 0x1a69               -- owned-esper bitfield, 27 bits
local GENJULIST  = 0x9d89               -- $7e9d89: list row -> esper index
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local IFRIT, TERRATO = 1, 4

-- BG1 screen B tilemap shadow: char byte of the cell at tile (x, y).
local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

-- Menu text codec bytes asserted below (ff6/tools/char_table/text_en.json).
local CH_W, CH_COLON, CH_PCT, CH_PLUS, CH_5 = 0x96, 0xc1, 0xcd, 0xca, 0xb9
local BLANK = 0xff

local function st() return H.readByte(ZMENUSTATE) end


-- Walk the esper list cursor down to the row holding esper `idx`.
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

-- The shared page shape: no learn-rate caption, no Skill caption, no rate
-- after the first spell name, no percent column.  `row` is the first spell
-- row (y=17); its name field is cols 5-11, vanilla's rate colon sat at col
-- 12 and the percent sign at col 27.
local function assertDeadColumnsGone(tag)
  H.assertEq(cell(13, 15), BLANK, tag .. ": no Learn.Rate caption at {13,15}")
  H.assertEq(cell(24, 15), BLANK, tag .. ": no Skill caption at {24,15}")
  H.assertEq(cell(12, 17), BLANK, tag .. ": no rate colon after spell 1's name")
  H.assertEq(cell(16, 17), BLANK, tag .. ": no {times}NN rate after spell 1")
  H.assertEq(cell(26, 17), BLANK, tag .. ": no Skill%% digits at {26,17}")
  H.assertEq(cell(27, 17), BLANK, tag .. ": no percent sign at {27,17}")
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- Pin the esper inventory to exactly IFRIT + TERRATO (bits 1 and 4).
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning IFRIT+TERRATO",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x12)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x00)
    H.writeByte(ESPERS + 3, 0x00)
  end),

  -- X opens the field menu; ride the fade to the main-menu steady state.
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),

  -- Items -> Skills, A; pick the lead character; land on the skills submenu.
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),

  -- POSITIVE CONTROL: the Espers row is enabled (the pin worked) and the
  -- submenu cursor sits on it.
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
  H.waitFrames(30),                     -- let the page draw + DMA settle
  H.call(function()
    H.assertEq(H.readByte(Z99), IFRIT, "detail page is IFRIT's")
    assertDeadColumnsGone("ifrit")
    -- Spell list: Fire's name cell is drawn (grant list still present).
    H.assertEq(cell(5, 17) ~= BLANK, true, "ifrit: spell 1 name drawn at {5,17}")
    -- The while-worn line: "While worn...Vigor   + 5" at {5,27}:
    -- prefix cols 5-17, stat name cols 18-24, '+' col 25, digits cols 26-27.
    H.assertEq(cell(5, 27), CH_W, "ifrit: While worn... starts at {5,27}")
    H.assertEq(cell(25, 27), CH_PLUS, "ifrit: '+' at {25,27}")
    H.assertEq(cell(27, 27), CH_5, "ifrit: magnitude 5 at {27,27}")
    H.screenshot("esper_detail_ifrit")
    H.log("IFRIT: dead columns gone, 'While worn...Vigor + 5' drawn")
  end),

  -- Back to the list; the saved cursor row is restored.
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
    -- No mod: the whole while-worn line is blank -- including the cells
    -- Ifrit's page just used, which proves the revisit overwrote them.
    for x = 5, 27 do
      H.assertEq(cell(x, 27), BLANK,
        string.format("terrato: while-worn line blank at {%d,27}", x))
    end
    H.screenshot("esper_detail_terrato")
    H.log("TERRATO: page clean in the no-mod state, stat line fully blank")
  end),

  H.call(function()
    H.log("PASSED: esper detail shows the while-worn stat mod, hides the "
      .. "dead learn-rate columns, and is correct with and without a mod")
  end),
})

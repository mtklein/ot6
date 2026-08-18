-- probe_skillspage.lua -- #68's mandated measurement: the field Skills page
-- as shipped (7 rows), with the BG2A window registers read live, before any
-- resize.  The recon: SkillsOptionsWindow1 {1,1},{7,4} and Window2
-- {1,7},{7,10} do not reconcile with BG3A text rows 3/5/9/11/13/15/17 under
-- any single row-grid model -- Dance at row 17 lands outside Window2 on
-- every reading.
local H = dofile("tools/tests/lib/ot6.lua")
local ZM, CUR = 0x26, 0x4B
local ST_MAIN, ST_CHAR, ST_SKILLS = 0x05, 0x06, 0x0a
local function st() return H.readByte(ZM) end
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/vargas_won.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST_MAIN and H.readByte(CUR) == 1 end,
    900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, "cursor Skills"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "char select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills page", 5),
  H.waitFrames(90),
  H.call(function()
    -- the live window shadows: WH0-3 ($2126-$2129 shadows) live in menu RAM;
    -- log the raw PPU window regs via zero-page shadows $86-$8D region AND
    -- screenshot for the geometry read.
    local w = {}
    for a = 0x80, 0x9F do w[#w+1] = string.format("%02X", H.readByte(a)) end
    H.log("[skills] zp $80-$9F: " .. table.concat(w, " "))
    H.screenshot("skillspage_7rows")
  end),
})

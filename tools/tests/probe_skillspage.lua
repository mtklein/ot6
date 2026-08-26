-- probe_skillspage.lua -- measures the field Skills page as shipped (7 rows),
-- reading the BG2A window registers live.
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
    -- logs raw PPU window regs via zero-page shadows $80-$9F
    local w = {}
    for a = 0x80, 0x9F do w[#w+1] = string.format("%02X", H.readByte(a)) end
    H.log("[skills] zp $80-$9F: " .. table.concat(w, " "))
    H.screenshot("skillspage_7rows")
  end),
})

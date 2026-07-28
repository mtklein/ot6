-- probe_factory_menus.lua -- VERIFICATION probe (issue #15 "honest
-- Factory-era kits").  NOT a suite test.  Cold-Continues post-opera-v1
-- (party LOCKE EDGAR SABIN CELES -- the v0.6 fixture four), takes a real
-- world encounter on the Albrook doorstep band, and walks each character's
-- battle surface in turn:
--   * LOCKE: command menu screenshot; a real Steal, MP read around it
--     (the flat 2 MP charge has no on-screen price -- this measures it);
--   * CELES: command menu screenshot; the Magic list (MP column) shot;
--   * SABIN: command menu + the Blitz submenu (price column);
--   * EDGAR: command menu + the Tools submenu (price column).
-- Staging is monster-side only (stop status + HP pinned high so nothing
-- dies mid-observation); no character row is ever poked.
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function MHP(m)  return 0x3BFC + m * 2 end
local function ST3(e)  return 0x3EF8 + e end

local CHARS = { [0]="TERRA","LOCKE","CYAN","SHADOW","EDGAR","SABIN",
                "CELES","STRAGO","RELM","SETZER","MOG","GAU","GOGO","UMARO" }

local slotOf = {}
local msPresent = {}

local function pinField()
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(ST3(e), H.readByte(ST3(e)) | 0x10)
    if H.readWord(MHP(m)) < 0x6000 then H.writeWord(MHP(m), 0xF000) end
  end
end

-- wait for a character's menu (charId resolved at runtime through slotOf),
-- consuming any other character's menu with a real Defend (right swaps
-- Fight->Def, then A)
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      pinField()
      ph = ph + 1
      if ph % 900 == 0 then
        H.log(string.format("[wait %s] ph=%d menu=%02X actor=%02X",
          what, ph, H.readByte(MENU), H.readByte(ACTOR)))
      end
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

local function mpLog(tag)
  return H.call(function()
    local t = {}
    for s = 0, 3 do
      t[#t + 1] = string.format("%s=%d/%d",
        CHARS[H.readByte(0x3ED8 + s * 2)] or "?",
        H.readWord(CURMP(s)), H.readWord(MAXMP(s)))
    end
    H.log("[mp @ " .. tag .. "] " .. table.concat(t, " "))
  end)
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl() and H.worldAligned()
  end, 3000, "cold Continue to the post-Opera world doorstep", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.call(function()
    H.assertEntryContract("post-opera-v1")
    H.log(string.format("[boot] world=(%d,%d)", H.worldX(), H.worldY()))
  end),

  (function()
    local ph = 0
    local pattern = { "left", "left", "up", "up", "right", "right", "down", "down" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        ph = ph + 1
        local dir = pattern[(math.floor(ph / 20) % #pattern) + 1]
        H.setPad({ [dir] = true })
      end),
    }, "a real world encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then
        slotOf[id] = s
        H.log(string.format("[slot %d] %s cmds=%02X %02X %02X %02X  MP=%d/%d",
          s, CHARS[id] or tostring(id),
          H.readByte(0x202E + s * 12), H.readByte(0x2031 + s * 12),
          H.readByte(0x2034 + s * 12), H.readByte(0x2037 + s * 12),
          H.readWord(CURMP(s)), H.readWord(MAXMP(s))))
      end
    end
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
        msPresent[#msPresent + 1] = m
        H.log(string.format("[monster %d] species=%04X hp=%d",
          m, H.readWord(0x3F46 + m * 2), H.readWord(MHP(m))))
      end
    end
    assert(slotOf[0x01] and slotOf[0x06] and slotOf[0x05] and slotOf[0x04],
      "LOCKE, CELES, SABIN, EDGAR all present")
    pinField()
  end),

  -- ---------------------------------------------------------- LOCKE --
  -- cmds Fight/Steal/-/Item: Steal is row 1.  A real Steal, MP measured
  -- around it: the 2 MP price has NO on-screen surface to screenshot.
  menuFor(0x01, "locke_menu"),
  H.waitFrames(30),
  mpLog("locke menu up"),
  H.call(function() H.screenshot("factory_locke_menu") end),
  tap("down", 20),
  tap("a", 30),                          -- Steal -> target select
  H.call(function() H.screenshot("factory_locke_steal_target") end),
  tap("a", 20),                          -- confirm default enemy target
  H.waitFrames(300),
  mpLog("after locke steal"),
  H.call(function() H.screenshot("factory_locke_steal_done") end),

  -- ---------------------------------------------------------- CELES --
  -- cmds Fight/Runic/Magic/Item: Magic is row 2 -- the priced-list
  -- comparison surface (MP column).
  menuFor(0x06, "celes_menu"),
  H.waitFrames(30),
  mpLog("celes menu up"),
  H.call(function() H.screenshot("factory_celes_menu") end),
  tap("down", 20), tap("down", 20),
  tap("a", 60),                          -- Magic list opens
  H.call(function()
    H.log(string.format("[celes] mstate=%02X after Magic A", H.readByte(MSTATE)))
    H.screenshot("factory_celes_magic_list")
  end),
  tap("b", 30),                          -- close the list
  tap("up", 16), tap("up", 16),          -- cursor back to Fight
  tap("a", 30), tap("a", 20),            -- a real Fight to consume the turn
  H.waitFrames(240),

  -- ---------------------------------------------------------- SABIN --
  menuFor(0x05, "sabin_menu"),
  H.waitFrames(30),
  mpLog("sabin menu up"),
  H.call(function() H.screenshot("factory_sabin_menu") end),
  tap("down", 20),
  tap("a", 60),                          -- Blitz submenu (tools shell)
  H.call(function()
    H.log(string.format("[sabin] mstate=%02X after Blitz A", H.readByte(MSTATE)))
    H.screenshot("factory_sabin_blitz_list")
  end),
  tap("b", 30),
  tap("up", 16),
  tap("a", 30), tap("a", 20),
  H.waitFrames(240),

  -- ---------------------------------------------------------- EDGAR --
  menuFor(0x04, "edgar_menu"),
  H.waitFrames(30),
  mpLog("edgar menu up"),
  H.call(function() H.screenshot("factory_edgar_menu") end),
  tap("down", 20),
  tap("a", 60),                          -- Tools submenu
  H.call(function()
    H.log(string.format("[edgar] mstate=%02X after Tools A", H.readByte(MSTATE)))
    H.screenshot("factory_edgar_tools_list")
  end),
  tap("b", 30),
  tap("up", 16),
  tap("a", 30), tap("a", 20),
  H.waitFrames(240),
  mpLog("all four observed"),

  H.logStep(function() return "probe_factory_menus complete" end),
})

-- probe_mp_universal.lua -- VERIFICATION probe (issue #32).  NOT a suite
-- test.  Cold-Continues terra-returned-v1 (party LOCKE EDGAR SABIN SETZER
-- -- NOBODY in this party knows a spell), disembarks the grounded
-- Blackjack at world (24,121), takes a real world encounter on the plain
-- south of Zozo, and measures, with NO character-side pokes:
--   * every slot's battle MP against the save's own field MP (read from
--     the live $1600 character-data block via battle's $3010 pointers);
--   * SABIN confirms Pummel (2 MP, Ot6AbilityCostTbl):
--       pre-fix  -- battle MP 0/0, the universal insufficient-MP fizzle
--                   (CalcAttackEffect, battle_main.asm:8311-8329): no
--                   damage, no charge, turn consumed;
--       post-fix -- Pummel lands on natural MP: monster HP drops and
--                   exactly 2 MP is charged ($3620 cost-queue watch,
--                   battle_stealmp.lua's instrument);
--   * WRITEBACK: the battle is then cleared and the field character data
--     re-read -- post-battle field MP must equal pre-battle minus exactly
--     what was spent, for every party member (UpdateSRAM,
--     battle_main.asm:12265-12267 -- pre-fix the max-0 skip hides the
--     zeroed pool; post-fix the real pool must round-trip the spend).
-- Monster-side staging only (stop status + HP pinned high so nothing dies
-- mid-observation); no character row is ever poked.
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

local slotOf, msPresent = {}, {}
local costs = {}                  -- $3620 cost-queue stores (blitz only)
local fieldPre = {}               -- [slot] = field cur MP before the battle
local charOfs = {}                -- [slot] = $1600-block byte offset ($3010,x)
local sabinPre, hpsumPre = nil, nil

-- on foot vs vehicle: $11FA&3==0 AND $11F3==0 (world/init.asm:93-102 via
-- docs/research/world-map-nav.md:33-35; $1f64/$1f65 are SAVE-BLOCK cells
-- and keep their aboard bit until the next save -- measured, probe_mpu_boot)
local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

local function monsterHpSum()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(MHP(m)) end
  return t
end

local function pinField()
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(ST3(e), H.readByte(ST3(e)) | 0x10)
    if H.readWord(MHP(m)) < 0x6000 then H.writeWord(MHP(m), 0xF000) end
  end
end

local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      pinField()
      ph = ph + 1
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

H.run({ maxFrames = 150000 }, {
  -- cold Continue (the anchor's $307ff0=3 preselects slot 3)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world (aboard the grounded Blackjack)", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("terra-returned-v1")
    H.log(string.format("[boot] $1f64=%04X onFoot=%s save-block=(%d,%d)",
      H.readWord(0x1f64), tostring(onFoot()),
      H.readByte(0x1f60), H.readByte(0x1f61)))
  end),

  -- disembark guard: the cold Continue restores the PARTY ON FOOT at the
  -- parked ship's tile ($11FA&3=0, $11F3=0 from the first world frame --
  -- measured, probe_mpu_boot + this probe's own boot log), so this drive
  -- normally exits at 0 frames; the B taps only matter if a future anchor
  -- re-mint ever restores aboard/airborne instead.
  (function()
    local ph = 0
    return H.driveUntil(function()
      ph = ph + 1
      if ph % 300 == 0 then
        H.log(string.format("[disembark ph=%d] $11FA=%02X $11F3=%02X ctrl=%s",
          ph, H.readByte(0x11FA), H.readByte(0x11F3),
          tostring(H.worldHasControl())))
      end
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = (ph2 or 0) + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[on foot] world=(%d,%d) $1f64=%04X",
      H.worldX(), H.worldY(), H.readWord(0x1f64)))
  end),

  -- walk the plain until a real encounter fires (drift south, away from
  -- the parked ship so the oscillation cannot re-board it)
  (function()
    local ph = 0
    local pattern = { "down", "down", "right", "right", "down", "down",
                      "left", "left" }
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

  -- the measurement: battle MP vs the save's field MP, per slot
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then
        slotOf[id] = s
        charOfs[s] = H.readWord(0x3010 + s * 2)
        fieldPre[s] = H.readWord(0x160d + charOfs[s])
        H.log(string.format(
          "[slot %d] %s battle MP=%d/%d  field MP=%d/%d(base)", s,
          CHARS[id] or tostring(id),
          H.readWord(CURMP(s)), H.readWord(MAXMP(s)),
          fieldPre[s], H.readWord(0x160f + charOfs[s])))
      end
    end
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    assert(slotOf[0x05], "SABIN present")
    pinField()
    emu.addMemoryCallback(function(_, v)
      if H.readByte(0x3A7A) == 0x0A then costs[#costs + 1] = v end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
    H.screenshot("mpu_battle_entry")
  end),

  -- SABIN: Pummel on natural MP
  menuFor(0x05, "sabin_menu"),
  H.waitFrames(30),
  H.call(function()
    costs = {}
    sabinPre = H.readWord(CURMP(slotOf[0x05]))
    hpsumPre = monsterHpSum()
    H.log(string.format("[sabin pre] MP=%d hpsum=%d", sabinPre, hpsumPre))
  end),
  tap("down", 20),
  tap("a", 40),                          -- Blitz submenu
  H.call(function() H.screenshot("mpu_blitz_open") end),
  tap("a", 30),                          -- confirm Pummel (row 0)
  H.call(function()
    H.log(string.format("[sabin confirm] mstate=%02X menu=%02X",
      H.readByte(MSTATE), H.readByte(MENU)))
  end),
  tap("a", 30),                          -- target select, if it appeared
  H.waitFrames(400),
  H.call(function()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = string.format("%d", v) end
    local after, hpsum = H.readWord(CURMP(slotOf[0x05])), monsterHpSum()
    H.log(string.format(
      "[sabin pummel] MP %d -> %d, hpsum %d -> %d (dmg %d), costq={%s}",
      sabinPre, after, hpsumPre, hpsum, hpsumPre - hpsum, table.concat(c, ",")))
    H.screenshot("mpu_pummel_resolved")
  end),

  -- writeback: clear the battle, then re-read the field character data
  H.clearBattle(12000),
  H.waitFrames(120),
  H.call(function()
    for s = 0, 3 do
      if charOfs[s] then
        local now = H.readWord(0x160d + charOfs[s])
        H.log(string.format("[writeback slot %d] field MP %d -> %d (delta %d)",
          s, fieldPre[s], now, fieldPre[s] - now))
      end
    end
  end),

  H.logStep(function() return "probe_mp_universal complete" end),
})

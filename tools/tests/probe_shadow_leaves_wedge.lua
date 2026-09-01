-- @manual
-- probe_shadow_leaves_wedge.lua -- replay the fighting lineage's forest leg
-- (gen_sabin_forest.lua: world -> map 132 -> the (28,7) exit) step for step
-- on the same fixture the 16:52 forest_done wedge booted (camp_escaped,
-- sha 59dff2382bde), with READ-ONLY observers riding alongside:
--   * exec watches on the field's RandBattle machinery (Ot6MarkRandom,
--     InitObjScript, ObjCmd_d7/ff, EventCmd_4e, ExecBattle, LoadMap,
--     EventCmd_b7/47): the field half of the "$ca0029 wedge";
--   * exec watches on the battle's end path (CheckBattleEnd, WinBattle,
--     ShadowLeaves, Ot6ShadowLeaves, _48c4/_488f, TerminateBattle) and on
--     $C2:FE00-$C2:FFFF, where a bank-relative `jmp Ot6ShadowLeaves`
--     (assembled 4C 00 FE at $C2:4911) lands instead of $CF:FE00;
--   * per-frame RAM dumps around the roll and around the kill, and CPU PC
--     samples once ShadowLeaves has fired.
-- The pad is driven by the same navigators with the same options as the
-- generator, so the emulation is the wedge run's; the observers only read.
-- No state writes.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/camp_escaped.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function b(a) return H.readByte(a) end
local function w(a) return H.readWord(a) end
local function evtPC() return b(0xE7) * 65536 + b(0xE6) * 256 + b(0xE5) end

-- ------------------------------------------------------------- dumps --
-- party slot i (0..3): the object at $0803+2i and its movement fields
local function objDump(i)
  local p = w(0x0803 + i * 2)
  if p == 0x07d9 then return string.format("s%d:hidden", i + 1) end
  return string.format(
    "s%d@%04X x=%02X%02X.%02X y=%02X%02X.%02X spd=%04X,%04X sp=%d " ..
    "mt=%02X/%02X dir=%d fc=%d wt=%d scr=%02X%02X%02X steps=%d jmp=%02X z=%02X en=%02X",
    i + 1, p, b(0x086b + p), b(0x086a + p), b(0x0869 + p),
    b(0x086e + p), b(0x086d + p), b(0x086c + p),
    w(0x0871 + p), w(0x0873 + p), b(0x0875 + p), b(0x087c + p), b(0x087d + p),
    b(0x087e + p), b(0x087f + p), b(0x0882 + p),
    b(0x0885 + p), b(0x0884 + p), b(0x0883 + p),
    b(0x0886 + p), b(0x0887 + p), b(0x0888 + p), b(0x0867 + p))
end

local function fieldDump(tag)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) evPC=%06X $e1=%02X $e2=%02X $e3=%04X $e8=%04X " ..
    "$56=%02X $57=%02X $58=%02X $84=%02X $47=%02X $0798=%02X bgupd=%02X,%02X,%02X " ..
    "$4a=%02X $4c=%02X $1eb9=%02X $11fa=%02X danger=%04X | %s | %s | %s | %s",
    tag, H.frame, mapIdx(), H.fieldX(), H.fieldY(), evtPC(), b(0xe1), b(0xe2),
    w(0xe3), w(0xe8), b(0x56), b(0x57), b(0x58), b(0x84), b(0x47), b(0x0798),
    b(0x055a), b(0x055b), b(0x055c), b(0x4a), b(0x4c), b(0x1eb9), b(0x11fa),
    w(0x1f6e), objDump(0), objDump(1), objDump(2), objDump(3)))
end

-- battle entity e (0..3 characters, 4..9 monsters), x = e*2
local function entDump(e)
  local x = e * 2
  return string.format(
    "e%d:pr=%02X hp=%d st=%02X,%02X,%02X,%02X sp=%02X sh=%d/%d br=%d atb=%04X",
    e, b(0x3aa0 + x), w(0x3bf4 + x), b(0x3ee4 + x), b(0x3ee5 + x),
    b(0x3ef8 + x), b(0x3ef9 + x), b(0x3e4c + x), b(0x3e38 + x), b(0x3e39 + x),
    b(0x3e88 + x), w(0x3218 + x))
end

local function battleDump(tag)
  local ents = {}
  for e = 0, 9 do
    if e < 4 or (b(0x3aa0 + e * 2) & 1) == 1 then ents[#ents + 1] = entDump(e) end
  end
  H.log(string.format(
    "[%s] f%d evPC=%06X alive=%04X nchar=%d nmon=%d $3a95=%02X died=%04X " ..
    "$3a3a=%02X $3a39=%02X $3ee0=%02X $3a6e=%02X $3ebc=%02X $3ebd=%02X " ..
    "$3003=%02X $201f=%02X $1ede=%02X $2f49=%02X $be=%02X menu=%02X st=%02X " ..
    "actor=%02X ot6=%02X,%02X,%02X,%02X | %s",
    tag, H.frame, evtPC(), w(0x3a74), b(0x3a76), b(0x3a77), b(0x3a95), w(0x3a56),
    b(0x3a3a), b(0x3a39), b(0x3ee0), b(0x3a6e), b(0x3ebc), b(0x3ebd),
    b(0x3003), b(0x201f), b(0x1ede), b(0x2f49), b(0xbe), b(0x7bca), b(0x7bc2),
    b(0x62ca), b(0x57bc), b(0x57bd), b(0x57be), b(0x57bf),
    table.concat(ents, " ")))
end

local cpuKeysLogged = false
local function cpuSample(tag)
  local ok, st = pcall(emu.getState)
  if not ok or type(st) ~= "table" then H.log("[cpu] getState failed"); return end
  if not cpuKeysLogged then
    cpuKeysLogged = true
    local ks = {}
    for k, _ in pairs(st) do
      local s = tostring(k)
      if s:match("^cpu") then ks[#ks + 1] = s end
    end
    table.sort(ks)
    H.log("[cpu] keys: " .. table.concat(ks, ","))
  end
  local parts = {}
  for k, v in pairs(st) do
    local s = tostring(k)
    if s:match("^cpu%.") then parts[#parts + 1] = s .. "=" .. tostring(v) end
  end
  table.sort(parts)
  H.log(string.format("[cpu %s] f%d %s", tag, H.frame, table.concat(parts, " ")))
end

-- ------------------------------------------------------------- hooks --
local hooks = {}
local slFrame = nil            -- frame ShadowLeaves ($C2:4911) executed
local function hook(name, fallback, logN, fn)
  local ok, addr = pcall(H.sym, name)
  if not ok then addr = fallback end
  if not addr then H.log("[hook] " .. name .. " unresolved"); return nil end
  local h = { name = name, addr = addr, n = 0, first = nil, last = nil }
  hooks[#hooks + 1] = h
  emu.addMemoryCallback(function(_a, _v)
    h.n = h.n + 1
    h.first = h.first or H.frame
    h.last = H.frame
    if h.n <= (logN or 0) then
      H.log(string.format("[x %s] #%d f%d @%06X%s", name, h.n, H.frame, addr,
        fn and (" " .. fn()) or ""))
    end
  end, emu.callbackType.exec, addr, addr)
  return h
end

-- field: the RandBattle machinery
hook("Ot6MarkRandom", 0xF00560, 8, function()
  return string.format("map=%d (%d,%d) danger=%04X $57=%02X", mapIdx(),
    H.fieldX(), H.fieldY(), w(0x1f6e), b(0x57))
end)
hook("InitObjScript", 0xC09BA5, 24, function()
  return string.format("obj=$%02X len/flags=$%02X evPC=%06X", b(0xea), b(0xeb), evtPC())
end)
hook("ObjCmd_d7", 0xC07A65, 24, function()
  return string.format("scroll_obj on obj ptr $%04X (#%d)", w(0xda), w(0xda) // 0x29)
end)
hook("ObjCmd_ff", 0xC07B70, 24, function()
  return string.format("end on obj ptr $%04X (#%d)", w(0xda), w(0xda) // 0x29)
end)
hook("EventCmd_4e", 0xC0A4F9, 8, function() return string.format("evPC=%06X", evtPC()) end)
hook("ExecBattle", 0xC0C13E, 8, function() return string.format("evPC=%06X", evtPC()) end)
hook("LoadMap", 0xC0BEBC, 8, function()
  return string.format("evPC=%06X $58=%02X $11fa=%02X", evtPC(), b(0x58), b(0x11fa))
end)
hook("EventCmd_b7", 0xC0B299, 8, function() return string.format("evPC=%06X", evtPC()) end)
hook("EventCmd_47", 0xC09D03, 8, function() return string.format("evPC=%06X", evtPC()) end)

-- battle: the end path
hook("Battle_ext", 0xC20000, 8)
hook("CheckBattleEnd", 0xC24858, 3)
hook("WinBattle", 0xC25DFF, 8, function() return string.format("$1ede=%02X", b(0x1ede)) end)
hook("LoseBattle", 0xC26076, 4)
hook("ShadowLeaves", 0xC24911, 8, function()
  slFrame = slFrame or H.frame
  local x = b(0x3003)
  return string.format(
    "the 1/16 leave roll HIT: $3003=%02X shadow st1=%02X $201f=%02X nchar=%d " ..
    "$3ebd=%02X $1ede=%02X $be=%02X map=%d",
    x, b(0x3ee4 + (x & 0x7f)), b(0x201f), b(0x3a76), b(0x3ebd), b(0x1ede), b(0xbe), mapIdx())
end)
hook("Ot6ShadowLeaves", 0xCFFE00, 8, function() return string.format("$1ede=%02X", b(0x1ede)) end)
hook("_48c4", 0xC24914, 8)
hook("_488f", 0xC248FA, 8)
hook("TerminateBattle", 0xC200C5, 8)
hook("Cmd_23", 0xC24FB9, 8)
hook("UpdateSRAM", 0xC24986, 8)
hook("CheckRetal", 0xC24CAB, 0)
hook("Ot6MayAct", 0xF00926, 0)
hook("AICmd_f5", nil, 8)

-- where a bank-relative `jmp $FE00` from $C2 lands: $C2:FE00-$C2:FEFF.
-- decompress_code owns $C2:FC6D-$C2:FFFF and runs on every battle load, so
-- hits before ShadowLeaves are only counted (with their address span); the
-- first hits AFTER ShadowLeaves are the wander path itself.
local landN, landFirst, preLo, preHi, preN = 0, {}, 0xFFFFFF, 0, 0
emu.addMemoryCallback(function(a, _v)
  if not slFrame then
    preN = preN + 1
    if a then
      if a < preLo then preLo = a end
      if a > preHi then preHi = a end
    end
    return
  end
  landN = landN + 1
  if #landFirst < 48 then
    landFirst[#landFirst + 1] = string.format("%06X", a or -1)
  end
end, emu.callbackType.exec, 0xC2FE00, 0xC2FEFF)
local stpN = 0
emu.addMemoryCallback(function(_a, _v)
  stpN = stpN + 1
  if stpN <= 3 then
    H.log(string.format("[x STP $C2:FEF9] #%d f%d (byte $DB = STP; the 65816 halts here)",
      stpN, H.frame))
  end
end, emu.callbackType.exec, 0xC2FEF9, 0xC2FEF9)

-- ------------------------------------------------- per-frame observer --
local rollFrame, battleStart, killFrame = nil, nil, nil
local lastBattle, battleN = false, 0
local hookMark = hook("Ot6MarkRandom", 0xF00560, 0)   -- second watch: frame stamp only
emu.addEventCallback(function()
  local f = H.frame
  if hookMark and hookMark.n > 0 and hookMark.last == f and rollFrame ~= hookMark.last then
    rollFrame = f
  end
  if rollFrame and f - rollFrame < 40 then fieldDump("roll+" .. (f - rollFrame)) end
  local inB = H.battleLoadStarted()
  if inB and not lastBattle then
    battleN = battleN + 1
    battleStart, killFrame = f, nil
    battleDump("battle" .. battleN .. " start")
  end
  if lastBattle and not inB then
    battleDump("battle" .. battleN .. " table released")
    fieldDump("field back")
  end
  lastBattle = inB
  if inB then
    local d = f - battleStart
    if d % 300 == 0 then battleDump("b" .. battleN .. "+" .. d) end
    if not killFrame then
      local anyMon, allZero = false, true
      for e = 4, 9 do
        if (b(0x3aa0 + e * 2) & 1) == 1 then
          anyMon = true
          if w(0x3bf4 + e * 2) ~= 0 then allZero = false end
        end
      end
      if anyMon and allZero then killFrame = f; battleDump("kill") end
    elseif f - killFrame <= 240 and (f - killFrame) % 8 == 0 then
      battleDump("kill+" .. (f - killFrame))
    end
    if slFrame then
      local s = f - slFrame
      if s <= 4 or (s % 60 == 0 and s <= 420) then
        cpuSample("sl+" .. s)
        if s % 60 == 0 then battleDump("sl+" .. s) end
      end
    end
  end
end, emu.eventType.startFrame)

-- the replay may end once the wedge is established (or on genuine success)
local function stopNow()
  if slFrame and H.frame > slFrame + 450 then return true end
  if killFrame and H.frame > killFrame + 3000 and H.battleLoadStarted() then return true end
  return false
end

-- ------------------------------------------- the generator's own steps --
-- (gen_sabin_forest.lua, verbatim through crossTo(28, 7, 133)'s navTo, with
-- only the navTo's `arrive` widened by stopNow so the wedge ends the ride)
local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, {
    maxFrames = budget or 25000,
    playBattles = "tactical",
    arrive = function() return not H.worldMode() end,
  })
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "start on the World of Balance")
    H.assertEq(sw(0x0037), 1, "$0037 set -- escape done")
    H.log(string.format("[forest] start world (%d,%d) $1dd2&08=%d (story's own)",
      H.worldX(), H.worldY(), H.readByte(0x1dd2) & 0x08))
  end),

  worldToMap(178, 82, "forest entrance (178,82)", 25000),
  H.waitUntil(function()
    return mapIdx() == 132 and H.hasControl() and H.tileAligned()
  end, 4000, "map 132 control", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "map 132 fade", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 132, "entered Phantom Forest map 132")
    H.log(string.format("[forest] on map 132 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  H.cond(function() return true end, {
    H.logStep(function()
      return string.format("[forest] crossTo %s: navTo (%d,%d) -> map %d "..
        "from map %d (%d,%d) f%d", "132->133", 28, 7, 133, mapIdx(),
        H.fieldX(), H.fieldY(), H.frame)
    end),
    H.navTo(28, 7, { maxFrames = 16000, playBattles = "tactical",
      arrive = function() return mapIdx() == 133 or stopNow() end }),
  }, {}),

  H.call(function()
    H.log(string.format("[probe] navTo ended f%d map=%d (%d,%d) evPC=%06X batt=%s ctl=%s",
      H.frame, mapIdx(), H.fieldX(), H.fieldY(), evtPC(),
      tostring(H.battleLoadStarted()), tostring(H.hasControl())))
    for _, h in ipairs(hooks) do
      H.log(string.format("[hooks] %-18s @%06X n=%d first=%s last=%s", h.name, h.addr,
        h.n, tostring(h.first), tostring(h.last)))
    end
    H.log(string.format("[land] $C2:FE00-FEFF exec before ShadowLeaves: %d hits " ..
      "spanning %06X-%06X (decompress_code); after ShadowLeaves: %d hits, path=%s; " ..
      "STP at $C2:FEF9 executed %d time(s)", preN, preLo, preHi, landN,
      table.concat(landFirst, " "), stpN))
    local byName = {}
    for _, h in ipairs(hooks) do byName[h.name] = byName[h.name] or h end
    local function n(name) return byName[name] and byName[name].n or -1 end
    if slFrame then
      battleDump("autopsy")
      cpuSample("autopsy")
      H.log(string.format("[verdict] ShadowLeaves ($C2:4911) ran at f%d; " ..
        "Ot6ShadowLeaves ($CF:FE00) ran %d times; $C2:FE00.. landed %d times; " ..
        "_48c4 %d, _488f %d, WinBattle %d, TerminateBattle %d (whole replay)",
        slFrame, n("Ot6ShadowLeaves"), landN, n("_48c4"), n("_488f"),
        n("WinBattle"), n("TerminateBattle")))
    else
      H.log(string.format("[verdict] ShadowLeaves never ran on this replay " ..
        "(WinBattle %d, TerminateBattle %d)", n("WinBattle"), n("TerminateBattle")))
    end
  end),
})

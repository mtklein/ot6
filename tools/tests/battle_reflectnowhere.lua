-- @suite savestate=first_battle
-- battle_reflectnowhere.lua -- a reflected spell with no body to land on
-- does not hang the battle (#520).
--
-- #519's hang (gen_wor_tower, formation $0AD): Relm's Drain left the last
-- L.30 Magic hit, so it queued its counter; a poison tick killed it before
-- the counter ran (counters run ahead of CheckBattleEnd), and the counter
-- cast Imp at Celes, who wore a Wall Ring.  CalcReflectDmg queued the
-- bounce's animation (battle script command $09) and looked for a body on
-- the monster side: none stood, so its target record stayed all $ff, and
-- GfxCmd_09 never returned -- ExecBtlGfx command 4 forever, no victory.
-- The retail ROM does the same (build/attempts/wt/v041-battle-hang/vanilla/).
-- Ot6ReflectNowhere (ot6_reflect.asm) turns a bounce that found nobody into
-- command $07, which steps the script's data pointer and shows nothing.
--
-- That sequence cannot be dealt on cue (the counter, the tick and the last
-- monster's HP all have to line up), so this is a mechanism test with
-- declared writes (tools/state_write_waivers.txt): in Narshe's first battle,
-- at the first monster action's dispatch, the command becomes Magic Imp, the
-- party gets Reflect, and in arm "nowhere" every monster, the caster too, is
-- set to 0 HP and Wound -- the state the counter met.  Arm "lands" keeps the
-- monsters standing, so the bounce lands and its $09 must still play.
--
--   nowhere: the bounce ran (CalcReflectDmg), its record is all $ff, the
--            script carries $07 and no $09/$15, the script returns, and the
--            victory starts (WinBattle).  On a ROM without the fix the
--            script never returns: the run fails on the wait below, or the
--            watchdog names it first (class wonhang, "battle-won-never-ended").
--   lands:   the record names a body, the script carries $09, and returns.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/first_battle.mss.lua"
local IMP, MAGIC = 0x23, 0x02
local ST3_REFLECT, ST1_WOUND = 0x80, 0x80

local arm = nil            -- "nowhere" / "lands" while an arm runs
local seen = {}            -- per arm: what the hooks saw
local function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", H.readByte(a + i)) end
  return table.concat(t, " ")
end

local hooked = false
local function hook()
  if hooked then return end
  hooked = true
  local d = H.sym("_dispatcher")
  emu.addMemoryCallback(function()
    local s = arm and seen[arm]
    if not s or s.forced then return end
    local x = emu.getState()["cpu.x"] & 0xff
    if x < 8 then return end
    s.forced, s.caster = H.frame, x
    H.writeByte(0x00B5, MAGIC)
    H.writeByte(0x00B6, IMP)
    for e = 0, 6, 2 do H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | ST3_REFLECT) end
    if arm == "nowhere" then
      for e = 8, 0x12, 2 do
        H.writeWord(0x3BF4 + e, 0)
        H.writeByte(0x3EE4 + e, H.readByte(0x3EE4 + e) | ST1_WOUND)
      end
    end
    H.log(string.format("[reflect] %s: f%d monster entity %02X casts Imp at the party in Reflect%s", arm,
      H.frame, x, arm == "nowhere" and ", every monster down" or ""))
  end, emu.callbackType.exec, d, d)
  local r = H.sym("CalcReflectDmg")
  emu.addMemoryCallback(function()
    local s = arm and seen[arm]
    if s and s.forced and not s.reflect then s.reflect = H.frame end
  end, emu.callbackType.exec, r, r)
  local g = H.sym("ExecBtlGfx")
  emu.addMemoryCallback(function()
    local s = arm and seen[arm]
    if not s or not s.forced or s.script then return end
    if (emu.getState()["cpu.a"] & 0xff) ~= 4 then return end
    local ids, i = {}, 0
    while i < 16 do
      local c = H.readByte(0x2D6E + 4 * i)
      if c == 0xFF then break end
      ids[#ids + 1] = c
      i = i + 1
    end
    s.script, s.ids = H.frame, ids
    s.text = hex(0x2D6E, 4 * #ids + 1)
    -- the 16-byte data blocks at $2C6E belong, in order, to the commands
    -- that step the data pointer (NextGfxCmdData: $06, $07, $09, $15);
    -- the bounce's is the one whose command is $07/$09/$15
    local block = 0
    for _, c in ipairs(ids) do
      if c == 0x07 or c == 0x09 or c == 0x15 then s.bounce, s.record = c, hex(0x2C6E + 16 * block, 10) end
      if c == 0x06 or c == 0x07 or c == 0x09 or c == 0x15 then block = block + 1 end
    end
    H.log(string.format("[reflect] %s: f%d ExecBtlGfx 4 script %s | bounce command %s record %s", arm, H.frame,
      s.text, s.bounce and string.format("$%02X", s.bounce) or "none", tostring(s.record)))
  end, emu.callbackType.exec, g, g)
  local u = H.sym("UpdateDead")
  emu.addMemoryCallback(function()
    local s = arm and seen[arm]
    if s and s.script and not s.back then
      s.back = H.frame
      H.log(string.format("[reflect] %s: f%d the script returned", arm, H.frame))
    end
  end, emu.callbackType.exec, u, u)
  local w = H.sym("WinBattle")
  emu.addMemoryCallback(function()
    local s = arm and seen[arm]
    if s and s.back and not s.won then
      s.won = H.frame
      H.log(string.format("[reflect] %s: f%d the victory starts", arm, H.frame))
    end
  end, emu.callbackType.exec, w, w)
end

local function runArm(name, check)
  return {
    H.loadState(STATE),
    H.waitFrames(2),
    H.call(function()
      hook()
      seen[name] = {}
      arm = name
    end),
    H.waitUntil(function() return seen[name].forced ~= nil end, 3000, name .. ": a monster's action"),
    H.waitUntil(function() return seen[name].script ~= nil end, 600, name .. ": the action's battle script"),
    H.waitUntil(function() return seen[name].back ~= nil end, 2400,
      name .. ": the forced Imp's battle script to return (it hung inside ExecBtlGfx command 4 #520)"),
    H.call(function() check(seen[name]) end),
  }
end

local steps = { H.waitFrames(20) }
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add(runArm("nowhere", function(s)
  -- the precondition: the bounce ran and found nobody
  H.assertEq(s.reflect ~= nil, true, "nowhere: the Imp was reflected (CalcReflectDmg ran)")
  H.assertEq(s.record, "FF FF FF FF FF FF FF FF FF FF", "nowhere: the bounce's target record is empty")
  local has = {}
  for _, c in ipairs(s.ids) do has[c] = true end
  H.assertEq(has[0x09] or has[0x15] or false, false, "nowhere: no bounce animation ($09/$15) is queued")
  H.assertEq(s.bounce, 0x07, "nowhere: the bounce's slot steps the data pointer ($07)")
end))
add({
  H.waitUntil(function() return seen.nowhere.won ~= nil end, 600, "nowhere: the victory to start"),
  H.call(function()
    H.log(string.format("[reflect] nowhere: script f%d, returned f%d (%d frames), victory f%d",
      seen.nowhere.script, seen.nowhere.back, seen.nowhere.back - seen.nowhere.script, seen.nowhere.won))
  end),
})
add(runArm("lands", function(s)
  H.assertEq(s.reflect ~= nil, true, "lands: the Imp was reflected (CalcReflectDmg ran)")
  H.assertEq(s.bounce, 0x09, "lands: the bounce animation ($09) still plays")
  H.assertEq(s.record ~= nil and s.record ~= "FF FF FF FF FF FF FF FF FF FF", true,
    "lands: the bounce's target record names a body")
  H.log(string.format("[reflect] lands: script f%d, returned f%d (%d frames)", s.script, s.back, s.back - s.script))
end))

H.run({ maxFrames = 16000, retries = 1, watchdog = true }, steps)

-- @manual standalone: lua tools/tests/parts_selftest.lua  (after ninja build/ot6.sfc)
-- parts_selftest.lua -- the multi-part reader and planner (#189,
-- M.formationRecord / M.partRoles / M.partsPlan) against the two route
-- formations' own bytes, read out of the built ROM and battle_monsters.dat.
--
-- No emulator.  The formation records come from
-- ff6/src/battle/battle_monsters.dat (15 bytes a formation) and the AI
-- scripts from build/ot6.sfc at the symbols ff6/rom/ff6-en.dbg gives
-- AIScriptPtrs and AIScript, the bytes the driver's readParts walks.
--   Number 128, formation $1BA: body slot 0 ($10B), Left Blade slot 1
--   ($140) and RightBlade slot 3 ($13F) restore themselves on their own
--   death -> kill order {0}.
--   The Air Force, formation $1CB: body slot 0 ($113), Laser Gun slot 2
--   ($145) sets battle switch 0.0 on its death and the body's script
--   reads it, Speck slot 3 ($146, present bit clear) is restored by the
--   body, MissileBay slot 4 ($147) dies plain -> kill order {2, 0}.
-- Negative controls: a random-pool formation with no boss_death reads
-- nil; so does the Whelk ($1B0), whose shell and head each carry a
-- boss_death and restore the other -- two bodies name none; the Air
-- Force with its body's boss_death rewritten to a plain kill reads nil
-- (no body); the gun's set_battle_switch rewritten to a clear leaves it
-- filler, order {0}.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dat = slurp("ff6/src/battle/battle_monsters.dat")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local function symbol(name)
  local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
  return assert(tonumber(val, 16), name .. " in ff6-en.dbg") & 0x3FFFFF
end
local PTRS, SCRIPTS = symbol("AIScriptPtrs"), symbol("AIScript")

local function record(f)
  return H.formationRecord(function(i) return dat:byte(f * 15 + i + 1) end)
end
local function scriptOf(species, patch)
  local off = rom:byte(PTRS + species * 2 + 1) | (rom:byte(PTRS + species * 2 + 2) << 8)
  return function(i)
    local b = rom:byte(SCRIPTS + off + i + 1)
    if patch and patch[i] then b = patch[i] end
    return b
  end
end
local function slotsOf(f, patches)
  local rec, slots = record(f), {}
  for slot, species in pairs(rec.species) do
    slots[slot] = { species = species,
                    roles = H.partRoles(scriptOf(species, patches and patches[species]), slot) }
  end
  return rec, slots
end
local function orderOf(plan)
  local out = {}
  for _, s in ipairs(plan.order) do out[#out + 1] = tostring(s) end
  return table.concat(out, ",")
end

-- Number 128
local rec, slots = slotsOf(0x1BA)
assert(rec.present == 0x0B and slots[0].species == 0x10B and slots[1].species == 0x140
  and slots[3].species == 0x13F, "$1BA: present $0B, species 10B/140/-/13F")
assert(slots[0].roles.endsBattle and not slots[0].roles.respawns, "$10B: boss_death, no self-restore")
assert(slots[1].roles.respawns and not slots[1].roles.endsBattle, "$140: restores itself on death")
assert(slots[3].roles.respawns and not slots[3].roles.endsBattle, "$13F: restores itself on death")
local plan = H.partsPlan({ slots = slots })
assert(plan and plan.body == 0 and orderOf(plan) == "0", "$1BA: body 0, order {0}")
assert(plan.skip[1] and plan.skip[3], "$1BA: both blades left alone")

-- the Air Force
rec, slots = slotsOf(0x1CB)
assert(rec.present == 0x15 and slots[0].species == 0x113 and slots[2].species == 0x145
  and slots[3].species == 0x146 and slots[4].species == 0x147, "$1CB: present $15, species 113/-/145/146/147")
assert(slots[0].roles.endsBattle, "$113: boss_death")
assert(#slots[0].roles.reads > 0 and slots[0].roles.reads[1].var == 0 and slots[0].roles.reads[1].switch == 0,
  "$113: reads battle switch 0.0")
assert((slots[0].roles.restores & 0x08) ~= 0, "$113: restores slot 3 (the Speck)")
assert(#slots[2].roles.arms == 1 and slots[2].roles.arms[1].var == 0 and slots[2].roles.arms[1].switch == 0,
  "$145: its death sets battle switch 0.0")
assert(not slots[2].roles.respawns and not slots[2].roles.endsBattle, "$145: no restore, no boss_death")
assert(not slots[4].roles.respawns and #slots[4].roles.arms == 0 and not slots[4].roles.endsBattle,
  "$147: plain")
assert(#slots[3].roles.arms == 0 and not slots[3].roles.respawns, "$146: an empty script")
plan = H.partsPlan({ slots = slots })
assert(plan and plan.body == 0 and orderOf(plan) == "2,0", "$1CB: body 0, order {2,0} (got " ..
  (plan and orderOf(plan) or "nil") .. ")")
assert(plan.skip[3] and plan.skip[4] and plan.note[2]:find("switch 0.0", 1, true),
  "$1CB: Speck and bay left alone, the gun's note names the switch")

-- every formation in the table: the linked ones are exactly these nine
-- (the route's two, Rizopas and its piranhas, Dadaluma's Iron Fists,
-- the FlameEater's balloons, and four past the World of Balance)
local linked, plain = {}, 0
for f = 0, #dat // 15 - 1 do
  local _, s = slotsOf(f)
  local n = 0
  for _ in pairs(s) do n = n + 1 end
  if n >= 2 then
    if H.partsPlan({ slots = s }) then linked[#linked + 1] = string.format("%03X", f)
    else plain = plain + 1 end
  end
end
assert(table.concat(linked, " ") == "04F 1B6 1BA 1C1 1C8 1CB 1CE 1D0 1E4",
  "the linked formations are the nine known (got " .. table.concat(linked, " ") .. ")")
-- negative controls
local r2, s2 = slotsOf(0x06F)
assert(H.partsPlan({ slots = s2 }) == nil, "$06F (Mag Roaders): no body, no plan")
local _, whelk = slotsOf(0x1B0)
assert(whelk[0].roles.endsBattle and whelk[1].roles.endsBattle and H.partsPlan({ slots = whelk }) == nil,
  "$1B0 (the Whelk): two slots end the fight, no plan")
-- the body's boss_death rewritten to a plain kill of itself: no body
local bodyOff = rom:byte(PTRS + 0x113 * 2 + 1) | (rom:byte(PTRS + 0x113 * 2 + 2) << 8)
local script113 = scriptOf(0x113)
local bossAt = nil
for i = 0, H.AI_SCRIPT_MAX do
  if script113(i) == 0xF5 and script113(i + 1) == 0x0C and script113(i + 2) == 0x01 and script113(i + 3) == 0xFF then
    bossAt = i; break
  end
end
assert(bossAt, "$113's boss_death found")
local _, s3 = slotsOf(0x1CB, { [0x113] = { [bossAt + 1] = 0x01, [bossAt + 3] = 0x01 } })
assert(not s3[0].roles.endsBattle and H.partsPlan({ slots = s3 }) == nil,
  "$1CB with the body's boss_death a plain kill: no body, no plan")
-- the gun's set_battle_switch rewritten to a clear: the gun is filler
local script145 = scriptOf(0x145)
local armAt = nil
for i = 0, H.AI_SCRIPT_MAX do
  if script145(i) == 0xF9 and script145(i + 1) == 0x01 then armAt = i; break end
end
assert(armAt, "$145's set_battle_switch found")
local _, s4 = slotsOf(0x1CB, { [0x145] = { [armAt + 1] = 0x02 } })
local plan4 = H.partsPlan({ slots = s4 })
assert(#s4[2].roles.arms == 0 and plan4 and orderOf(plan4) == "0" and plan4.skip[2],
  "$1CB with the gun clearing the switch instead: the gun is filler, order {0}")

-- The last-stand counters (#255, M.partRoles' lastStand): a retaliation
-- gated on `if_num_monsters N` (FC 13 01 N).  The Chitonid ($07C) sneezes
-- (attack $CB) at N=1; the HermitCrab ($02C) throws its special (Rock,
-- $EF: the SPECIAL attack) at N=1; the Mesosaur ($021) keeps its own
-- `if_num_monsters 1` in the MAIN section (it stops escaping when alone),
-- which is not a counter; the Osprey ($0E6) counters Magic, not a count.
-- Formation $0CC (Osprey, Chitonid, Gigan Toad) carries exactly the one.
local function lastStandOf(species, patch)
  local r = H.partRoles(scriptOf(species, patch), 0)
  local t = {}
  for _, a in ipairs(r.lastStand) do t[#t + 1] = string.format("%02X", a) end
  return table.concat(t, " "), r.lastStandN
end
local ls, n = lastStandOf(0x07C)
assert(ls == "CB" and n == 1, "$07C Chitonid: last-stand SNEEZE at N=1 (got '" .. ls .. "' N=" .. tostring(n) .. ")")
ls, n = lastStandOf(0x02C)
assert(ls == "EF" and n == 1, "$02C HermitCrab: last-stand SPECIAL at N=1 (got '" .. ls .. "' N=" .. tostring(n) .. ")")
assert(lastStandOf(0x021) == "", "$021 Mesosaur: its if_num_monsters is in the main section, no counter")
assert(lastStandOf(0x0E6) == "", "$0E6 Osprey: counters Magic, no last-stand")
local _, s204 = slotsOf(0x0CC)
local holders = {}
for slot = 0, 5 do
  if s204[slot] and #s204[slot].roles.lastStand > 0 then holders[#holders + 1] = tostring(slot) end
end
assert(table.concat(holders, " ") == "1", "$0CC: the Chitonid in slot 1 is the one last-stand body")
-- negative control: the Chitonid's `if_num_monsters 1` rewritten to
-- `if_num_chars 1` (FC 13 00 01): a count of the party, not of the
-- monsters -- no last-stand counter
local chit = scriptOf(0x07C)
local condAt = nil
for i = 0, H.AI_SCRIPT_MAX do
  if chit(i) == 0xFC and chit(i + 1) == 0x13 and chit(i + 2) == 0x01 then condAt = i; break end
end
assert(condAt, "$07C's if_num_monsters found")
assert(lastStandOf(0x07C, { [condAt + 2] = 0x00 }) == "",
  "$07C with its count turned on the party: no last-stand counter")

print("parts_selftest: PASS -- $1BA {0} with the blades respawning, $1CB {2,0} with the gun "
  .. "arming 0.0 and the Speck the body's; 9 linked formations, " .. plain
  .. " other multi-slot formations plan nothing; last-stand counters: $07C SNEEZE and $02C "
  .. "SPECIAL at N=1, $021 and $0E6 none, $0CC's one in slot 1, the party-count mutant none")

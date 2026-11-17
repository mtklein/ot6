-- lab_spellboost.lua -- a lab (#555): what a boosted tier-family spell shows, casts and charges.
-- Continue LAB_BOOT (default kolts-summit-v1), pace into a random battle, and play LAB_PLAN through the
-- real menu (H.kitBattle), logging every change of the caster's menu state, pending boost, bank, MP and
-- the spell row's list cell (cost byte, enabled bit), every queued cost ($3620), every executed spell
-- ($3410), every fizzle and every Ot6ActionEnd.  Screenshots at the list on each plan entry.
-- Reads and presses only.
-- @manual a lab (#555)
-- @checkpoint kolts-summit-v1
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
-- a plan entry's confirmWhen: rest on the target 45 frames, then a screenshot of the window as it stands
function LAB_WAITSHOT(tag)
  local t0
  return function()
    t0 = t0 or H.frame
    if H.frame - t0 < 45 then return false end
    local s = nil
    for i = 0, 3 do if H.readByte(0x3ED8 + i * 2) == (LAB_WHO or 0) then s = i end end
    H.log(string.format("[sb] f%d target select rested: pend=%d bank=%d mp=%d all=%d", H.frame,
      H.readByte(0x3E9D + s * 2), H.readByte(0x3E9C + s * 2), H.readWord(0x3C08 + s * 2), H.readByte(0x7B7F)))
    H.screenshot("sb_" .. tag)
    return true
  end
end
local BOOT = LAB_BOOT or "kolts-summit-v1"
local WHO = LAB_WHO or 0                      -- TERRA
local SPELL = LAB_SPELL or 0x00               -- Fire
local PLAN = (LAB_PLAN_FN and LAB_PLAN_FN()) or LAB_PLAN or {
  { who = WHO, cmd = 0x02, spell = SPELL, boost = 2 },
}
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local function seat()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == WHO then return s end end
end
local function rowCell(s, id)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[s] + i * 4
    if H.readByte(a) == id then return a end
  end
end
local last = ""
local watching = false
local function sample()
  if not watching or not H.battleActive() then return end
  local s = seat(); if not s then return end
  local a = rowCell(s, SPELL)
  local txt = string.format("menu=%d actor=%d st=%02X pend=%d bank=%d mp=%d row(cost=%d flags=%02X) cmdptr=%02X",
    H.readByte(0x7BCA), H.readByte(0x62CA) & 3, H.readByte(0x7BC2), H.readByte(0x3E9D + s * 2),
    H.readByte(0x3E9C + s * 2), H.readWord(0x3C08 + s * 2), a and H.readByte(a + 3) or -1,
    a and H.readByte(a + 1) or -1, H.readByte(0x32CC + s * 2))
  if txt ~= last then
    H.log(string.format("[sb] f%d %s", H.frame, txt))
    last = txt
  end
end
local shots = 0
H.run({ maxFrames = 120000 }, {
  H.bootCheckpoint(BOOT),
  H.call(function()
    emu.addEventCallback(sample, emu.eventType.startFrame)
    emu.addMemoryCallback(function(_, v)
      if watching then H.log(string.format("[sb] f%d $3410 <- %02X (spell executed)", H.frame, v)) end
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
    emu.addMemoryCallback(function(addr, v)
      if watching then H.log(string.format("[sb] f%d queued cost $%04X <- %d", H.frame, addr - 0x7e0000, v)) end
    end, emu.callbackType.write, 0x7e3620, 0x7e3627)
    emu.addMemoryCallback(function(_, v)
      if watching and v ~= 0 then H.log(string.format("[sb] f%d ching ($6281 <- %02X)", H.frame, v)) end
    end, emu.callbackType.write, 0x7e6281, 0x7e6281)
    emu.addMemoryCallback(function(_, v)
      if watching and v ~= 0 then H.log(string.format("[sb] f%d buzz ($95 <- %02X)", H.frame, v)) end
    end, emu.callbackType.write, 0x7e0095, 0x7e0095)
    emu.addMemoryCallback(function()
      if watching then H.log(string.format("[sb] f%d Ot6FizzleDropBoost x=%02X", H.frame,
        emu.getState()["cpu.x"] & 0xff)) end
    end, emu.callbackType.exec, H.sym("Ot6FizzleDropBoost"))
    emu.addMemoryCallback(function()
      if not watching then return end
      local x = emu.getState()["cpu.x"] & 0xff
      if x < 8 then
        H.log(string.format("[sb] f%d Ot6ActionEnd slot %d: pend=%d bank=%d mp=%d $3a7c=%04X", H.frame, x >> 1,
          H.readByte(0x3E9D + x), H.readByte(0x3E9C + x), H.readWord(0x3C08 + x), H.readWord(0x3A7C)))
      end
    end, emu.callbackType.exec, H.sym("Ot6ActionEnd"))
  end),
  LAB_WORLD and H.seqStep(H.newEncounterDraw({ tag = "sb", minBodies = 1, minHp = 0, pace = LAB_PACE or 4 }).steps())
    or H.paceToEncounter("sb"),
  H.call(function()
    watching = true
    local s = seat()
    H.log(string.format("[sb] battle up: who $%02X seat %s level %d mp %d/%d", WHO, tostring(s),
      s and H.readByte(0x3B18 + s * 2) or -1, s and H.readWord(0x3C08 + s * 2) or -1,
      s and H.readWord(0x3C30 + s * 2) or -1))
  end),
  H.kitBattle(PLAN, {
    maxFrames = 30000,
    untilPlanDone = LAB_UNTIL_DONE,
    onTarget = function(p, a)
      H.log(string.format("[sb] f%d at target select: pend=%d bank=%d mp=%d", H.frame,
        H.readByte(0x3E9D + a * 2), H.readByte(0x3E9C + a * 2), H.readWord(0x3C08 + a * 2)))
      H.screenshot("sb_target")
    end,
    onList = function(p, a)
      shots = shots + 1
      local c = rowCell(a, SPELL)
      H.log(string.format("[sb] f%d at the list: pend=%d bank=%d mp=%d row cost=%d flags=%02X", H.frame,
        H.readByte(0x3E9D + a * 2), H.readByte(0x3E9C + a * 2), H.readWord(0x3C08 + a * 2),
        c and H.readByte(c + 3) or -1, c and H.readByte(c + 1) or -1))
      if shots <= 6 then H.screenshot(string.format("sb_list_%d", shots)) end
    end,
  }),
  H.call(function() watching = false end),
})

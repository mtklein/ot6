-- tools/manual/battle_shots.lua: Celes using Runic and Mog dancing, for their
-- pages.  Not a test; tools/manual/shots.py runs it with OT6_NO_PUBLISH=1.
--
-- Boots the graph's wor_umaro_hunt (TERRA, CYAN, CELES and MOG in the cave
-- below the Narshe cliffs) and paces into a random battle.  The library's
-- menu driver plays everyone's turns (real inputs only) except the first
-- turn of CELES and of MOG, which this script plays through the same
-- command window: down to the second command (RuneKnt, Dance) and A, which
-- opens Celes's list (#563; the driver backs out of it and plays her turn),
-- and for Mog A again on the first Dance in his list.  After each, it takes
-- "<who>_<k>" every 8 frames, k = 1..24.
local H = dofile("tools/tests/lib/ot6.lua")
local CELES, MOG = 6, 10
local F
local own = {}          -- char -> { t = frames into the script, done, shots }
local function charOf(slot) return H.readByte(0x3ed8 + slot * 2) end

local function script(who, presses)
  local s = own[who]
  s.t = s.t + 1
  local i = s.t // 8 + 1                 -- one press per 8 frames: 4 held, 4 released
  if i <= #presses then
    H.setPad(s.t % 8 < 4 and { [presses[i]] = true } or {})
    return
  end
  H.setPad({})
  s.done = true
end

local function shoot()
  for who, s in pairs(own) do
    if s.done and s.k < 24 then
      s.after = s.after + 1
      if s.after % 8 == 0 then
        s.k = s.k + 1
        H.screenshot(s.tag .. "_" .. s.k)
      end
    end
  end
end

local function frame()
  shoot()
  if H.readByte(0x7bca) ~= 0 and H.readByte(0x7bc2) == 0x05 then
    local who = charOf(H.readByte(0x62ca))
    if (who == CELES or who == MOG) and (own[who] == nil or not own[who].done) then
      own[who] = own[who] or { t = 0, k = 0, after = 0, tag = who == CELES and "celes_runic" or "mog_dance" }
      script(who, who == CELES and { "down", "a" } or { "down", "a", "a" })
      return
    end
  end
  for who, s in pairs(own) do
    if not s.done then script(who, who == CELES and { "down", "a" } or { "down", "a", "a" }); return end
  end
  F.frame()
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/wor_umaro_hunt.mss.lua"),
  H.waitFrames(30),
  H.paceToEncounter("manual", 0),
  H.call(function() F = H.newFightDriver("manual_battle", H.fightByMenuOpts()) end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 30000,
    { H.call(frame) }, "fight through the menus"),
})

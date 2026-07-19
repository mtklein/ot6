-- probe_lateboost.lua -- what does a boost pressed during TARGET SELECT
-- actually buy?
--
-- Playtest: "you can boost after selecting the ability" / "once the list
-- is gone you can still boost" / "it looks cosmetic, didn't notice any
-- damage boost or BP being spent".
--
-- Ot6Boost (ot6.asm) gates only on $7bca "a battle menu is open", not on
-- the per-frame menu state $7bc2, so L/R keep working through spell-list
-- and target-select.  Whether that spend PAYS depends on when the action
-- is committed: Ot6QueueFold hangs off CreateAction (battle_main.asm:
-- 12978), which also writes the target list $b8 into the queue -- i.e. it
-- runs AFTER target select.  If that read is right, a late boost folds
-- and multiplies exactly like an early one, and the playtester's "nothing
-- happened" is a perception of the missing spell-list preview rather than
-- a lost spend.  If it is wrong, points are being eaten for nothing.
--
-- Measured here rather than argued: drive the menu by STATE
-- (metrics_battle.lua's idiom -- $7bc2, root $05 / spell $0e / target
-- $38), tap R only once the target cursor is up, and record bp, pending,
-- the queued+executed spell id, and the damage dealt.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local ST = { root = 0x05, spell = 0x0e, target = 0x38 }
local SPELL_FIRE = 0x00
local actor, execd = nil, {}
local mhp0

local function st() return H.readByte(0x7bc2) end
local function bp(s) return H.readByte(0x3e9c + s*2) end
local function pend(s) return H.readByte(0x3e9d + s*2) end
-- $32cc,x is the actor's pending-action command-list pointer, $ff = none
-- (battle_main.asm:254 "set new command list pointer ($ff if no actions
-- pending)"); CreateNormalAction:@4ecb tests it the same way.  Same x
-- indexing as $3e9c/$3e9d, i.e. slot*2 (Ot6QueueFold uses one x for both).
local function cmdptr(s) return H.readByte(0x32cc + s*2) end

-- spell list cursor (metrics_battle.lua:233)
local SPELLBASE = { [0] = 0x0000, [1] = 0x013c, [2] = 0x0278, [3] = 0x03b4 }
local function magicCursor(slot, spellId)
  local base = 0x2092 + SPELLBASE[slot]
  for i = 0, 53 do
    if H.readByte(base + i*4) == spellId then
      local r, c = i // 2, i % 2
      local scroll = (r <= 3) and 0 or math.min(r - 3, 0x17)
      H.writeByte(0x8913 + slot, scroll)
      H.writeByte(0x8917 + slot, c)
      H.writeByte(0x891b + slot, r - scroll)
      return true
    end
  end
  return false
end

local function monsterHp()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3bfc + s*2) end
  return t
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  -- the menu must belong to a real caster: Terra (char index 0), the one
  -- character on this mint who knows a foldable spell (battle_fold.lua
  -- finds her the same way).  Pass turns until it is hers.
  H.driveUntil(function()
    if H.readByte(0x7bca) == 0 then return false end
    local a = H.readByte(0x62ca) & 3
    return H.readByte(0x3ed8 + a*2) == 0
  end, 8000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "terra holds the menu"),
  H.call(function()
    actor = H.readByte(0x62ca) & 3
    H.log(string.format("actor slot %d (terra), menu state %02x", actor, st()))
    H.writeByte(0x3e9c + actor*2, 5)          -- plenty of bp
    H.writeByte(0x3e9d + actor*2, 0)
    H.writeWord(0x3c08 + actor*2, 99)         -- mp
    -- big monster hp so a fold is visible in the damage, and the fight
    -- does not end mid-measurement
    for s = 0, 5 do
      if H.readWord(0x3bfc + s*2) > 0 then H.writeWord(0x3bfc + s*2, 3000) end
    end
    -- stop the guards contesting the run
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    -- magitek armor would force the beam instead of a spell list
    local s1 = 0x3ee4 + actor*2
    H.writeByte(s1, H.readByte(s1) & 0xf7)
    -- Magic in every command cell so one 'a' opens the spell list
    for i = 0, 3 do H.writeByte(0x202e + actor*12 + i*3, 0x02) end
    -- whoever holds the menu may not know Fire; graft it onto their first
    -- KNOWN entry (keeping that entry's targeting/cost bytes, so the list
    -- still renders and confirms) rather than gamble on the roster
    local base = 0x2092 + SPELLBASE[actor]
    local have = false
    for i = 0, 53 do
      if H.readByte(base + i*4) == SPELL_FIRE then have = true end
    end
    if not have then
      for i = 0, 53 do
        if H.readByte(base + i*4) ~= 0xff then
          H.writeByte(base + i*4, SPELL_FIRE)
          H.writeByte(base + i*4 + 1, 0x00)     -- enabled
          H.log(string.format("grafted Fire onto spell-list entry %d", i))
          break
        end
      end
    end
    emu.addMemoryCallback(function(addr, value)
      execd[#execd+1] = value
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- open the spell list
  H.driveUntil(function() return st() == ST.spell end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "spell list open"),
  H.call(function()
    H.assertEq(magicCursor(actor, SPELL_FIRE), true, "cursor parked on Fire")
    H.log(string.format("in spell list: bp=%d pend=%d cmdptr=%02x",
      bp(actor), pend(actor), cmdptr(actor)))
  end),
  H.waitFrames(20),
  -- confirm the spell -> target select.  NO boost pressed yet.
  H.driveUntil(function() return st() == ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target select up"),
  H.call(function()
    H.log(string.format("TARGET SELECT reached: state=%02x bp=%d pend=%d cmdptr=%02x",
      st(), bp(actor), pend(actor), cmdptr(actor)))
    H.assertEq(pend(actor), 0, "no boost pending on entering target select")
  end),
  -- the whole question: does R do anything HERE?
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.log(string.format("after 1st R in target select: state=%02x bp=%d pend=%d",
      st(), bp(actor), pend(actor)))
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    mhp0 = monsterHp()
    H.log(string.format("after 2nd R in target select: bp=%d pend=%d cmdptr=%02x, monster hp %d",
      bp(actor), pend(actor), cmdptr(actor), mhp0))
  end),
  -- confirm the target: this is where CreateAction (and Ot6QueueFold) runs
  H.driveUntil(function() return st() ~= ST.target end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "target confirmed"),
  H.call(function()
    H.log(string.format("target confirmed: state=%02x bp=%d pend=%d menu=%d cmdptr=%02x",
      st(), bp(actor), pend(actor), H.readByte(0x7bca), cmdptr(actor)))
  end),
  -- THE THEFT WINDOW, if there is one: the action is queued (CreateAction
  -- has run, so Ot6QueueFold has already read pending and picked a tier),
  -- but Ot6ActionEnd has not consumed yet.  A boost accepted here would
  -- be charged at ActionEnd against a spell that was already folded at
  -- the older, lower level -- points spent for nothing.
  H.call(function()
    H.log(string.format("POST-CONFIRM probe: menu=%d state=%02x actor-now=%d cmdptr=%02x",
      H.readByte(0x7bca), st(), H.readByte(0x62ca) & 3, cmdptr(actor)))
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.pressButtons({ "r" }, 6), H.waitFrames(12),
  H.call(function()
    H.log(string.format("after post-confirm R x2: bp=%d pend=%d cmdptr=%02x (actor %d)",
      bp(actor), pend(actor), cmdptr(actor), actor))
  end),
  H.waitUntil(function() return #execd > 0 end, 1200, "an action executed", 5),
  -- BP is consumed by Ot6ActionEnd, which runs when the actor's action
  -- FINISHES, not when it fires; poll rather than guess a frame count
  H.waitUntilSoft(function() return pend(actor) == 0 end, 1800,
    "pending consumed", 10),
  H.waitFrames(60),
  H.call(function()
    local ids = {}
    for _, v in ipairs(execd) do ids[#ids+1] = string.format("%02x", v) end
    H.log("executed attack ids: " .. table.concat(ids, " "))
    H.log(string.format("after resolution: bp=%d pend=%d, monster hp %d (dealt %d)",
      bp(actor), pend(actor), monsterHp(), mhp0 - monsterHp()))
    -- Fire $00, Fire 2 $05, Fire 3 $09 (Ot6FoldTbl)
    local folded = false
    for _, v in ipairs(execd) do
      if v == 0x05 or v == 0x09 then folded = true end
    end
    H.log("did the late boost fold the spell tier? " .. tostring(folded))
  end),
})

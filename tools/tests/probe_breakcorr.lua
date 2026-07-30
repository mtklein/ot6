-- probe_breakcorr.lua -- issue #63: is the break moment REVEAL-DEPENDENT?
--
-- #63's filed hypothesis: the arm hangs off Ot6RevealCommit's tail, and that
-- proc "only runs when a reveal is pending", so a break on an enemy whose
-- weakness was revealed on an earlier hit arms nothing.
--
-- Two readings settle it, and neither needs a break to be staged:
--
--   1. HOW OFTEN DOES Ot6RevealCommit RUN WITH NOTHING PENDING?  An exec
--      callback on its entry reads all six slots' OT6_RVPEND_ELEM/CLS.  If it
--      runs at all with every one of them zero, it is not gated on pending --
--      Ot6RevealPoll calls it on every damage-numeral edge (ot6_hud.asm:204,
--      Ot6RevealPoll's own body), and Ot6BreakArm rides the tail regardless.
--   2. DOES A BREAK WITH NOTHING NEW REVEALED STILL ARM?  One staged break
--      with the guard's fire weakness ALREADY revealed, watched at
--      Ot6BreakStart's arming store.
--
-- Deliberately lean: Mesen's testrunner caps a run at 600 wall-clock seconds
-- and LOSES ITS STDOUT when it does, so a probe that needs six staged breaks
-- reports nothing at all.  Two exec callbacks and one break fit.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local BRKTICK  = 0xED76
local RVPENDE  = 0xED45
local RVPENDC  = 0xED51
local REVE     = 0x3E91
local REVC     = 0x3EA5
local BROKEN   = 0x3E90
local SHIELD   = 0x3E40
local MONHP    = 0x3BFC
local MONFLASH = 0x618B
local G = { [1] = 4, [2] = 6 }

local commits, commitsNoPend = 0, 0
local armStores = 0
local sfx = {}
local watch = false

local function install()
  local C = H.sym("Ot6RevealCommit")
  local B = H.sym("Ot6BreakStart")
  local ARM = B + 0x23                 -- sta OT6_BRKPAL,y: the arming store
  H.assertEq(H.readRomByte(ARM & 0x3FFFFF), 0x99,
    "Ot6BreakStart+$23 is the arming store")
  H.log(string.format("Ot6RevealCommit=$%06X, arming store=$%06X", C, ARM))
  emu.addMemoryCallback(function()
    if not watch then return end
    commits = commits + 1
    for s = 0, 5 do
      if H.readByte(RVPENDE + s * 2) ~= 0 or H.readByte(RVPENDC + s * 2) ~= 0 then
        return
      end
    end
    commitsNoPend = commitsNoPend + 1
  end, emu.callbackType.exec, C, C)
  emu.addMemoryCallback(function()
    if watch then armStores = armStores + 1 end
  end, emu.callbackType.exec, ARM, ARM)
  emu.addMemoryCallback(function(_, v)
    if not watch or v == 0 then return end
    if H.readByte(0xE9E9) == 0xBE then sfx[#sfx + 1] = H.frame end
  end, emu.callbackType.write, 0x7EE9EC, 0x7EE9EC)
end

local function mash()
  return {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    install()
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)   -- fire-weak
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    for c = 0, 2 do
      H.writeByte(0x3B18 + c * 2, 5)
      H.writeByte(0x3B41 + c * 2, 10)
    end
    -- pre-reveal fire and refill the gauges, so the break that follows is
    -- guaranteed to reveal NOTHING NEW.  hp high so it survives its own break;
    -- the vanilla turn-flash latch is left ALONE.
    for g = 1, 2 do
      H.writeByte(REVE + G[g], H.readByte(REVE + G[g]) | 0x01)
      H.writeByte(BROKEN + G[g], 0)
      H.writeByte(BRKTICK + G[g], 0)
      H.writeByte(SHIELD + G[g], 2)
      H.writeWord(MONHP + G[g], 6000)
    end
    H.log(string.format("pre-revealed fire: %02X/%02X; turn-flash latch %02X/%02X "
      .. "left alone", H.readByte(REVE + G[1]), H.readByte(REVE + G[2]),
      H.readByte(MONFLASH + 2), H.readByte(MONFLASH + 3)))
    H.vars.rev0 = { H.readByte(REVE + G[1]), H.readByte(REVE + G[2]),
                    H.readByte(REVC + G[1]), H.readByte(REVC + G[2]) }
    watch = true
  end),

  H.driveUntil(function()
    for g = 1, 2 do
      if H.readWord(MONHP + G[g]) < 2500 then H.writeWord(MONHP + G[g], 6000) end
    end
    return armStores > 0
  end, 20000, mash(), "a break on a hit that reveals nothing new"),
  H.release(),
  H.waitFrames(30),

  H.call(function()
    watch = false
    H.log(string.format("Ot6RevealCommit passes: %d, of which with NOTHING "
      .. "pending at entry: %d", commits, commitsNoPend))
    H.log(string.format("arming stores: %d; break cleaves ($BE): %d",
      armStores, #sfx))
    H.log(string.format("revealed E/C now %02X/%02X %02X/%02X (was %02X/%02X %02X/%02X)",
      H.readByte(REVE + G[1]), H.readByte(REVC + G[1]),
      H.readByte(REVE + G[2]), H.readByte(REVC + G[2]),
      H.vars.rev0[1], H.vars.rev0[3], H.vars.rev0[2], H.vars.rev0[4]))

    -- 1. the proc is NOT gated on a pending reveal
    H.assertEq(commitsNoPend > 0, true,
      "Ot6RevealCommit runs even when NOTHING is pending -- the arm on its "
      .. "tail cannot be reveal-gated")
    -- 2. and a break that reveals nothing new arms and cleaves
    H.assertEq(armStores, 1, "the break armed")
    H.assertEq(#sfx, 1, "and cleaved once")
    H.assertEq(H.readByte(REVE + G[1]), H.vars.rev0[1],
      "guard 1's revealed elements never changed")
    H.assertEq(H.readByte(REVE + G[2]), H.vars.rev0[2],
      "guard 2's revealed elements never changed")
  end),
  H.logStep(function() return "probe_breakcorr complete" end),
})

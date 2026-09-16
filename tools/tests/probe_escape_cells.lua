-- @manual
-- probe_escape_cells.lua -- which RAM cells move while L+R holds an escape.
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/banquet-done-v1 \
--     tools/tests/run.sh tools/tests/probe_escape_cells.lua build/states/escape_cells.log
--
-- The first full ninja baseline of the segment runner stopped at
-- crescent_landing: gen_voyage's world walker holds L+R through a world
-- random (the real run mechanic), the command window opens, and the
-- battle no-effect rule read 300 frames of an unmoving menu signature
-- under a held pad as a dead press.  It was not: the engine was counting
-- the escape (CheckRunAway, battle_main.asm ~15549: every ATB tick with
-- $2F45 set adds random($3D71,x)+1 to the run counter $3D70,x and compares
-- it to the run difficulty $3A3B; reaching it sets $3A38 and the
-- character runs).
--
-- This probe boots the same checkpoint the same way gen_voyage does
-- (its opening steps and world walker copied verbatim -- gen_voyage.lua
-- itself is another agent's file), snapshots the machine on the first
-- frame of the first world random, and branches it:
--   A. the walker's own L+R, held until the party is out;
--   B. the same snapshot with the pad released for the same length.
-- Every 16 frames each branch logs one `[escape]` line with the
-- candidate cells, so the diff between A and B says which cells the
-- escape moves and which the mere passage of battle time moves.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local snap = nil          -- the request; snap.blob is the fight's first frame
local snapFrame = nil
local seenBattle = false
local battleDone = false
local escapeFrames = nil

local function cells(tag)
  local rc, rf, atb = {}, {}, {}
  for e = 0, 3 do
    rc[#rc + 1] = string.format("%02X", H.readByte(0x3D70 + e * 2))
    rf[#rf + 1] = string.format("%02X", H.readByte(0x3D71 + e * 2))
    atb[#atb + 1] = string.format("%04X", H.readWord(0x3218 + e * 2))
  end
  H.log(string.format("[escape] %s f%d 2f45=%02X 3a3b=%02X 3a38=%02X "
    .. "3a39=%02X 3a3a=%02X b1=%02X 2f4b=%02X 201f=%02X rc=%s rf=%s atb=%s "
    .. "menu=%02X.%02X mhp=%d",
    tag, H.frame,
    H.readByte(0x2F45), H.readByte(0x3A3B), H.readByte(0x3A38),
    H.readByte(0x3A39), H.readByte(0x3A3A), H.readByte(0x00B1),
    H.readByte(0x2F4B), H.readByte(0x201F),
    table.concat(rc, ","), table.concat(rf, ","), table.concat(atb, ","),
    H.readByte(0x7BCA), H.readByte(0x7BC2),
    H.readWord(0x3BFC) + H.readWord(0x3BFE)))
end

-- gen_voyage.lua's worldGrind, verbatim, plus the snapshot hook on the
-- first battle frame and the [escape] sampler while the battle is up.
local function worldGrind(tx, ty, what)
  local plan, idx, ph, hb = nil, 1, 0, -600
  local step = nil
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  return H.driveUntil(function()
    return battleDone or (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        if not seenBattle then
          seenBattle = true
          snapFrame = H.frame
          snap = H.requestSaveState()
          H.log(string.format("[escape] first battle frame f%d: snapshot "
            .. "requested; the walker holds L+R from here", H.frame))
        end
        if H.frame % 16 == 0 then cells("A:l+r") end
        plan = nil; step = nil
        H.setPad({ l = true, r = true }); return
      end
      if seenBattle and not battleDone then
        battleDone = true
        escapeFrames = H.frame - snapFrame
        cells("A:l+r")
        H.log(string.format("[escape] A: battle over at f%d, %d frames after "
          .. "the first battle frame", H.frame, escapeFrames))
        H.setPad({}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then
        plan = nil; step = nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end   -- hold through the glide
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1               -- landed: next entry
        elseif x ~= step.fx or y ~= step.fy then
          plan = nil; step = nil                  -- drifted: replan
        else
          step.held = step.held + 1
          if step.held > 90 then                  -- press provably dead
            plan = nil; step = nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- Branch B: the same first frame, hands off, for as long as A took (plus a
-- margin), sampling the same cells.
local loadReq = nil
local bStart = nil
local function branchB()
  return H.driveUntil(function()
    return bStart and (H.frame - bStart) >= (escapeFrames or 600) + 240
  end, 6000, {
    H.call(function()
      if not bStart then bStart = H.frame end
      H.setPad({})
      if H.frame % 16 == 0 then cells("B:hands-off") end
      if not H.battleLoadStarted() then
        H.log(string.format("[escape] B: battle over at f%d, %d frames after "
          .. "the restore", H.frame, H.frame - bStart))
      end
    end),
  }, "branch B: hands off from the fight's first frame")
end

H.run({ maxFrames = 30000, retries = 1 }, {
  -- gen_voyage's boot, verbatim
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function() local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 120 and H.worldY() == 188
    end
    return H.driveUntil(function()
      return atSite() and bright() >= 15
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> J-tile world load (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the J tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEntryContract("banquet-done-v1")
  end),
  H.waitFrames(60),
  H.fieldCare({ tag = "care at the J tile", threshold = 0.9 }),

  -- A: the walk, and the first random with the walker's own L+R
  worldGrind(137, 203, "the J->K world walk -> (137,203), west of Albrook"),
  H.call(function()
    assert(seenBattle, "the walk to (137,203) drew no encounter on this seed; "
      .. "nothing to measure (move OT6_SEED_SHIFT and rerun)")
    H.checkReq(snap, "snapshot of the fight's first frame")
    H.log(string.format("[escape] A summary: %d frames from the first battle "
      .. "frame to the field (snapshot %d bytes)", escapeFrames, #snap.blob))
    H.screenshot("escape_a_done")
  end),

  -- B: restore that first frame and keep the hands off
  H.call(function() loadReq = H.requestLoadState(snap.blob) end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(loadReq, "restore of the fight's first frame")
    H.log(string.format("[escape] B: restored the first battle frame at f%d",
      H.frame))
  end),
  branchB(),
  H.call(function() H.screenshot("escape_b_done") end),
})

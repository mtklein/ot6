-- probe_runic_recon.lua -- read-only recon for battle_runic.  Buttons and
-- observation only.
--
-- The post-opera-v1 checkpoint cold Continues to the world map at Vector's
-- west entry point with the same four party members, and world-area trash
-- is levelled for this party where the factory area is not.  Measures:
-- whether the checkpoint's config carries Wait mode; what the area serves
-- (species, levels, HP, MP, and whether any cast); what an unattended party
-- takes; and whether the formations flee on their own.
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/post-opera-v1 \
--     tools/tests/run.sh tools/tests/probe_runic_recon.lua
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF
local function runicable(id)
  return H.readRomByte(MAGIC_PROP + id * 14 + 3) & 0x08 ~= 0
end

local spells = {}
local hpTrace = {}

H.run({ maxFrames = 90000 }, {
  -- cold Continue; the checkpoint's $307ff0=3 preselects slot 3
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("post-opera-v1") end),

  H.call(function()
    local espers = H.readByte(0x1A69) | (H.readByte(0x1A6A) << 8)
    H.log(string.format(
      "[boot] world=(%d,%d) espers=$%04x config $1D4D=$%02x $1D4E=$%02x",
      H.worldX(), H.worldY(), espers,
      H.readByte(0x1D4D), H.readByte(0x1D4E)))
    for _, r in ipairs({ 1, 4, 5, 6 }) do
      local b = 0x1600 + 37 * r
      H.log(string.format(
        "[roster %d] actor=$%02x lvl=%d hp=%d/%d mp=%d/%d esper=$%02x",
        r, H.readByte(b), H.readByte(b + 0x08),
        H.readByte(b + 0x09) | (H.readByte(b + 0x0A) << 8),
        H.readByte(b + 0x0B) | (H.readByte(b + 0x0C) << 8),
        H.readByte(b + 0x0D) | (H.readByte(b + 0x0E) << 8),
        H.readByte(b + 0x0F) | (H.readByte(b + 0x10) << 8),
        H.readByte(b + 0x1E)))
    end
  end),

  -- find the nearest battle-enabled tile (world tile-prop bit6) and pace on it
  H.call(function()
    local x0, y0 = H.worldX(), H.worldY()
    local best, bd = nil, 1e9
    for dy = -12, 12 do
      for dx = -12, 12 do
        local x, y = x0 + dx, y0 + dy
        if x ~= 138 and x ~= 139 then          -- never the Vector entrance
          local ok, p = pcall(H.worldTileProp, x, y)
          if ok and p and (p & 0x40) ~= 0 and H.worldPassable(x, y) then
            local d = dx * dx + dy * dy
            if d < bd then best, bd = { x, y }, d end
          end
        end
      end
    end
    H.assertEq(best ~= nil, true, "a battle-enabled world tile is in reach")
    H.vars.bandX, H.vars.bandY = best[1], best[2]
    H.log(string.format("[area] nearest battle-enabled tile: (%d,%d)",
      best[1], best[2]))
  end),
  H.call(function()
    -- pick a pacing partner tile: a passable neighbor that is not toward
    -- the Vector entrance column (x 138/139, an event trigger rather than
    -- a battle; stepping onto it leaves the world and wedges the pace)
    local x, y = H.vars.bandX, H.vars.bandY
    local pair = nil
    for _, d in ipairs({ { "left", -1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }) do
      local nx, ny = x + d[2], y + d[3]
      if nx ~= 138 and nx ~= 139 and H.worldPassable(nx, ny) then
        pair = { d[1], nx, ny }
        break
      end
    end
    H.assertEq(pair ~= nil, true, "the area tile has a safe pacing partner")
    H.vars.paceDir, H.vars.pairX, H.vars.pairY = pair[1], pair[2], pair[3]
    H.log(string.format("[area] pacing (%d,%d) <-> (%d,%d) via %s",
      x, y, pair[2], pair[3], pair[1]))
  end),
  (function()
    local back = { left = "right", right = "left", up = "down", down = "up" }
    local tick = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.call(function()
        tick = tick + 1
        if tick % 900 == 0 then
          H.log(string.format("  [pace] f%d world=%s pos=(%d,%d)",
            H.frame, tostring(H.worldMode()), H.worldX(), H.worldY()))
        end
        if H.battleLoadStarted() then H.setPad({}); return end
        if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
        local x, y = H.worldX(), H.worldY()
        if x == H.vars.bandX and y == H.vars.bandY then
          H.setPad({ [H.vars.paceDir] = true })
        else
          H.setPad({ [back[H.vars.paceDir]] = true })
        end
      end),
      H.waitFrames(1),
    }, "a real world-area encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    H.log(string.format("[battle] formation $%03x", H.readWord(0x11E0)))
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then
        H.log(string.format("[slot %d] char=$%02x hp=%d/%d mp=%d",
          s, id, H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2),
          H.readWord(0x3C08 + s * 2)))
      end
    end
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
        local e = 8 + m * 2
        H.log(string.format("[mon %d] species=$%04x hp=%d/%d mp=%d lvl=%d",
          m, H.readWord(0x57C0 + m * 2),
          H.readWord(0x3BFC + m * 2), H.readWord(0x3C24 + m * 2),
          H.readWord(0x3C08 + e), H.readByte(0x3B18 + e)))
      end
    end
  end),

  -- temper: unattended for 3600 frames, recording what resolves, what it
  -- costs, and whether the formation flees on its own
  (function()
    local t0 = nil
    return H.repeatN(12, {
      H.call(function()
        t0 = t0 or H.frame
        local hp = {}
        for s = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + s * 2)) end
        local mons = 0
        for m = 0, 5 do
          if H.readByte(0x3AA8 + m * 2) % 2 == 1
             and H.readWord(0x3BFC + m * 2) > 0 then mons = mons + 1 end
        end
        hpTrace[#hpTrace + 1] = string.format("f%+d {%s} mons=%d%s",
          H.frame - t0, table.concat(hp, ","), mons,
          H.battleLoadStarted() and "" or " ENDED")
      end),
      H.waitFrames(300),
    })
  end)(),
  H.call(function()
    H.log("[temper] unattended: " .. table.concat(hpTrace, "  "))
    local ids = {}
    for _, v in ipairs(spells) do
      ids[#ids + 1] = string.format("%02x%s", v, runicable(v) and "*" or "")
    end
    H.log(string.format("[temper] %d ids resolved: %s", #ids,
      table.concat(ids, " ")))
  end),

  -- flee out (if the battle still stands)
  H.cond(function() return H.battleLoadStarted() end, {
    H.driveUntil(function() return not H.battleLoadStarted() end, 8000, {
      H.call(function() H.setPad({ l = true, r = true }) end),
    }, "the area encounter is fled"),
    H.release(),
  }, {}),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl()
  end, 2400, "world control back", 10),
  H.call(function()
    H.log(string.format("[exit] world=(%d,%d) -- recon complete",
      H.worldX(), H.worldY()))
  end),
})

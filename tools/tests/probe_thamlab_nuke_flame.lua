-- probe_thamlab_nuke_flame.lua -- thamasa fire lab, FlameEater sublab:
-- ONE battle-79 attempt under the lib driver's new attack-magic
-- repertoire (opts.nuke / opts.nukeLore), measured and reported.
--
--   tools/tests/run.sh tools/tests/probe_thamlab_nuke_flame.lua
--
-- Boots build/states/thamlab_flame.mss (probe_thamlab_bake.lua: the
-- gen's own route, banked after the care stop just before the (46,53)
-- floor trigger; the trigger re-forces party order STRAGO,TERRA,LOCKE).
-- Battle 79, formation 449: FlameEater absorbs fire, weak ice, water add
-- (thamlab bake header).  The strategy under test is the owner directive:
-- TERRA and LOCKE boosted Ice (Ot6FoldTbl folds the boosted base cast to
-- Ice2, the AoE tier), STRAGO Aqua Rake (lore 3), all through the lib
-- driver rather than a bespoke plan.  Absorb guards, the nuke MP floor,
-- and the lore stall guard are all live; a refusal or a stall is data and
-- shows up in the log.
--
-- The @TOKEN@s follow the rafterlab batch pattern: HOLD aligned frames of
-- standing still before stepping onto the trigger, which advances $021e
-- and thereby the battle seed ($be = $021e * 4 at InitBattle).
--
-- PASSes whether the fight is won or lost -- this file measures, it does
-- not assert.  One machine-readable line per run:
--   [result] lab=flame strategy=nuke-v1 seed=... won=... frames=...

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/thamlab_flame.mss.lua"

local HOLD = tonumber("@HOLD@") or 0
local BANK = tonumber("@BANK@") or 2

local TERRA, LOCKE, STRAGO = 0, 1, 7
local ICE_SPELL, AQUA_RAKE_LORE = 0x01, 3
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local TRIG_X, TRIG_Y = 46, 53
local CONFIRM_BATTLE_GONE = 90

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end

-- per-entity battle HP, for the deaths count
local function bhp(e) return H.readWord(0x3BF4 + e * 2) end
local function bmaxhp(e) return H.readWord(0x3C1C + e * 2) end

local F = H.newFightDriver("flame-nuke", {
  tactical = true, boost = true, bank = BANK,
  items = true, cure = true, healer = TERRA, healPercent = 60,
  nuke = { ICE_SPELL }, nukeLore = { AQUA_RAKE_LORE },
})

local res = {
  seed = -1, won = 0, frames = 0, bframes = 0, deaths = 0,
  fenix = 0, tonic = 0, potion = 0, standing = 0, reason = "none",
}
local bag0 = {}
local f0 = 0
local wasDown = {}

H.run({ maxFrames = 400000, allowGameOver = true }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[flame-nuke] booted at (%d,%d) map=%d phase=%d "
      .. "HOLD=%d BANK=%d", H.fieldX(), H.fieldY(), H.mapId() & 0x1ff,
      H.readByte(0x021E), HOLD, BANK))
    H.assertEq(sw(0x0090), 0, "$0090 clear: FlameEater not fought yet")
    for _, it in ipairs({ TONIC, POTION, FENIX_DOWN }) do
      bag0[it] = H.invCountOf(it)
    end
    f0 = H.frame
  end),
  -- the seed stagger: stand still HOLD frames; $021e keeps ticking
  H.waitFrames(HOLD),

  -- walk onto the trigger tile; the seed is read on the engage edge
  H.driveUntil(function()
    if H.battleLoadStarted() then
      if res.seed < 0 then
        res.seed = H.readByte(0x021E)
        H.log(string.format("[flame-nuke] engaged: seeded from $021e=%d",
          res.seed))
      end
      return true
    end
    return false
  end, 8000, {
    (function()
      local ph = 0
      return H.call(function()
        -- the fixture boots at (46,54), one tile below the trigger.  The
        -- trigger's event (_cbe767) walks the party into formation and
        -- shows a dialog ($07D1) BEFORE `battle 79`, so the approach is a
        -- held UP that switches to edge-tapped A whenever a text box is
        -- up, and battleLoadStarted() is the exit either way.
        ph = (ph + 1) % 8
        if H.dialogWaiting() then
          H.setPad(ph < 4 and { a = true } or {})
        else
          H.setPad({ up = true })
        end
      end)
    end)(),
  }, "walk onto (46,53) -> battle 79"),

  -- the fight, played out by the driver; deaths counted on the 0-HP edge
  (function()
    local notBattle = 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then H.setPad({}); return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 200000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        res.bframes = res.bframes + 1
        for e = 0, 3 do
          if bmaxhp(e) > 0 then
            if bhp(e) == 0 and not wasDown[e] then
              wasDown[e] = true
              res.deaths = res.deaths + 1
            elseif bhp(e) > 0 then
              wasDown[e] = nil
            end
          end
        end
        F.frame()
      end),
    }, "FlameEater fight under the nuke repertoire")
  end)(),
  H.call(function() F.idle() end),

  -- win tail: tap A until $0090 flips; a loss shows itself as the
  -- GameOver read-watch firing (allowGameOver in H.run keeps the run
  -- alive so the [result] line below is still written; NO input once it
  -- has fired, since any press auto-Continues the last save)
  (function()
    local giveUp = 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then H.setPad({}); return true end
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = giveUp % 8
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or GameOver shows itself)")
  end)(),

  H.call(function()
    H.setPad({})
    res.frames = H.frame - f0
    res.won = sw(0x0090) == 1 and 1 or 0
    res.fenix = bag0[FENIX_DOWN] - H.invCountOf(FENIX_DOWN)
    res.tonic = bag0[TONIC] - H.invCountOf(TONIC)
    res.potion = bag0[POTION] - H.invCountOf(POTION)
    local standing = true
    for _, c in ipairs({ TERRA, LOCKE, STRAGO }) do
      if H.charHp(c) == 0 then standing = false end
    end
    res.standing = standing and 1 or 0
    res.reason = res.won == 1 and "win"
      or (H.gameOverFired > 0 and "gameover" or "tail-timeout")
    H.log(string.format(
      "[result] lab=flame strategy=nuke-v1 seed=%d won=%d frames=%d "
      .. "bframes=%d deaths=%d fenix=%d tonic=%d potion=%d mp=%d,%d,%d "
      .. "standing=%d attempts=1 reason=%s",
      res.seed, res.won, res.frames, res.bframes, res.deaths, res.fenix,
      res.tonic, res.potion, H.charMp(TERRA), H.charMp(LOCKE),
      H.charMp(STRAGO), res.standing, res.reason))
  end),
})

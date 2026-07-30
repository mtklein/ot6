.ifndef CODE_EXT_INC
CODE_EXT_INC = 1

; field module
.global LoadMapCharGfx_ext, CheckBattleWorld_ext, DoPoisonDmg_ext
.global DecTimersMenuBattle_ext

; battle module
.global Battle_ext, UpdateBattleTime_ext
.global UpdateEquip_ext, CalcMagicEffect_ext

; ot6 module (bank f0, part of battle object)
.global Ot6LoadFontIcons_ext
.global Ot6AbilityPad_ext
.global Ot6ListIcon_ext, Ot6MagitekIcon_ext, Ot6LoreIcon_ext
.global Ot6ToolListIcon_ext
.global Ot6BgHud_ext, Ot6BgHudFlush_ext, Ot6PipGlyph_ext
.global Ot6ActionEnd, Ot6BoostDmg, Ot6InitBP
.global Ot6CodexSaveAs          ; copy slot-local weakness knowledge on Save As
.global Ot6CodexNewGame, Ot6CodexLoaded
.global Ot6BushidoTier
.global Ot6Oblivion              ; divine: Bushido tech 8, broken-gated in CalcAttackEffect
.global Ot6Assassinate           ; divine: Shadow, broken non-boss instant-kill
.global Ot6StealBoostLevel, Ot6StealSlot   ; boost-tiered steal (chance verb)
.global Ot6SlotRig, Ot6SlotDrift           ; boost-tiered Slot (chance verb):
.global Ot6SlotMiss, Ot6SlotCommit         ;   rig/drift/miss tiers + the
                                           ;   latched-tier charge at commit
.global Ot6ThiefListOpen         ; #55 locke's kit: steal -> tools-shell submenu
.global Ot6ThiefExec             ;   Cmd_05's execute-side dispatch (filch/bestow)
.global Ot6BlitzListOpen         ; v0.3 blitz-as-menu: _c1776b -> tools shell
.global Ot6BushidoListOpen       ; v0.5 bushido submenu (#8): swdtech -> tools shell
.global Ot6BushidoConfirm        ;   confirm shim: row r -> boost r + latch tech
.global Ot6BushidoWindow         ;   enumerate the <=4 window techs into wItemList
.global Ot6LoadoutOpen           ; v0.5 loadout (#8 Layer B): F0 state logic the
.global Ot6LoadoutInput          ;   thin C3 configurator shim jsl's -- seed the
.global Ot6LoadoutSlotTech       ;   four slots, drive input, resolve each slot's
.global Ot6TechLearned           ;   $1cf7 learned-bit test (pool draw + validation)
.global Ot6LoadoutCeil           ;   validated tech, and expose the $1cf7-derived
                                 ;   ceiling (menu reads $1cf7, never $2020)
.global Ot6RageOpen              ; #40 Gau's rage loadout: the same split -- F0
.global Ot6RageInput             ;   owns every decision, the C3 page is tilemap
.global Ot6RageShow              ;   and cursor only.  Show resolves a slot to
.global Ot6RageCount             ;   the id it draws (stored+validated, or the
                                 ;   AUTO window), Count is the LEARNED score
.global Ot6LoadoutIsAuto         ; #49: is the loadout AUTO (all-zero) or MANUAL?
.global Ot6RageIsAuto            ;   one per page -- the pages STATE the mode now,
                                 ;   and must not re-derive it from the save bytes
.global Ot6SkillIconGlyph        ; #53: attack id -> ELEMENT glyph, else its
                                 ;   break-class glyph, else $ff.  The rtl
                                 ;   wrapper over Ot6ElemGlyphFor, so the field
                                 ;   pages and the battle lists decide an
                                 ;   ability's icon in ONE place.  Replaced #46's
                                 ;   class-only Ot6SkillClassGlyph, which existed
                                 ;   only because the field font had no element
                                 ;   tiles to draw.
.global Ot6MenuIcons4bpp_ext     ; #53: put the eight element tiles into the
.global Ot6MenuIcons2bpp_ext     ;   FIELD MENU font -- one entry per vram copy
                                 ;   (BG1's 4bpp at $5000, BG2/BG3's 2bpp at
                                 ;   $6000), each hooked at the tail of the
                                 ;   vanilla loader that lays that copy down
.global Ot6RageRowCost           ;   ALWAYS-defined price shim, Ot6LoadoutCost's
                                 ;   twin (flat trance price / 0 under nomp)
.global Ot6LoadoutCost           ;   ALWAYS-defined price shim (flag-gated body):
                                 ;   forwards to Ot6CostFor under OT6_MP_COSTS,
                                 ;   returns 0 under nomp so the shared menu links
.global Ot6BlitzRowDecorate      ; menu-bank: DrawToolsListText's blitz row shim
                                 ;   (name->$0f swap always; MP cost only under
                                 ;   OT6_MP_COSTS). ALWAYS defined -- the stock C1
                                 ;   btlgfx object jsl's it in both builds.
.global Ot6ToolRowDecorate       ; menu-bank: DrawToolsListText's real-tools row
                                 ;   shim -- a leading MP cost before each tool
                                 ;   name (cost only under OT6_MP_COSTS; a no-op
                                 ;   otherwise). ALWAYS defined -- the shared C1
                                 ;   btlgfx object jsl's it in both builds.
.global Ot6AbilityCost           ; v0.4 mp-cost hook (only defined/referenced
                                 ;   under OT6_MP_COSTS; a weak decl otherwise)
.global Ot6CostFor               ; pure leaf: attack/tool id in A -> MP cost in A
                                 ;   (OT6_MP_COSTS only; battle-object-internal)
.global Ot6PreviewList_ext
.global Ot6EsperSpellKnown       ; M5 espers-as-sub-jobs: equipped esper grants
                                 ;   its spells to the in-battle Magic list
.global Ot6UnionEspers           ; M5: seed the master-list union with equipped
                                 ;   espers' spells so the compacted list has slots
.global Ot6EsperStatMod          ; M5: while-equipped stat mod -- an equipped esper
                                 ;   adds a live +stat to the battle-side stat copy
.global Ot6EsperStatTbl          ; #62: TWO bytes per esper in VANILLA'S OWN
                                 ;   equipment layout (ItemProp+16/+17):
                                 ;     byte 0 = [speed:4][vigor:4]
                                 ;     byte 1 = [magpwr:4][stamina:4]
                                 ;   each nibble [sign:1][magnitude:3], so -7..+7;
                                 ;   $0000 = no mod.  Was one byte of
                                 ;   [sel:4][mag:4] until #62.  BOTH readers move
                                 ;   together: Ot6EsperStatMod (battle) and
                                 ;   DrawEsperDetailMenu's stat block (menu/
                                 ;   skills.asm).  Derivation and the vanilla
                                 ;   decoder it mirrors: ot6_progression.asm.

; #62: the nibble sign flag, shared by both readers of Ot6EsperStatTbl above.
; Set = the magnitude is subtracted.  $8 alone (flag, zero magnitude) decodes to
; zero, which is vanilla's own dead code and is why the encoding is -7..+7 and
; not -8..+7.
OT6_SM_NEG = $8
.global Ot6DanceRowDecorate      ; #34: DrawDanceListText's per-row MP cost
                                 ;   (flat Ot6DanceCost; ALWAYS defined, the
                                 ;   stock C1 object jsl's it in both builds)
.global Ot6RestageGate_ext
.global Ot6FontRestoreMark_ext
.global Ot6DangerStep, Ot6MarkRandom
.global Ot6EntryExitVeil_ext
.global Ot6ScriptBegin_ext, Ot6ScriptEnd_ext
.global Ot6C1Rtl, DrawMagicListText, _c15a17, _c15729, WaitTfrVRAM_far
.global DoMonsterEntryExit
.global MonsterOverlap          ; per-species $8057 seed (btlgfx data);
                                ;   the hud anchor re-derives load-time
                                ;   rows from it (ot6.asm Ot6BgHudLine)

; battle graphics module
.global SineTbl8, SineTbl16
.global ExecBtlGfx_ext, Decompress_ext

; cutscene module
.global OpeningCredits_ext, TitleScreen_ext
.global FloatingContScene_ext, WorldOfRuinScene_ext
.global TheEnd_ext

; menu module
.global OpenMenu_ext, UpdateCtrlBattle_ext, InitCtrl_ext, UpdateCtrlField_ext
.global IncGameTime_ext, LoadSavedGame_ext, EndingCutscene_ext
.global OptimizeCharEquip_ext, EndingAirshipScene_ext

; sound module
.global InitSound_ext, ExecSound_ext
.global TfrSong_ext, TfrSongScript_ext  ; unused

; world module
.global LoadWorld_ext, UpdateMode7Vars_ext, UpdateMode7Rot_ext
.global PushMode7Vars_ext, PopMode7Vars_ext, UpdateMode7Circle_ext
.global MagitekTrain_ext, EndingAirshipScene2_ext

.endif

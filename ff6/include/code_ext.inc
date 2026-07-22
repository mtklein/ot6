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
.global Ot6BushidoTier
.global Ot6Oblivion              ; divine: Bushido tech 8, broken-gated in CalcAttackEffect
.global Ot6Assassinate           ; divine: Shadow, broken non-boss instant-kill
.global Ot6StealBoostLevel, Ot6StealSlot   ; boost-tiered steal (chance verb)
.global Ot6BlitzListOpen         ; v0.3 blitz-as-menu: _c1776b -> tools shell
.global Ot6BlitzRowDecorate      ; menu-bank: DrawToolsListText's blitz row shim
                                 ;   (name->$0f swap always; MP cost only under
                                 ;   OT6_MP_COSTS). ALWAYS defined -- the stock C1
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
.global Ot6BoostMarksNmi_ext
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

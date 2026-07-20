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
<<<<<<< HEAD
.global Ot6StealBoostLevel, Ot6StealSlot   ; boost-tiered steal (chance verb)
=======
.global Ot6BlitzListOpen         ; v0.3 blitz-as-menu: _c1776b -> tools shell
>>>>>>> da1c691 (blitz: the command becomes a menu -- the pad-edge code reader dies, the Tools window shell picks a learned blitz)
.global Ot6AbilityCost           ; v0.4 mp-cost hook (only defined/referenced
                                 ;   under OT6_MP_COSTS; a weak decl otherwise)
.global Ot6PreviewList_ext
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

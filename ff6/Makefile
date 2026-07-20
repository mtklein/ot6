
# (ot6) delete half-written targets when a recipe fails, e.g. fix_checksum dying mid-build
.DELETE_ON_ERROR:

# the assembler
ASM = ca65
ASMFLAGS = -g -I include
VERSION_EXT =

# the linker
LINK = ld65
LINKFLAGS =

# script to fix the SNES checksum
FIX_CHECKSUM = python3 tools/fix_checksum.py

# list of ROM versions
VERSIONS = ff6-jp ff6-en ff6-en1
OBJ_DIR = obj
ROM_DIR = rom
ROMS = $(foreach V, $(VERSIONS), $(ROM_DIR)/$(V).sfc)

# the SPC program
SPC_PRG = src/sound/ff6-spc.dat

.PHONY: all rip clean distclean mml spc wav rng event monster_gfx text dte \
	lz ff6-en-mp $(VERSIONS) $(MODULES)

# disable default suffix rules
.SUFFIXES:

# make all versions
all: $(VERSIONS)

# rip data from ROMs
rip:
	python3 tools/extract_assets.py
	python3 tools/fix_dlg.py combine en
	python3 tools/fix_dlg.py combine jp

# shuffle the RNG table
rng:
	python3 tools/shuffle_rng.py src/field/rng_tbl.dat

spc: $(SPC_PRG)

clean:
	$(RM) -rf $(ROM_DIR) $(OBJ_DIR)
	$(RM) -f src/text/*.dat
	$(RM) src/menu/menu_text_*.inc.raw
	$(RM) src/sound/song_script/*.asm src/sound/sfx_script/*.asm
	$(RM) src/sound/sample_brr/*.wav src/sound/sfx_brr/*.wav
	$(RM) $(SPC_PRG)
	$(RM) rom/ff6-event.bin

distclean: clean
	python3 tools/clean_assets.py

# ROM filenames
FF6_JP_PATH = $(ROM_DIR)/ff6-jp.sfc
FF6_EN_PATH = $(ROM_DIR)/ff6-en.sfc
FF6_EN1_PATH = $(ROM_DIR)/ff6-en1.sfc

ff6-jp: $(FF6_JP_PATH)
ff6-en: $(FF6_EN_PATH)
ff6-en1: $(FF6_EN1_PATH)

# set up target-specific variables
ff6-jp: VERSION_EXT = jp
ff6-en: VERSION_EXT = en
ff6-en1: VERSION_EXT = en1

ff6-jp: ASMFLAGS += -D ROM_VERSION=0
ff6-en: ASMFLAGS += -D LANG_EN=1 -D ROM_VERSION=0
ff6-en1: ASMFLAGS += -D LANG_EN=1 -D ROM_VERSION=1

%.lz: %
	python3 tools/ff6_lzss.py $< $@

# list of all include files
INC_FILES = $(wildcard include/*.inc) $(wildcard include/*/*.inc)

# target-specific object filenames
OBJ_FILES_JP = $(foreach M,$(MODULES),$(OBJ_DIR)/$(M)_jp.o)
OBJ_FILES_EN = $(foreach M,$(MODULES),$(OBJ_DIR)/$(M)_en.o)
OBJ_FILES_EN1 = $(foreach M,$(MODULES),$(OBJ_DIR)/$(M)_en1.o)

# list of modules
MODULES = field btlgfx battle menu sound cutscene event world gfx text

# (ot6) Compressed-data files the assembler reads at eval time, derived
# from TRACKED SOURCES so the list is complete even in a tree with zero
# .lz files. The module deps below are parse-time $(wildcard)s, so a .lz
# that does not exist yet is invisible to them and never gets scheduled;
# deriving from existing .lz would inherit that circularity. Two
# reference classes: eight directories consumed wholesale through
# .sprintf-built filenames (grep cannot see those names), and literal
# .incbin paths ($(wildcard) drops sources absent from this rip, e.g.
# the jp-only title/status graphics).
LZ_SPRINTF_DIRS = src/field/map_tile_prop src/field/map_tileset \
	src/field/overlay_prop src/field/sub_tilemap \
	src/gfx/battle_bg_tiles src/gfx/battle_bg_gfx \
	src/gfx/map_gfx_bg3 src/gfx/map_anim_gfx_bg3
LZ_LITERAL_SRC = \
	src/gfx/airship1.4bpp src/gfx/airship2.4bpp \
	src/gfx/attack_mode7.4bpp src/gfx/attack_mode7.scr \
	src/gfx/credits.4bpp src/gfx/ending_font.2bpp \
	src/gfx/ending1.4bpp src/gfx/ending2.4bpp src/gfx/ending3.4bpp \
	src/gfx/ending4.4bpp src/gfx/ending5.4bpp \
	src/gfx/floating_cont.4bpp src/gfx/magitek_train.cgx \
	src/gfx/minimap_1.4bpp src/gfx/minimap_2.4bpp \
	src/gfx/ruin_cutscene.4bpp \
	src/gfx/status_en.4bpp src/gfx/status_jp.4bpp \
	src/gfx/title_opening_en.4bpp src/gfx/title_opening_jp.4bpp \
	src/gfx/vector_approach.4bpp src/gfx/vector_approach.scr \
	src/gfx/world_1_bg.4bpp src/gfx/world_2_bg.4bpp \
	src/gfx/world_3_bg.4bpp src/gfx/world_3.pal \
	src/gfx/world_anim_sprite.4bpp src/gfx/world_misc_sprite.4bpp \
	src/gfx/world_backdrop.4bpp src/gfx/world_backdrop.scr \
	src/gfx/world_choco_1.4bpp src/gfx/world_choco_2.4bpp \
	src/world/world_1_tilemap.dat src/world/world_2_tilemap.dat \
	src/world/world_3_tilemap.dat
LZ_FILES := $(addsuffix .lz,\
	$(filter-out %.lz,$(foreach D,$(LZ_SPRINTF_DIRS),$(wildcard $(D)/*))) \
	$(wildcard $(LZ_LITERAL_SRC)))

# (ot6) This explicit rule is what keeps the .lz files on disk: mentioned
# only by pattern rules (the module objects) they would be chain
# intermediates, which make builds, uses, and then DELETES at the end of
# the run -- observed as `rm src/...lz` after an otherwise clean build,
# forcing full recompression every make. Doubles as a manual pre-build:
# `make lz`.
lz: $(LZ_FILES)

# generate rules for making each module
# (ot6) $(LZ_FILES) is order-only: it guarantees every .lz exists and is
# fresh before assembly without making all objects stale whenever any one
# .lz changes; per-object staleness comes from the wildcard deps and the
# ca65 depfiles below.
define MAKE_MODULE
$1_SRC := $(wildcard src/$1/*) $(wildcard src/$1/*/*)
$$(OBJ_DIR)/$1_%.o: $$($1_SRC) $$(INC_FILES) | $$(LZ_FILES)
	@mkdir -p $$(OBJ_DIR)
	$$(ASM) $$(ASMFLAGS) --create-dep $$(@:o=d) -l $$(@:o=lst) src/$1/$1_main.asm -o $$@
endef

$(foreach M, $(MODULES), $(eval $(call MAKE_MODULE,$(M))))

# (ot6) Exact per-object dependencies recorded by ca65 on the previous
# build (.include and .incbin files alike, so cross-module data like
# src/world/*.dat.lz is covered). These cannot replace $(LZ_FILES) for a
# fresh clone: no .d file exists before the first successful build.
-include $(wildcard $(OBJ_DIR)/*.d)

# temporary compressed cutscene program file
LZ_DIR = temp_lz
CUTSCENE_LZ = $(LZ_DIR)/cutscene.lz
CUTSCENE_LZ_ASM = $(LZ_DIR)/cutscene_lz.asm

$(OBJ_DIR)/ff6-spc.o: src/sound/ff6-spc.asm
	@mkdir -p $(OBJ_DIR)
	$(ASM) $(ASMFLAGS) -l $(@:o=lst) $< -o $@

$(SPC_PRG): cfg/ff6-spc.cfg $(OBJ_DIR)/ff6-spc.o
	$(LINK) $(LINKFLAGS) -o $@ -C $< $(OBJ_DIR)/ff6-spc.o

# list of all text files
TEXT_JSON_JP = $(wildcard src/text/*_jp.json)
TEXT_JSON_EN = $(wildcard src/text/*_en.json) src/text/mte_tbl_jp.json
TEXT_DAT_JP = $(TEXT_JSON_JP:json=dat)
TEXT_DAT_EN = $(TEXT_JSON_EN:json=dat)

text_jp: $(TEXT_DAT_JP) src/menu/menu_text_jp.inc.raw
text_en: $(TEXT_DAT_EN) src/menu/menu_text_en.inc.raw
text: text_jp text_en

src/text/dlg1_%.dat src/text/dlg2_%.dat: src/text/dlg1_%.json src/text/dlg2_%.json
	python3 tools/fix_dlg.py split $*
	python3 tools/encode_text.py src/text/dlg1_$*.json
	python3 tools/encode_text.py src/text/dlg2_$*.json
	python3 tools/fix_dlg.py combine $*
	@touch $@

src/text/%.dat: src/text/%.json
	python3 tools/encode_text.py $<

dte:
	python3 tools/fix_dlg.py dte en

# rules for encoding menu text
%.inc.raw: %.inc
	python3 tools/encode_menu_text.py $<

# rules for converting mml files to asm
SONG_MML_FILES = $(wildcard src/sound/song_script/*.mml)
SONG_ASM_FILES = $(SONG_MML_FILES:mml=asm)

SFX_MML_FILES = $(wildcard src/sound/sfx_script/*.mml)
SFX_ASM_FILES = $(SFX_MML_FILES:mml=asm)

mml: $(SONG_ASM_FILES) $(SFX_ASM_FILES)

src/sound/song_script/%.asm: src/sound/song_script/%.mml
	python3 tools/encode_mml.py $<

src/sound/sfx_script/%.asm: src/sound/sfx_script/%.mml
	python3 tools/encode_sfx.py $<

# rules for converting extracted BRR files to WAV files
BRR_FILES = $(wildcard src/sound/sample_brr/*.brr) \
	$(wildcard src/sound/sfx_brr/*.brr)
WAV_FILES = $(BRR_FILES:brr=wav)
wav: $(WAV_FILES)

%.wav: %.brr
	python3 tools/brr.py $< $@

# rules for trimming monster graphics
MONSTER_GFX_FILES = $(wildcard src/gfx/monster_gfx/*.4bpp) \
	$(wildcard src/gfx/monster_gfx/*.3bpp)
MONSTER_TRIMMED_FILES = $(addsuffix .trm,$(MONSTER_GFX_FILES))
monster_gfx: $(MONSTER_TRIMMED_FILES)

%.trm: %
	python3 tools/monster_stencil.py $<

event: rom/ff6-event.bin

rom/ff6-event.bin: cfg/ff6-event.cfg obj/event_en.o
	$(LINK) $(LINKFLAGS) -o $@ -C $< obj/event_en.o

# rules for making ROM files
# run linker twice: 1st for the cutscene program, 2nd for the ROM itself
$(FF6_JP_PATH): cfg/ff6-jp.cfg spc mml text_jp monster_gfx $(OBJ_FILES_JP)
	@mkdir -p $(LZ_DIR) $(ROM_DIR)
	$(LINK) $(LINKFLAGS) -o "" -C $< $(OBJ_FILES_JP)
	python3 tools/encode_cutscene.py $(CUTSCENE_LZ:lz=bin) $(CUTSCENE_LZ)
	@printf '.segment "cutscene_lz"\n.incbin "cutscene.lz"' > $(CUTSCENE_LZ_ASM)
	$(ASM) --bin-include-dir $(LZ_DIR) $(CUTSCENE_LZ_ASM) -o $(CUTSCENE_LZ).o
	$(LINK) $(LINKFLAGS) --dbgfile $(@:sfc=dbg) -m $(@:sfc=map) -o $@ -C $< $(OBJ_FILES_JP) $(CUTSCENE_LZ).o
	@$(RM) -rf $(LZ_DIR)
	$(FIX_CHECKSUM) $@

$(FF6_EN_PATH): cfg/ff6-en.cfg spc mml text_en monster_gfx $(OBJ_FILES_EN)
	@mkdir -p $(LZ_DIR) $(ROM_DIR)
	$(LINK) $(LINKFLAGS) -o "" -C $< $(OBJ_FILES_EN)
	python3 tools/encode_cutscene.py $(CUTSCENE_LZ:lz=bin) $(CUTSCENE_LZ)
	@printf '.segment "cutscene_lz"\n.incbin "cutscene.lz"' > $(CUTSCENE_LZ_ASM)
	$(ASM) --bin-include-dir $(LZ_DIR) $(CUTSCENE_LZ_ASM) -o $(CUTSCENE_LZ).o
	$(LINK) $(LINKFLAGS) --dbgfile $(@:sfc=dbg) -m $(@:sfc=map) -o $@ -C $< $(OBJ_FILES_EN) $(CUTSCENE_LZ).o
	@$(RM) -rf $(LZ_DIR)
	$(FIX_CHECKSUM) $@

$(FF6_EN1_PATH): cfg/ff6-en.cfg spc mml text_en monster_gfx $(OBJ_FILES_EN1)
	@mkdir -p $(LZ_DIR) $(ROM_DIR)
	$(LINK) $(LINKFLAGS) -o "" -C $< $(OBJ_FILES_EN1)
	python3 tools/encode_cutscene.py $(CUTSCENE_LZ:lz=bin) $(CUTSCENE_LZ)
	@printf '.segment "cutscene_lz"\n.incbin "cutscene.lz"' > $(CUTSCENE_LZ_ASM)
	$(ASM) --bin-include-dir $(LZ_DIR) $(CUTSCENE_LZ_ASM) -o $(CUTSCENE_LZ).o
	$(LINK) $(LINKFLAGS) --dbgfile $(@:sfc=dbg) -m $(@:sfc=map) -o $@ -C $< $(OBJ_FILES_EN1) $(CUTSCENE_LZ).o
	@$(RM) -rf $(LZ_DIR)
	$(FIX_CHECKSUM) $@

# --------------------------------------------------------------------- ot6 --
# v0.4 "every ability costs MP" -- the OT6_MP_COSTS=1 ON build, for the A/B
# mpcost gate (tools/tests/battle_mpcost.lua). ONLY the battle module reads
# the flag (battle_main.asm + ot6.asm) -- the other nine assemble to
# byte-identical objects with it set or clear -- so this rebuilds JUST the
# battle object with the flag and relinks it against the stock en objects.
# It is the ff6-en recipe verbatim but for that one substituted object, and
# it proves the ON path assembles and links cheaply. The battle object is
# named battlemp_en.o (NOT battle_en-mp.o) so it can't collide with the
# generated battle_%.o pattern rule, which would build it flag-clear.
OBJ_BATTLE_MP = $(OBJ_DIR)/battlemp_en.o
OBJ_FILES_EN_MP = $(patsubst $(OBJ_DIR)/battle_en.o,$(OBJ_BATTLE_MP),$(OBJ_FILES_EN))

ff6-en-mp: $(ROM_DIR)/ff6-en-mp.sfc

$(OBJ_BATTLE_MP): $(battle_SRC) $(INC_FILES) | $(LZ_FILES)
	@mkdir -p $(OBJ_DIR)
	$(ASM) $(ASMFLAGS) -D LANG_EN=1 -D ROM_VERSION=0 -D OT6_MP_COSTS=1 \
		--create-dep $(@:o=d) -l $(@:o=lst) src/battle/battle_main.asm -o $@

$(ROM_DIR)/ff6-en-mp.sfc: cfg/ff6-en.cfg spc mml text_en monster_gfx $(OBJ_FILES_EN_MP)
	@mkdir -p $(LZ_DIR) $(ROM_DIR)
	$(LINK) $(LINKFLAGS) -o "" -C $< $(OBJ_FILES_EN_MP)
	python3 tools/encode_cutscene.py $(CUTSCENE_LZ:lz=bin) $(CUTSCENE_LZ)
	@printf '.segment "cutscene_lz"\n.incbin "cutscene.lz"' > $(CUTSCENE_LZ_ASM)
	$(ASM) --bin-include-dir $(LZ_DIR) $(CUTSCENE_LZ_ASM) -o $(CUTSCENE_LZ).o
	$(LINK) $(LINKFLAGS) --dbgfile $(@:sfc=dbg) -m $(@:sfc=map) -o $@ -C $< $(OBJ_FILES_EN_MP) $(CUTSCENE_LZ).o
	@$(RM) -rf $(LZ_DIR)
	$(FIX_CHECKSUM) $@

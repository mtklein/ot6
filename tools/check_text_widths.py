#!/usr/bin/env python3
"""check_text_widths.py -- item descriptions and battle command names fit their windows.

    python3 tools/check_text_widths.py              # check; print the widest lines
    python3 tools/check_text_widths.py --show NAME  # also print the lines of the items whose name holds NAME
    python3 tools/check_text_widths.py --selftest   # the checks catch a line one pixel too wide, a name too long

Item descriptions (src/text/item_desc_en.json) are drawn in the menus' variable-width font into the help
window at the top of the Item, Equip and Relic menus, one or two lines.  Each line is measured in pixels from
FontWidth (src/gfx/font_gfx.asm, the rule tools/esper_ladder.py uses for the esper page's help line) and must
fit DESC_WIDTH, the widest vanilla line ("Enemy becomes self-destructive", 223 pixels): the window that holds
every vanilla line holds it.

Battle command names (src/text/battle_cmd_name_en.json, BattleCmdName) are drawn in the fixed 8-pixel font, a
record's cells one tile each, by every window that names a command: the battle command window, the field
Status screen's command list and Gogo's command picker (status.asm DrawCmdName / DrawCmdNameGogo), and the
Skills list's TresHnt and Painter rows (ot6_painter_page.asm Ot6SkillsCmdRow).  Each draws the record's
item_size cells and nothing past them, and each window's text area is that many tiles wide, so a name fits
exactly when its encoded length is at most item_size (7 cells, 56 pixels).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import esper_ladder as el  # noqa: E402

DESC_JSON = os.path.join(ROOT, "ff6", "src", "text", "item_desc_en.json")
NAME_JSON = os.path.join(ROOT, "ff6", "src", "text", "item_name_en.json")
CMD_JSON = os.path.join(ROOT, "ff6", "src", "text", "battle_cmd_name_en.json")


def cmd_codec(tables):
    sys.path.insert(0, os.path.join(ROOT, "ff6", "tools"))
    cwd = os.getcwd()
    os.chdir(os.path.join(ROOT, "ff6"))
    try:
        import romtools as rt
        return rt.TextCodec({"char_tables": tables})
    finally:
        os.chdir(cwd)


def desc_lines(texts):
    """[(item index, line number, line)] for every description line."""
    out = []
    for i, t in enumerate(texts):
        for k, line in enumerate(t.split("{n}")):
            out.append((i, k, line))
    return out


def check(descs, cmds, item_size, cmd_tables, show=None, names=None):
    dc = el.desc_codec()
    widths = el.font_widths()
    problems, rows = [], []
    for i, k, line in desc_lines(descs):
        w = el.desc_width(dc, widths, line)
        rows.append((w, i, k, line))
        if w > el.DESC_WIDTH:
            problems.append("item $%02X description line %d is %d pixels, over the help window's %d: %r"
                            % (i, k + 1, w, el.DESC_WIDTH, line))
    cc = cmd_codec(cmd_tables)
    crow = []
    for i, name in enumerate(cmds):
        b = [x for x in cc.encode(name) if x != 0] if name else []
        crow.append((len(b), i, name))
        if len(b) > item_size:
            problems.append("battle command $%02X %r is %d cells, over the windows' %d" % (i, name, len(b), item_size))
    rows.sort(reverse=True)
    for w, i, k, line in rows[:3]:
        print("widest description lines: %3d px  item $%02X line %d  %r" % (w, i, k + 1, line))
    if show and names:
        for w, i, k, line in sorted(rows, key=lambda r: (r[1], r[2])):
            if show.lower() in names[i].lower():
                print("item $%02X %s line %d: %d of %d px  %r" % (i, names[i], k + 1, w, el.DESC_WIDTH, line))
        for n, i, name in crow:
            if show.lower() in name.lower():
                print("battle command $%02X %r: %d of %d cells (%d of %d px)" % (i, name, n, item_size, 8 * n,
                                                                                   8 * item_size))
    full = [name for n, i, name in crow if n == item_size]
    print("battle command names at the full %d cells: %s" % (item_size, ", ".join(full)))
    return problems


def load():
    d = json.load(open(DESC_JSON))
    c = json.load(open(CMD_JSON))
    names = [n.split("}")[-1] for n in json.load(open(NAME_JSON))["text"]]
    return d["text"], c["text"], c["item_size"], c["char_tables"], names


def selftest():
    descs, cmds, size, tables, names = load()
    bad = []
    if check(descs, cmds, size, tables):
        bad.append("the tree's own text fails")
    widest = max(desc_lines(descs), key=lambda r: el.desc_width(el.desc_codec(), el.font_widths(), r[2]))
    wider = list(descs)
    wider[widest[0]] = descs[widest[0]].replace(widest[2], widest[2] + "W") if widest[2] else "W" * 40
    if not any("description" in p for p in check(wider, cmds, size, tables)):
        bad.append("a description line widened past the window passed")
    longer = list(cmds)
    longer[0x0D] = cmds[0x0D] + "s"
    if not any("battle command $0D" in p for p in check(descs, longer, size, tables)):
        bad.append("an eight-cell command name passed")
    if bad:
        print("check_text_widths selftest: FAIL: " + "; ".join(bad))
        return 1
    print("check_text_widths selftest: PASS (the tree's text fits; a widened line and a long name are caught)")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    show = argv[argv.index("--show") + 1] if "--show" in argv else None
    descs, cmds, size, tables, names = load()
    problems = check(descs, cmds, size, tables, show, names)
    for p in problems:
        print("check_text_widths: " + p)
    if problems:
        return 1
    print("check_text_widths: every item description line within %d px; every battle command name within %d cells"
          % (el.DESC_WIDTH, size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

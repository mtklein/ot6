#!/usr/bin/env python3
"""Build the OT6 instruction booklet: build/manual/ot6-manual.pdf, copied to
docs/manual/ot6-manual.pdf (tracked) with docs/manual/ot6-manual.stamp.

    python3 tools/manual/build.py                 # the PDF
    python3 tools/manual/build.py --booklet       # and the printer's 2-up version
    python3 tools/manual/build.py --version 0.47  # the version the cover prints
    python3 tools/manual/build.py --png 1,5,9     # and PNG renders of those pages
                                                  #   (build/manual/pages/page-NN.png)
    python3 tools/manual/build.py --check         # is the tracked PDF today's?
                                                  #   (no browser; qualification runs it)

The stamp records a hash of the booklet's inputs (INPUTS below) and of the
PDFs written from them.  --check fails when either no longer matches the
tree: a source or docs/PLAYING.md changed without a rebuild, or a tracked PDF
was replaced by hand.  The version is recorded but not checked, so main's
version bump after a release does not stale the release's booklet.  Once
docs/manual/ot6-manual-booklet.pdf is tracked, every build rewrites it too.

Sources, all in tools/manual/: manual.html (the text, one <section
class="page"> per printed page), manual.css, fonts/ (OFL fonts, vendored),
img/ (emulator screenshots at 256x224, made by shots.py).  The build scales
the screenshots up with nearest-neighbour, fills in the version and page
numbers, and prints the HTML to PDF with headless Chromium.  Nothing is
fetched from the network.

Chromium is looked for in $OT6_CHROME, on PATH (chromium, chromium-browser,
google-chrome, google-chrome-stable, chrome-headless-shell), in
/Applications, and in Playwright's browser cache.  Needs Pillow.

The build fails if any page's content overflows the page, or if the page
count is not a multiple of four (the booklet is folded from sheets of four
pages; add or remove a notes page).
"""
import argparse
import glob
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tools" / "manual"
OUT = ROOT / "build" / "manual"
SCALE = 4            # 256x224 -> 1024x896, nearest-neighbour
PAGE_PX = (528, 816)  # 5.5in x 8.5in at 96 px/in
DOCS = ROOT / "docs" / "manual"
STAMP = DOCS / "ot6-manual.stamp"
INPUTS = ["tools/manual/manual.html", "tools/manual/manual.css", "tools/manual/checks.js",
          "tools/manual/build.py", "tools/manual/fonts/*", "tools/manual/img/*.png",
          "docs/PLAYING.md"]


def sha256(path):
    import hashlib
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inputs_hash():
    import hashlib
    h = hashlib.sha256()
    files = sorted({f for pat in INPUTS for f in glob.glob(str(ROOT / pat))})
    for f in files:
        h.update(f"{Path(f).relative_to(ROOT)}\0{sha256(f)}\n".encode())
    return h.hexdigest(), len(files)


def read_stamp():
    out = {}
    if STAMP.exists():
        for line in STAMP.read_text().splitlines():
            if line and not line.startswith("#"):
                k, _, v = line.partition(" ")
                out[k] = v.strip()
    return out


def check():
    """The tracked PDFs against today's inputs; no browser."""
    st = read_stamp()
    fix = ("rebuild with `python3 tools/manual/build.py` (`--version X.Y` at a release) "
           "and commit docs/manual/")
    if not st:
        sys.exit(f"build.py --check: no {STAMP.relative_to(ROOT)}; {fix}")
    now, n = inputs_hash()
    bad = []
    if st.get("inputs") != now:
        bad.append(f"the booklet's {n} input files changed since the tracked PDF was built "
                   f"(stamp {st.get('inputs', '?')[:12]}, tree {now[:12]})")
    for key, name in (("pdf", "ot6-manual.pdf"), ("booklet", "ot6-manual-booklet.pdf")):
        f = DOCS / name
        if key in st and not f.exists():
            bad.append(f"docs/manual/{name} is missing")
        elif key in st and sha256(f) != st[key]:
            bad.append(f"docs/manual/{name} is not the file the stamp records")
        elif key not in st and f.exists():
            bad.append(f"docs/manual/{name} is not in the stamp")
    if bad:
        sys.exit("build.py --check: " + "; ".join(bad) + f".\n  {fix}")
    print(f"build.py --check: docs/manual is today's ({n} inputs, {now[:12]}; "
          f"v{st.get('version', '?')})")


def find_chrome():
    cands = []
    if os.environ.get("OT6_CHROME"):
        cands.append(os.environ["OT6_CHROME"])
    for name in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable",
                 "chrome-headless-shell", "chrome"):
        p = shutil.which(name)
        if p:
            cands.append(p)
    cands += [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
    ]
    home = Path.home()
    for cache in (home / "Library/Caches/ms-playwright", home / ".cache/ms-playwright"):
        cands += sorted(glob.glob(str(cache / "chromium_headless_shell-*/*/chrome-headless-shell")),
                        reverse=True)
        cands += sorted(glob.glob(str(cache / "chromium-*/chrome-linux*/chrome")), reverse=True)
        cands += sorted(glob.glob(str(cache / "chromium-*/chrome-mac*/*.app/Contents/MacOS/*")),
                        reverse=True)
    for c in cands:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    sys.exit("build.py: no Chromium found.  Install Google Chrome or Chromium, or "
             "`python3 -m playwright install chromium-headless-shell`, or set OT6_CHROME.")


def scale_images(dst):
    from PIL import Image
    dst.mkdir(parents=True, exist_ok=True)
    for png in sorted((SRC / "img").glob("*.png")):
        im = Image.open(png).convert("RGB")
        im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST).save(
            dst / png.name, optimize=True)


def esper_tables():
    """The Esper table from docs/PLAYING.md ("### Every Esper"), as two HTML tables."""
    md = (ROOT / "docs" / "PLAYING.md").read_text()
    sec = md.split("### Every Esper", 1)[1].split("\n#", 1)[0]
    rows = [r for r in sec.splitlines() if r.startswith("| ") and not r.startswith("| Esper")
            and not r.startswith("|---")]
    if len(rows) < 20:
        sys.exit(f"build.py: found only {len(rows)} Esper rows in docs/PLAYING.md")

    def short(cell):
        cell = re.sub(r"Raises ([\w. ]+?) by (\d[\d/]*)",
                      lambda m: m.group(1)[0].upper() + m.group(1)[1:] + " +" + m.group(2), cell)
        return html.escape(cell).replace(" +", "\u00a0+")

    def table(part):
        head = ('<table class="compact espers"><tr><th style="width:0.62in">Esper</th>'
                '<th style="width:0.72in">Spells</th><th>10</th><th>30</th><th>75</th>'
                '<th>200</th><th>500</th></tr>')
        body = []
        for r in part:
            cells = [c.strip() for c in r.strip().strip("|").split("|")]
            body.append("<tr><td class=\"k\">%s</td>%s</tr>" % (
                html.escape(cells[0]), "".join(f"<td>{short(c)}</td>" for c in cells[1:])))
        return head + "".join(body) + "</table>"
    half = (len(rows) + 1) // 2
    return table(rows[:half]), table(rows[half:])


def paginate(text):
    """Number the pages, mark odd/even, fill {{page:id}} references and the folio."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    pages = re.findall(r'<section class="page([^"]*)"', text)
    anchors = {}
    n = 0
    out = []
    pos = 0
    for m in re.finditer(r'<section class="page([^"]*)"([^>]*)>', text):
        n += 1
        classes = m.group(1)
        attrs = m.group(2)
        idm = re.search(r'id="([^"]+)"', attrs)
        if idm:
            anchors[idm.group(1)] = n
        side = "odd" if n % 2 else "even"
        out.append(text[pos:m.start()])
        out.append(f'<section class="page{classes} {side}" data-n="{n}"{attrs}>')
        pos = m.end()
    out.append(text[pos:])
    text = "".join(out)
    # also anchors on inner elements: <... data-anchor="x"> inside page n
    for page_m in re.finditer(r'<section class="page[^"]*" data-n="(\d+)"[^>]*>(.*?)</section>',
                              text, re.S):
        for a in re.findall(r'data-anchor="([^"]+)"', page_m.group(2)):
            anchors[a] = int(page_m.group(1))
    text = re.sub(r"\{\{page:([\w-]+)\}\}",
                  lambda m: str(anchors[m.group(1)]) if m.group(1) in anchors
                  else sys.exit(f"build.py: no page anchor '{m.group(1)}'"), text)
    # the folio: every numbered page carries <div class="folio"><span>N</span></div>
    text = re.sub(r'(<section class="page(?![^"]*\b(?:cover|back)\b)[^"]*" data-n="(\d+)"[^>]*>)',
                  lambda m: m.group(1) + f'<div class="folio"><span>{m.group(2)}</span></div>',
                  text)
    return text, len(pages)


def chrome(binary, *args):
    with tempfile.TemporaryDirectory() as prof:
        cmd = [binary, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
               "--allow-file-access-from-files", f"--user-data-dir={prof}",
               "--no-first-run", "--disable-extensions", "--run-all-compositor-stages-before-draw",
               "--virtual-time-budget=5000", *args]
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if r.returncode != 0:
            sys.exit(f"build.py: chromium failed ({r.returncode}):\n{r.stderr[-2000:]}")
        return r.stdout


def impose(text, npages):
    """The printer's version: each letter-size landscape sheet carries two pages, in
    saddle-stitch order, so the stack printed duplex (flip on the short edge), folded
    and stapled reads 1..n."""
    pages = re.findall(r'<section class="page.*?</section>', text, re.S)
    assert len(pages) == npages
    sheets = []
    for s in range(npages // 4):
        for left, right in ((npages - 2 * s, 2 * s + 1), (2 * s + 2, npages - 2 * s - 1)):
            sheets.append(f'<div class="sheet">{pages[left - 1]}{pages[right - 1]}</div>')
    head = text[:text.index("<body")]
    style = ("<style>@page { size: 11in 8.5in; margin: 0; }"
             " .sheet { display: flex; width: 11in; height: 8.5in; overflow: hidden;"
             " break-after: page; page-break-after: always; }"
             " .sheet:last-child { break-after: auto; page-break-after: auto; }"
             " .sheet .page { margin: 0; flex: none; break-after: auto; page-break-after: auto; }"
             "</style>")
    return head.replace("</head>", style + "</head>") + "<body>" + "".join(sheets) + "</body></html>"


def pdf_pages(path):
    return len(re.findall(rb"/Type\s*/Page\b", path.read_bytes()))


def main():
    ap = argparse.ArgumentParser(description="Build the OT6 instruction booklet PDF.")
    ap.add_argument("--version", help="the version the cover prints (default: VERSION)")
    ap.add_argument("--booklet", action="store_true",
                    help="also write the printer's version: two pages per letter sheet, "
                         "saddle-stitch order (ot6-manual-booklet.pdf beside the PDF)")
    ap.add_argument("--png", default="", help="comma-separated page numbers to render as PNG")
    ap.add_argument("--out", default=str(OUT / "ot6-manual.pdf"))
    ap.add_argument("--check", action="store_true",
                    help="check docs/manual's PDFs against today's inputs (no browser) and exit")
    a = ap.parse_args()
    if a.check:
        return check()
    a.booklet = a.booklet or (DOCS / "ot6-manual-booklet.pdf").exists()
    draft = bool(os.environ.get("OT6_MANUAL_DRAFT"))

    binary = find_chrome()
    site = OUT / "site"
    shutil.rmtree(site, ignore_errors=True)
    site.mkdir(parents=True)
    shutil.copytree(SRC / "fonts", site / "fonts")
    shutil.copyfile(SRC / "manual.css", site / "manual.css")
    scale_images(site / "img")

    text = (SRC / "manual.html").read_text()
    version = a.version or (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+", version):
        sys.exit(f"build.py: version '{version}' is not X.Y")
    text = text.replace("{{version}}", html.escape(version))
    e1, e2 = esper_tables()
    text = text.replace("<!--ESPERS1-->", e1).replace("<!--ESPERS2-->", e2)
    text, npages = paginate(text)
    paged = text
    checks = (SRC / "checks.js").read_text()
    text = text.replace("</body>", f"<script>\n{checks}</script>\n</body>")
    index = site / "index.html"
    index.write_text(text)
    url = index.resolve().as_uri()

    dom = chrome(binary, "--dump-dom", url)
    m = re.search(r'<body[^>]*data-layout="([^"]*)"', dom)
    if m is None:
        sys.exit("build.py: the layout check did not run (no data-layout on <body>)")
    problems = html.unescape(m.group(1))
    if problems:
        if not draft:
            sys.exit("build.py: layout fails (page: what):\n  " + problems.replace("; ", "\n  "))
        print("build.py: DRAFT: layout fails:\n  " + problems.replace("; ", "\n  "))
    if npages % 4:
        msg = (f"build.py: {npages} pages; a folded booklet needs a multiple of four "
               f"(add or remove a notes page)")
        if not draft:
            sys.exit(msg)
        print("DRAFT: " + msg)

    pdf = Path(a.out)
    pdf.parent.mkdir(parents=True, exist_ok=True)
    chrome(binary, "--no-pdf-header-footer", "--generate-pdf-document-outline",
           f"--print-to-pdf={pdf}", url)
    got = pdf_pages(pdf)
    if got != npages:
        sys.exit(f"build.py: the PDF has {got} pages, the source {npages}: a page broke in two")
    rel = lambda p: p.relative_to(ROOT) if p.is_relative_to(ROOT) else p
    print(f"build.py: {rel(pdf)}: {npages} pages, v{version}, {pdf.stat().st_size // 1024} KB "
          f"(chromium: {binary})")

    if a.booklet and npages % 4 == 0:
        bk = site / "booklet.html"
        bk.write_text(impose(paged, npages))
        bpdf = pdf.with_name(pdf.stem + "-booklet.pdf")
        chrome(binary, "--no-pdf-header-footer", f"--print-to-pdf={bpdf}", bk.resolve().as_uri())
        got = pdf_pages(bpdf)
        if got != npages // 2:
            sys.exit(f"build.py: the booklet PDF has {got} sheet sides, expected {npages // 2}")
        print(f"build.py: {rel(bpdf)}: {got} letter sheet sides, saddle-stitch order "
              f"(print duplex, flip on the short edge)")

    if not draft:
        DOCS.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pdf, DOCS / "ot6-manual.pdf")
        lines = ["# written by tools/manual/build.py; `build.py --check` compares it with the tree",
                 f"inputs {inputs_hash()[0]}", f"version {version}",
                 f"pdf {sha256(DOCS / 'ot6-manual.pdf')}"]
        if a.booklet:
            shutil.copyfile(bpdf, DOCS / "ot6-manual-booklet.pdf")
            lines.append(f"booklet {sha256(DOCS / 'ot6-manual-booklet.pdf')}")
        STAMP.write_text("\n".join(lines) + "\n")
        print("build.py: wrote docs/manual/ (commit it)")

    if a.png:
        pages_dir = OUT / "pages"
        pages_dir.mkdir(parents=True, exist_ok=True)
        for n in [int(x) for x in a.png.split(",") if x.strip()]:
            png = pages_dir / f"page-{n:02d}.png"
            chrome(binary, f"--window-size={PAGE_PX[0]},{PAGE_PX[1]}",
                   "--force-device-scale-factor=2", f"--screenshot={png}", f"{url}#only={n}")
            print(f"build.py: {rel(png)}")


if __name__ == "__main__":
    main()

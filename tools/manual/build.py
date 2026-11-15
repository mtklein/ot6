#!/usr/bin/env python3
"""Build the OT6 instruction booklet: build/manual/ot6-manual.pdf.

    python3 tools/manual/build.py                 # the PDF
    python3 tools/manual/build.py --png 1,5,9     # and PNG renders of those pages
                                                  #   (build/manual/pages/page-NN.png)

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


OVERFLOW_JS = """
<script>
window.addEventListener('load', () => {
  const bad = [];
  document.querySelectorAll('.page').forEach(p => {
    const b = p.querySelector('.body') || p;
    const kids = b.querySelectorAll('*');
    let over = b.scrollHeight > b.clientHeight + 1 || b.scrollWidth > b.clientWidth + 1;
    if (over) bad.push(p.dataset.n);
  });
  document.body.setAttribute('data-overflow', bad.join(','));
  const m = location.hash.match(/^#only=(\\d+)$/);
  if (m) {
    document.body.classList.add('only');
    document.querySelectorAll('.page').forEach(p => {
      if (p.dataset.n === m[1]) p.classList.add('shown');
    });
  }
});
</script>
"""


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


def main():
    ap = argparse.ArgumentParser(description="Build the OT6 instruction booklet PDF.")
    ap.add_argument("--png", default="", help="comma-separated page numbers to render as PNG")
    ap.add_argument("--out", default=str(OUT / "ot6-manual.pdf"))
    a = ap.parse_args()

    binary = find_chrome()
    site = OUT / "site"
    shutil.rmtree(site, ignore_errors=True)
    site.mkdir(parents=True)
    shutil.copytree(SRC / "fonts", site / "fonts")
    shutil.copyfile(SRC / "manual.css", site / "manual.css")
    scale_images(site / "img")

    text = (SRC / "manual.html").read_text()
    version = (ROOT / "VERSION").read_text().strip()
    text = text.replace("{{version}}", html.escape(version))
    e1, e2 = esper_tables()
    text = text.replace("<!--ESPERS1-->", e1).replace("<!--ESPERS2-->", e2)
    text, npages = paginate(text)
    text = text.replace("</body>", OVERFLOW_JS + "</body>")
    index = site / "index.html"
    index.write_text(text)
    url = index.resolve().as_uri()

    dom = chrome(binary, "--dump-dom", url)
    m = re.search(r'<body[^>]*data-overflow="([^"]*)"', dom)
    if m is None:
        sys.exit("build.py: the overflow check did not run (no data-overflow on <body>)")
    if m.group(1) and os.environ.get("OT6_MANUAL_DRAFT"):
        print(f"build.py: DRAFT: content overflows page(s) {m.group(1)}")
    elif m.group(1):
        sys.exit(f"build.py: content overflows page(s) {m.group(1)}; shorten or split them")
    if npages % 4 and not os.environ.get("OT6_MANUAL_DRAFT"):
        sys.exit(f"build.py: {npages} pages; a folded booklet needs a multiple of four "
                 f"(add or remove a notes page)")

    pdf = Path(a.out)
    pdf.parent.mkdir(parents=True, exist_ok=True)
    chrome(binary, "--no-pdf-header-footer", "--generate-pdf-document-outline",
           f"--print-to-pdf={pdf}", url)
    data = pdf.read_bytes()
    got = len(re.findall(rb"/Type\s*/Page\b", data))
    if got != npages:
        sys.exit(f"build.py: the PDF has {got} pages, the source {npages}: a page broke in two")
    print(f"build.py: {pdf.relative_to(ROOT) if pdf.is_relative_to(ROOT) else pdf}: "
          f"{npages} pages, {len(data) // 1024} KB (chromium: {binary})")

    if a.png:
        pages_dir = OUT / "pages"
        pages_dir.mkdir(parents=True, exist_ok=True)
        for n in [int(x) for x in a.png.split(",") if x.strip()]:
            png = pages_dir / f"page-{n:02d}.png"
            chrome(binary, f"--window-size={PAGE_PX[0]},{PAGE_PX[1]}",
                   "--force-device-scale-factor=2", f"--screenshot={png}", f"{url}#only={n}")
            print(f"build.py: {png.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

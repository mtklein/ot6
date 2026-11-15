// The layout checks build.py reads back from the DOM (<body data-layout="...">):
//   * a page whose text area runs off the bottom;
//   * any run of text that crosses the left or right edge of the box that
//     clips it: the page's text area (.body), or, for the running head, the
//     folio and the covers, the page itself.  An italic or bold glyph can
//     overhang its advance, so text must stay a pixel inside the edge.
// With #only=N in the URL the page shows page N alone (the PNG renders).
window.addEventListener('load', () => {
  const bad = [];
  document.querySelectorAll('.page').forEach(p => {
    const b = p.querySelector('.body') || p;
    if (b.scrollHeight > b.clientHeight + 1) bad.push(p.dataset.n + ': runs off the bottom');
    const boxes = b === p ? [p] : [b, p];
    for (const box of boxes) {
      const r = box.getBoundingClientRect();
      const walk = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
      for (let t = walk.nextNode(); t; t = walk.nextNode()) {
        if (!t.textContent.trim()) continue;
        if (box === p && b !== p && b.contains(t)) continue;
        // an italic glyph's ink runs past its advance on the right (the
        // "dagger" whose r was cut at the margin): allow a quarter em for it
        const cs = getComputedStyle(t.parentElement);
        const overhang = cs.fontStyle === 'italic' ? 0.25 * parseFloat(cs.fontSize) : 0;
        const range = document.createRange();
        range.selectNodeContents(t);
        for (const q of range.getClientRects()) {
          if (q.width === 0) continue;
          if (q.right + overhang > r.right + 0.25 || q.left < r.left - 0.25) {
            bad.push(p.dataset.n + ': clipped "' + t.textContent.trim().slice(0, 40) + '"');
            break;
          }
        }
      }
    }
  });
  document.body.setAttribute('data-layout', bad.join('; '));
  const m = location.hash.match(/^#only=(\d+)$/);
  if (m) {
    document.body.classList.add('only');
    document.querySelectorAll('.page').forEach(p => {
      if (p.dataset.n === m[1]) p.classList.add('shown');
    });
  }
});

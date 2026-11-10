(() => {
  const input = CAPTURE_INPUT;
  const browserWindow = window;
  const normalize = (value, base = browserWindow.location.href) => {
    try {
      const u = new URL(value, base);
      const note = u.pathname.match(/^\/(?:explore|search_result)\/([a-f0-9]{24})\/?$/i) || u.pathname.match(/^\/discovery\/item\/([a-f0-9]{24})\/?$/i);
      if (/^(?:www\.|m\.)?xiaohongshu\.com$/i.test(u.hostname) && note) return 'https://www.xiaohongshu.com/explore/' + note[1].toLowerCase();
      for (const key of Array.from(u.searchParams.keys())) if (/^(utm_|xsec_)/i.test(key) || ['spm','from','share_source'].includes(key)) u.searchParams.delete(key);
      u.searchParams.sort();
      return u.origin + decodeURIComponent(u.pathname).replace(/\/$/, '') + (u.searchParams.size ? '?' + u.searchParams.toString() : '');
    }
    catch { return ''; }
  };
  const target = normalize(input.url);
  const topURL = browserWindow.location.href;
  // Search can host a note in a same-origin iframe. Inspect frame URLs first;
  // only the document whose URL matches the collected note may supply its body.
  let frameUnavailable = false;
  const locate = (w, offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1, depth = 0) => {
    if (depth > 3) return null;
    let d, href;
    try { d = w.document; href = w.location.href; } catch { return null; }
    const candidate = target && normalize(href) === target ? {win:w, doc:d, href, offsetX, offsetY, scaleX, scaleY} : null;
    if (candidate && Array.from(d.querySelectorAll('#detail-desc, [itemprop="articleBody"], .article-content, .post-content, .entry-content')).some(el => {const r=el.getBoundingClientRect();return r.width>8&&r.height>8;})) return candidate;
    for (const frame of Array.from(d.querySelectorAll('iframe')).slice(0, 16)) {
      const r = frame.getBoundingClientRect();
      if (r.width <= 8 || r.height <= 8 || r.bottom <= 0 || r.right <= 0 || r.top >= w.innerHeight || r.left >= w.innerWidth) continue;
      const declaredMatch = target && normalize(frame.src, href) === target;
      try {
        const child = frame.contentWindow;
        if (!child?.document) { if (declaredMatch) frameUnavailable = true; continue; }
        const sx = r.width / (frame.offsetWidth || r.width), sy = r.height / (frame.offsetHeight || r.height);
        const result = locate(child, offsetX + (r.left + frame.clientLeft * sx) * scaleX, offsetY + (r.top + frame.clientTop * sy) * scaleY, scaleX * sx, scaleY * sy, depth + 1);
        if (result) return result;
        if (declaredMatch && child.location.href === 'about:blank') frameUnavailable = true;
      } catch { if (declaredMatch) frameUnavailable = true; }
    }
    return candidate;
  };
  const located = locate(browserWindow);
  const source = located || {win:browserWindow, doc:browserWindow.document, href:topURL, offsetX:0, offsetY:0, scaleX:1, scaleY:1};
  const doc = source.doc, pageWindow = source.win;
  const pageMatches = !!located;
  const visible = el => {
    const r = el.getBoundingClientRect();
    return r.width > 8 && r.height > 8 && r.bottom > 0 && r.right > 0 && r.top < pageWindow.innerHeight && r.left < pageWindow.innerWidth;
  };
  const matches = el => el && target && [el.href, el.currentSrc, el.src].some(v => v && normalize(v) === target);
  const zoom = browserWindow.outerWidth && browserWindow.innerWidth ? browserWindow.outerWidth / browserWindow.innerWidth : 1;
  const topInset = browserWindow.outerHeight - browserWindow.innerHeight * zoom;
  const point = doc.elementFromPoint(((input.x - browserWindow.screenX) / zoom - source.offsetX) / source.scaleX, ((input.y - browserWindow.screenY - topInset) / zoom - source.offsetY) / source.scaleY);
  let selected = [point, point?.closest('a'), point?.closest('img')].find(matches);
  if (!selected && pageMatches && point?.tagName === 'IMG') selected = point;
  if (!selected && !pageMatches) {
    selected = Array.from(doc.querySelectorAll('a[href],img[src]')).find(el => visible(el) && matches(el));
  }
  if (!pageMatches && !selected) return JSON.stringify({matched: false, frameUnavailable});
  const container = selected?.closest('.note-item, article, [role="listitem"], .feed-item') || selected;
  const text = el => (el?.innerText || el?.textContent || '').trim().replace(/\s+/g, ' ');
  // Read only the matched note/article, never the whole feed, comments or sidebars.
  const candidates = Array.from(doc.querySelectorAll('#noteContainer, .note-detail-mask, article, main'));
  const detailRoot = pageMatches ? candidates.find(el => visible(el) && el.querySelector('#detail-desc, [itemprop="articleBody"], .article-content, .post-content, .entry-content')) ||
    candidates.find(el => el.querySelector('#detail-desc, [itemprop="articleBody"], .article-content, .post-content, .entry-content')) : null;
  const scope = pageMatches ? detailRoot || doc : container;
  const bodySelectors = '#detail-desc, [itemprop="articleBody"], [data-testid="note-content"], .note-content .desc, .note-text, .article-content, .post-content, .entry-content';
  let bodyNode = scope?.querySelector(pageMatches && !detailRoot ? '#detail-desc, [itemprop="articleBody"], [data-testid="note-content"]' : bodySelectors);
  let bodySource = pageMatches ? 'browser_note_body' : 'browser_card_excerpt';
  if (!bodyNode && !pageMatches) bodyNode = scope?.querySelector('.desc, .description, .summary, .excerpt');
  if (!bodyNode && pageMatches) {
    const article = scope?.matches?.('article') ? scope : scope?.querySelector('article');
    if (article) bodyNode = article;
  }
  let bodyText = '';
  let bodyPartial = !pageMatches;
  if (bodyNode) {
    const clone = bodyNode.cloneNode(true);
    clone.querySelectorAll('script, style, nav, aside, footer, button, .comments, #comments, .comments-container, .comment-container, .comment-list, .recommend, [role="complementary"]').forEach(el => el.remove());
    // Preserve paragraph boundaries without depending on a detached element's innerText.
    clone.querySelectorAll('br').forEach(el => el.replaceWith('\n'));
    clone.querySelectorAll('p, div, li, section').forEach(el => el.append('\n'));
    bodyText = (clone.textContent || '').replace(/\r\n?/g, '\n').replace(/\u00a0/g, ' ').split('\n').map(line => line.trim()).join('\n').replace(/\n{3,}/g, '\n\n').trim();
    bodyPartial ||= /[.…]{2,}\s*(展开|更多|阅读全文)?$/.test(bodyText) || /展开|阅读全文/.test(text(bodyNode.querySelector('.expand, .read-more, .show-more')));
  }
  if (!bodyText && pageMatches) {
    bodyText = doc.querySelector('meta[name="description"], meta[property="og:description"]')?.content?.trim() || '';
    if (bodyText) { bodySource = 'browser_page_summary'; bodyPartial = true; }
  }
  let title = pageMatches
    ? text(scope?.querySelector('#detail-title, h1')) || doc.title
    : text(container?.querySelector('.title, [data-testid="title"], h1, h2, h3')) || selected?.getAttribute('title') || selected?.getAttribute('aria-label') || text(container);
  let image = selected?.tagName === 'IMG' ? selected : container?.querySelector('img');
  if (!image && pageMatches) {
    const og = doc.querySelector('meta[property="og:image"]')?.content;
    const images = Array.from(doc.images).filter(el => visible(el) && el.naturalWidth >= 64);
    image = images.find(el => og && normalize(el.currentSrc || el.src) === normalize(og)) ||
      images.filter(el => el.closest('#noteContainer, .note-detail-mask, article, main')).sort((a,b) => b.getBoundingClientRect().width * b.getBoundingClientRect().height - a.getBoundingClientRect().width * a.getBoundingClientRect().height)[0];
  }
  if (image && !title) title = image.alt || '';
  const result = {matched: true, title: Array.from(String(title || '')).slice(0, 500).join(''), pageURL: topURL, contentURL: source.href, inFrame: pageWindow !== browserWindow};
  if (bodyText) { const characters = Array.from(bodyText); result.text = characters.slice(0, 24000).join(''); result.textSource = bodySource; result.textTruncated = bodyPartial || characters.length > 24000; }
  result.sourceURL = selected?.closest('a[href]')?.href || (pageMatches ? source.href : input.url);
  if (image) result.imageURL = image.currentSrc || image.src;
  if (image && visible(image)) {
    const r = image.getBoundingClientRect();
    const left = Math.max(0, r.left), top = Math.max(0, r.top);
    result.rect = {x: browserWindow.screenX + (source.offsetX + left * source.scaleX) * zoom, y: browserWindow.screenY + topInset + (source.offsetY + top * source.scaleY) * zoom, width: Math.max(0, Math.min(pageWindow.innerWidth, r.right) - left) * source.scaleX * zoom, height: Math.max(0, Math.min(pageWindow.innerHeight, r.bottom) - top) * source.scaleY * zoom};
    try {
      const canvas = document.createElement('canvas');
      const scale = Math.min(1, 512 / Math.max(image.naturalWidth, image.naturalHeight));
      canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
      canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
      canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
      result.imageData = canvas.toDataURL('image/png');
    } catch { /* Cross-origin images are captured from their rendered window rectangle. */ }
  }
  return JSON.stringify(result);
})();

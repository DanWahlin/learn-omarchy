(function () {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- Nav ---------- */

  const toggle = document.querySelector('.nav-toggle');
  const links = document.querySelector('.nav-links');
  if (toggle && links) {
    toggle.addEventListener('click', function () {
      const isOpen = toggle.getAttribute('aria-expanded') === 'true';
      toggle.setAttribute('aria-expanded', String(!isOpen));
      links.classList.toggle('open', !isOpen);
    });
    links.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        toggle.setAttribute('aria-expanded', 'false');
        links.classList.remove('open');
      });
    });
  }

  const navItems = document.querySelectorAll('.nav-links a[href^="#"]');
  const sections = document.querySelectorAll('main section[id]');
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navItems.forEach(function (item) {
          item.classList.toggle('active', item.getAttribute('href') === '#' + entry.target.id);
        });
      });
    }, { rootMargin: '-35% 0px -55%' });
    sections.forEach(function (section) { observer.observe(section); });
  }

  const year = document.getElementById('year');
  if (year) year.textContent = String(new Date().getFullYear());

  document.querySelectorAll('.copy[data-copy]').forEach(function (button) {
    button.addEventListener('click', function () {
      const text = button.getAttribute('data-copy');
      if (!navigator.clipboard || !text) return;
      navigator.clipboard.writeText(text).then(function () {
        button.textContent = 'Copied';
        button.classList.add('done');
        setTimeout(function () { button.textContent = 'Copy'; button.classList.remove('done'); }, 1600);
      });
    });
  });


  /* ---------- Themes: palettes copied from Omarchy's bundled colors.toml files ---------- */

  const THEMES = {
    'catppuccin':  { name: 'Catppuccin',   bg: '#1e1e2e', fg: '#cdd6f4', accent: '#cba6f7', red: '#f38ba8', yellow: '#f9e2af', orange: '#fab387', green: '#a6e3a1', cyan: '#94e2d5', blue: '#89b4fa', magenta: '#f5c2e7' },
    'tokyo-night': { name: 'Tokyo Night',  bg: '#1a1b26', fg: '#a9b1d6', accent: '#7aa2f7', red: '#f7768e', yellow: '#e0af68', orange: '#eb927b', green: '#9ece6a', cyan: '#7dcfff', blue: '#7aa2f7', magenta: '#bb9af7' },
    'ethereal':    { name: 'Ethereal',     bg: '#060b1e', fg: '#ffcead', accent: '#7d82d9', red: '#ed5b5a', yellow: '#e9bb4f', orange: '#eb8b54', green: '#92a593', cyan: '#a3bfd1', blue: '#7d82d9', magenta: '#c89dc1' },
    'retro-82':    { name: 'Retro 82',     bg: '#05182e', fg: '#f6dcac', accent: '#faa968', red: '#f85525', yellow: '#e97b3c', orange: '#faa968', green: '#3f8f8a', cyan: '#8cbfb8', blue: '#3f8f8a', magenta: '#faa968' },
    'rose-pine':   { name: 'Rosé Pine',    bg: '#191724', fg: '#e0def4', accent: '#c4a7e7', red: '#eb6f92', yellow: '#f6c177', orange: '#ea9a97', green: '#9ccfd8', cyan: '#9ccfd8', blue: '#31748f', magenta: '#ebbcba' },
    'everforest':  { name: 'Everforest',   bg: '#2d353b', fg: '#d3c6aa', accent: '#7fbbb3', red: '#e67e80', yellow: '#dbbc7f', orange: '#e09d7f', green: '#a7c080', cyan: '#83c092', blue: '#7fbbb3', magenta: '#d699b6' },
    'gruvbox':     { name: 'Gruvbox',      bg: '#282828', fg: '#d4be98', accent: '#7daea3', red: '#ea6962', yellow: '#d8a657', orange: '#e1875c', green: '#a9b665', cyan: '#89b482', blue: '#7daea3', magenta: '#d3869b' },
    'kanagawa':    { name: 'Kanagawa',     bg: '#1f1f28', fg: '#dcd7ba', accent: '#7e9cd8', red: '#c34043', yellow: '#c0a36e', orange: '#c17158', green: '#76946a', cyan: '#6a9589', blue: '#7e9cd8', magenta: '#957fb8' },
    'nord':        { name: 'Nord',         bg: '#2e3440', fg: '#d8dee9', accent: '#81a1c1', red: '#bf616a', yellow: '#ebcb8b', orange: '#d5967a', green: '#a3be8c', cyan: '#88c0d0', blue: '#81a1c1', magenta: '#b48ead' },
    'osaka-jade':  { name: 'Osaka Jade',   bg: '#111c18', fg: '#c1c497', accent: '#2dd5b7', red: '#ff5345', yellow: '#e6c384', orange: '#a2734b', green: '#549e6a', cyan: '#2dd5b7', blue: '#509475', magenta: '#d2689c' },
    'ristretto':   { name: 'Ristretto',    bg: '#2c2525', fg: '#e6d9db', accent: '#f38d70', red: '#fd6883', yellow: '#f9cc6c', orange: '#fb9a77', green: '#adda78', cyan: '#85dacc', blue: '#a8a9eb', magenta: '#a8a9eb' },
    'matte-black': { name: 'Matte Black',  bg: '#121212', fg: '#bebebe', accent: '#e68e0d', red: '#d35f5f', yellow: '#ffc107', orange: '#e68e0d', green: '#8bc34a', cyan: '#bebebe', blue: '#e68e0d', magenta: '#d35f5f' },
    'hackerman':   { name: 'Hackerman',    bg: '#0b0c16', fg: '#ddf7ff', accent: '#82fb9c', red: '#50f872', yellow: '#50f7d4', orange: '#50f7a3', green: '#4fe88f', cyan: '#7cf8f7', blue: '#829dd4', magenta: '#86a7df' },
    'lumon':       { name: 'Lumon',        bg: '#16242d', fg: '#d6e2ee', accent: '#8bc9eb', red: '#4d86b0', yellow: '#6fa4c9', orange: '#8bc9eb', green: '#5e95bc', cyan: '#b4e4f6', blue: '#6fb8e3', magenta: '#8bc9eb' }
  };
  const THEME_IDS = Object.keys(THEMES);
  const DEFAULT_THEME = 'ethereal';

  function hexToRgb(h) { h = h.replace('#', ''); return [0, 2, 4].map(function (i) { return parseInt(h.slice(i, i + 2), 16); }); }
  function rgbToHex(c) { return '#' + c.map(function (v) { return Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0'); }).join(''); }
  function mix(a, b, t) { const A = hexToRgb(a), B = hexToRgb(b); return rgbToHex(A.map(function (v, i) { return v + (B[i] - v) * t; })); }
  function rgbList(h) { return hexToRgb(h).join(', '); }
  function luma(h) { const c = hexToRgb(h); return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; }
  function relativeLuminance(h) {
    const channels = hexToRgb(h).map(function (value) {
      const channel = value / 255;
      return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  }
  function contrastRatio(a, b) {
    const lighter = Math.max(relativeLuminance(a), relativeLuminance(b));
    const darker = Math.min(relativeLuminance(a), relativeLuminance(b));
    return (lighter + 0.05) / (darker + 0.05);
  }
  function accessibleTextMix(fg, bg, preferredMix, backgrounds, minimumContrast) {
    let low = 0;
    let high = preferredMix;
    let best = fg;
    for (let i = 0; i < 12; i += 1) {
      const amount = (low + high) / 2;
      const candidate = mix(fg, bg, amount);
      if (backgrounds.every(function (background) { return contrastRatio(candidate, background) >= minimumContrast; })) {
        best = candidate;
        low = amount;
      } else {
        high = amount;
      }
    }
    return best;
  }

  function vividWordmarkColor(hex) {
    const rgb = hexToRgb(hex).map(function (value) { return value / 255; });
    const high = Math.max.apply(null, rgb), low = Math.min.apply(null, rgb);
    const delta = high - low;
    if (!delta) return mix(hex, '#ffffff', 0.4);
    const originalLightness = (high + low) / 2;
    const hue = ((high === rgb[0] ? (rgb[1] - rgb[2]) / delta
      : high === rgb[1] ? (rgb[2] - rgb[0]) / delta + 2
      : (rgb[0] - rgb[1]) / delta + 4) + 6) % 6;
    const saturation = Math.min(0.95, delta / (1 - Math.abs(2 * originalLightness - 1)) * 1.7 + 0.15);
    const lightness = Math.max(0.67, Math.min(0.74, originalLightness));
    const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
    const x = chroma * (1 - Math.abs(hue % 2 - 1));
    const channels = [[chroma, x, 0], [x, chroma, 0], [0, chroma, x],
      [0, x, chroma], [x, 0, chroma], [chroma, 0, x]][Math.floor(hue)];
    return rgbToHex(channels.map(function (value) { return (value + lightness - chroma / 2) * 255; }));
  }

  function tokensFor(t) {
    const bg = t.bg;
    const white = '#ffffff';
    const bgDeep = mix(bg, '#000000', 0.18);
    const crust = mix(bg, '#000000', 0.32);
    const surface = mix(bg, white, 0.03);
    const surface2 = mix(bg, white, 0.09);
    const textBackgrounds = [bg, bgDeep, crust, surface, surface2];
    // Some palettes reuse one color for several slots; keep magenta and cyan distinct from the accent
    const pink = t.magenta.toLowerCase() === t.accent.toLowerCase() ? t.orange : t.magenta;
    const cyan = t.cyan.toLowerCase() === t.fg.toLowerCase() ? t.blue : t.cyan;
    const sky = mix(cyan, white, 0.25);
    const wordmarkPink = vividWordmarkColor(pink);
    const wordmarkColors = [
      mix(t.fg, white, 0.92),
      mix(wordmarkPink, white, 0.65),
      wordmarkPink,
      vividWordmarkColor(mix(pink, t.accent, 0.6)),
      vividWordmarkColor(cyan)
    ].map(function (color) {
      return accessibleTextMix(white, color, 1, [bg, bgDeep], 5.5);
    });
    return {
      '--wordmark-top': wordmarkColors[0],
      '--wordmark-blush': wordmarkColors[1],
      '--wordmark-pink': wordmarkColors[2],
      '--wordmark-violet': wordmarkColors[3],
      '--wordmark-cyan': wordmarkColors[4],
      '--bg': bg,
      '--bg-deep': bgDeep,
      '--crust': crust,
      '--surface': surface,
      '--surface-2': surface2,
      '--line': mix(bg, white, 0.1),
      '--line-2': mix(bg, white, 0.2),
      '--ink': mix(t.fg, white, 0.6),
      '--ink-2': t.fg,
      '--muted': accessibleTextMix(t.fg, bg, 0.35, textBackgrounds, 5.5),
      '--dim': accessibleTextMix(t.fg, bg, 0.52, textBackgrounds, 4.5),
      '--white': white,
      '--brand': t.accent,
      '--pink': pink,
      '--cyan': cyan,
      '--sky': sky,
      '--blue': t.blue,
      '--orange': t.orange,
      '--green': t.green,
      '--magenta': t.magenta,
      '--red': t.red,
      '--yellow': t.yellow,
      '--lavender': mix(t.accent, white, 0.3),
      '--brand-ink': luma(t.accent) > 0.5 ? mix(bg, '#000000', 0.32) : white,
      '--bg-rgb': rgbList(bg),
      '--bg-deep-rgb': rgbList(bgDeep),
      '--crust-rgb': rgbList(crust),
      '--brand-rgb': rgbList(t.accent),
      '--pink-rgb': rgbList(pink),
      '--cyan-rgb': rgbList(cyan),
      '--sky-rgb': rgbList(sky),
      '--red-rgb': rgbList(t.red)
    };
  }

  let currentTheme = DEFAULT_THEME;
  const rainPalette = { colors: [] };

  function applyTheme(id, animate) {
    const t = THEMES[id] || THEMES[DEFAULT_THEME];
    const tokens = tokensFor(t);
    const root = document.documentElement;
    if (animate) { root.classList.add('theming'); setTimeout(function () { root.classList.remove('theming'); }, 400); }
    Object.keys(tokens).forEach(function (k) { root.style.setProperty(k, tokens[k]); });
    root.dataset.theme = id;
    currentTheme = id;
    rainPalette.colors = [t.accent, t.magenta, t.cyan, t.blue, t.orange, tokens['--line-2']];
    document.querySelectorAll('#desktop .theme-line').forEach(function (n) { n.textContent = t.name; });
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', tokens['--bg-deep']);
    try { localStorage.setItem('learn-omarchy-theme', id); } catch (e) { /* private mode */ }
  }

  function randomTheme() {
    const pool = THEME_IDS.filter(function (id) { return id !== currentTheme; });
    return pool[Math.floor(Math.random() * pool.length)];
  }

  (function initThemes() {
    const params = new URLSearchParams(location.search);
    let id = params.get('theme');
    if (id === 'random') id = randomTheme();
    if (!id || !THEMES[id]) { try { id = localStorage.getItem('learn-omarchy-theme'); } catch (e) { id = null; } }
    if (!id || !THEMES[id]) id = DEFAULT_THEME;
    applyTheme(id, false);

    const overlay = document.getElementById('theme-panel');
    const stage = document.getElementById('theme-list');
    const nameEl = document.getElementById('theme-name');
    const toggleBtn = document.getElementById('theme-toggle');
    const closeBtn = document.getElementById('theme-close');
    if (!overlay || !stage) return;

    // Each card is a miniature of the demo desktop, recolored with that theme's tokens
    const template = document.getElementById('desktop');
    const cards = [];
    THEME_IDS.forEach(function (tid, i) {
      const t = THEMES[tid];
      const card = document.createElement('button');
      card.type = 'button'; card.className = 'theme-card'; card.dataset.theme = tid; card.dataset.index = String(i);
      card.setAttribute('aria-label', t.name);
      const tokens = tokensFor(t);
      Object.keys(tokens).forEach(function (k) { card.style.setProperty(k, tokens[k]); });
      if (template) {
        const mini = document.createElement('div');
        mini.className = 'desktop mini';
        mini.setAttribute('aria-hidden', 'true');
        const bar = template.querySelector('.bar');
        const scene = template.querySelector('#scene-1');
        [bar, scene].forEach(function (el) {
          if (!el) return;
          const clone = el.cloneNode(true);
          clone.removeAttribute('id');
          clone.classList.remove('hidden', 'fade');
          clone.querySelectorAll('[id]').forEach(function (n) { n.removeAttribute('id'); });
          mini.appendChild(clone);
        });
        mini.querySelectorAll('.theme-line').forEach(function (n) { n.textContent = t.name; });
        card.appendChild(mini);
      }
      card.addEventListener('click', function () {
        if (selected === i) { commit(); } else { select(i, true); }
      });
      stage.appendChild(card);
      cards.push(card);
    });

    let selected = THEME_IDS.indexOf(currentTheme);
    let committed = currentTheme;
    let open = false;
    let previousFocus = null;
    const backgroundElements = Array.from(document.body.children).filter(function (element) {
      return element !== overlay && element.tagName !== 'SCRIPT';
    });
    const initialInertStates = backgroundElements.map(function (element) { return element.inert; });

    function layout() {
      const n = cards.length;
      cards.forEach(function (card, i) {
        let d = i - selected;
        if (d > n / 2) d -= n; if (d < -n / 2) d += n;
        const ad = Math.abs(d);
        card.classList.toggle('active', d === 0);
        card.classList.toggle('near', ad === 1);
        card.classList.toggle('far', ad === 2);
        card.classList.toggle('hiddenfar', ad > 2);
        card.tabIndex = d === 0 ? 0 : -1;
        card.setAttribute('aria-hidden', String(ad > 2));
        const x = d * 46;
        const scale = d === 0 ? 1 : ad === 1 ? 0.78 : 0.62;
        const rot = d === 0 ? 0 : d < 0 ? 22 : -22;
        card.style.transform = 'translate(-50%, -50%) translateX(' + x + '%) scale(' + scale + ') rotateY(' + rot + 'deg)';
      });
      nameEl.textContent = THEMES[THEME_IDS[selected]].name;
    }

    function select(i, preview) {
      selected = (i + cards.length) % cards.length;
      layout();
      if (open) cards[selected].focus();
      if (preview) applyTheme(THEME_IDS[selected], true);
    }
    function commit() { committed = THEME_IDS[selected]; applyTheme(committed, true); openPicker(false); }
    function cancel() { if (currentTheme !== committed) applyTheme(committed, true); openPicker(false); }

    function openPicker(show) {
      open = show;
      if (show) previousFocus = document.activeElement;
      overlay.hidden = !show;
      toggleBtn.setAttribute('aria-expanded', String(show));
      document.body.style.overflow = show ? 'hidden' : '';
      backgroundElements.forEach(function (element, index) {
        element.inert = show || initialInertStates[index];
      });
      if (show) { committed = currentTheme; selected = THEME_IDS.indexOf(currentTheme); layout(); cards[selected].focus(); }
      else {
        const focusTarget = previousFocus && previousFocus !== document.body && previousFocus.isConnected ? previousFocus : toggleBtn;
        focusTarget.focus();
        previousFocus = null;
      }
    }

    toggleBtn.addEventListener('click', function () { openPicker(!open); });
    closeBtn.addEventListener('click', cancel);
    overlay.addEventListener('click', function (e) { if (e.target === overlay) cancel(); });
    document.addEventListener('keydown', function (e) {
      const typing = /^(input|textarea|select)$/i.test(e.target.tagName) || e.target.isContentEditable;
      if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
      if (!open) {
        return;
      }
      if (e.key === 'Tab') {
        const focusable = [closeBtn, cards[selected]];
        const current = focusable.indexOf(document.activeElement);
        const next = e.shiftKey
          ? (current <= 0 ? focusable.length - 1 : current - 1)
          : (current === focusable.length - 1 ? 0 : current + 1);
        e.preventDefault();
        focusable[next].focus();
      }
      else if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === 'l' || e.key === 'j') { e.preventDefault(); select(selected + 1, true); }
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp' || e.key === 'h' || e.key === 'k') { e.preventDefault(); select(selected - 1, true); }
      else if ((e.key === 'Enter' || e.key === ' ') && cards.includes(document.activeElement)) { e.preventDefault(); commit(); }
      else if (e.key === 'Escape') { e.preventDefault(); cancel(); }
    });
    window.addEventListener('resize', function () { if (open) layout(); });
    if (params.get('picker') === '1') openPicker(true);

  })();

  /* ---------- Shared 5x7 glyphs: crisp SVG hero and compact text previews ---------- */

  const FONT = {
    A: ['.███.', '█...█', '█...█', '█████', '█...█', '█...█', '█...█'],
    B: ['████.', '█...█', '█...█', '████.', '█...█', '█...█', '████.'],
    C: ['.████', '█....', '█....', '█....', '█....', '█....', '.████'],
    D: ['████.', '█...█', '█...█', '█...█', '█...█', '█...█', '████.'],
    E: ['█████', '█....', '█....', '████.', '█....', '█....', '█████'],
    G: ['.████', '█....', '█....', '█.███', '█...█', '█...█', '.████'],
    H: ['█...█', '█...█', '█...█', '█████', '█...█', '█...█', '█...█'],
    I: ['█████', '..█..', '..█..', '..█..', '..█..', '..█..', '█████'],
    L: ['█....', '█....', '█....', '█....', '█....', '█....', '█████'],
    M: ['█...█', '██.██', '█.█.█', '█...█', '█...█', '█...█', '█...█'],
    N: ['█...█', '██..█', '█.█.█', '█..██', '█...█', '█...█', '█...█'],
    O: ['.███.', '█...█', '█...█', '█...█', '█...█', '█...█', '.███.'],
    R: ['████.', '█...█', '█...█', '████.', '█.█..', '█..█.', '█...█'],
    Y: ['█...█', '█...█', '.█.█.', '..█..', '..█..', '..█..', '..█..'],
    ' ': ['...', '...', '...', '...', '...', '...', '...']
  };

  function pixelWordmark(text) {
    let cursor = 0;
    const pixels = [];
    for (const character of text.toUpperCase()) {
      const glyph = FONT[character] || FONT[' '];
      glyph.forEach(function (row, y) {
        for (let x = 0; x < row.length; x++) {
          if (row[x] !== '.') pixels.push('M' + (cursor + x + 0.04) + ' ' + (y + 0.04) + 'h.92v.92h-.92z');
        }
      });
      cursor += glyph[0].length + 1;
    }
    return { width: Math.max(1, cursor - 1), height: 7, path: pixels.join('') };
  }

  document.querySelectorAll('[data-pixel-text]').forEach(function (el, index) {
    const text = el.getAttribute('data-pixel-text').toUpperCase();
    if (el.classList.contains('wordmark')) {
      const geometry = pixelWordmark(text);
      const namespace = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(namespace, 'svg');
      svg.setAttribute('viewBox', '0 0 ' + geometry.width + ' ' + geometry.height);
      svg.setAttribute('width', geometry.width);
      svg.setAttribute('height', geometry.height);
      svg.setAttribute('aria-hidden', 'true');
      svg.setAttribute('focusable', 'false');
      const defs = document.createElementNS(namespace, 'defs');
      const gradient = document.createElementNS(namespace, 'linearGradient');
      const gradientId = 'wordmark-gradient-' + index;
      gradient.setAttribute('id', gradientId);
      gradient.setAttribute('x1', '0%');
      gradient.setAttribute('y1', '0%');
      gradient.setAttribute('x2', '0%');
      gradient.setAttribute('y2', '100%');
      ['top', 'blush', 'pink', 'violet', 'cyan'].forEach(function (name, stopIndex) {
        const stop = document.createElementNS(namespace, 'stop');
        stop.setAttribute('offset', [0, 28, 56, 78, 100][stopIndex] + '%');
        stop.style.stopColor = 'var(--wordmark-' + name + ')';
        gradient.appendChild(stop);
      });
      defs.appendChild(gradient);
      const path = document.createElementNS(namespace, 'path');
      path.setAttribute('class', 'wordmark-pixels');
      path.setAttribute('d', geometry.path);
      path.setAttribute('fill', 'url(#' + gradientId + ')');
      svg.append(defs, path);
      el.replaceChildren(svg);
      return;
    }
    const rows = [];
    for (let r = 0; r < 7; r++) {
      let line = '';
      for (const ch of text) {
        const glyph = FONT[ch] || FONT[' '];
        line += glyph[r].replace(/\./g, ' ') + ' ';
      }
      rows.push(line.replace(/\s+$/, ''));
    }
    el.textContent = rows.join('\n');
  });

  /* ---------- Pixel rain background ---------- */

  const canvas = document.getElementById('pixel-rain');
  if (canvas && canvas.getContext) {
    const ctx = canvas.getContext('2d');
    const palette = rainPalette.colors.length ? rainPalette.colors : ['#cba6f7', '#f5c2e7', '#94e2d5', '#89b4fa', '#fab387', '#585b70'];
    let cells = [];
    let size = 8;
    let cols = 0;
    let rows = 0;

    function reset() {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.floor(window.innerWidth * dpr);
      canvas.height = Math.floor(window.innerHeight * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      size = window.innerWidth < 720 ? 6 : 8;
      cols = Math.ceil(window.innerWidth / (size * 2));
      rows = Math.ceil(window.innerHeight / (size * 2));
      const count = Math.floor(cols * rows * 0.045);
      cells = Array.from({ length: count }, spawn);
    }

    function spawn() {
      const edge = Math.random();
      // Denser near the left and right edges, like a curtain
      const x = edge < 0.35 ? Math.random() * cols * 0.22 : edge < 0.7 ? cols * 0.78 + Math.random() * cols * 0.22 : Math.random() * cols;
      return {
        x: Math.floor(x), y: Math.floor(Math.random() * rows),
        colorIndex: Math.floor(Math.random() * 6),
        life: Math.random() * 6, speed: 0.15 + Math.random() * 0.5, alpha: 0.25 + Math.random() * 0.6
      };
    }

    function draw(t) {
      ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
      for (const c of cells) {
        const twinkle = 0.55 + 0.45 * Math.sin(c.life + t * 0.0015);
        ctx.globalAlpha = c.alpha * twinkle * 0.5;
        ctx.fillStyle = rainPalette.colors[c.colorIndex] || palette[c.colorIndex % palette.length];
        ctx.fillRect(c.x * size * 2, c.y * size * 2, size, size);
        if (!reduceMotion) {
          c.life += 0.01;
          if (Math.random() < c.speed * 0.02) c.y = (c.y + 1) % rows;
          if (Math.random() < 0.0015) Object.assign(c, spawn());
        }
      }
      ctx.globalAlpha = 1;
      if (!reduceMotion) requestAnimationFrame(draw);
    }

    reset();
    window.addEventListener('resize', reset);
    requestAnimationFrame(draw);
  }

  /* ---------- Live clock for the demo bar (and theme cards) ---------- */

  function tickClock() {
    const now = new Date();
    const day = now.toLocaleDateString(undefined, { weekday: 'long' });
    const time = now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    document.querySelectorAll('.bar-center').forEach(function (n) { n.textContent = day + ' ' + time; });
  }
  tickClock();
  setInterval(tickClock, 15000);

  /* ---------- Lesson demo director ---------- */

  const desktop = document.getElementById('desktop');
  if (!desktop) return;

  const coach = document.getElementById('coach');
  const caption = document.getElementById('caption');
  const captionText = document.getElementById('caption-text');
  const outline = document.getElementById('outline');
  const outlineLabel = document.getElementById('outline-label');
  const lesson = document.getElementById('lesson');
  const instruction = document.getElementById('lesson-instruction');
  const keycaps = document.getElementById('keycaps');
  const note = document.getElementById('lesson-note');
  const stepLabel = document.getElementById('lesson-step');
  const omenu = document.getElementById('omenu');
  const scene1 = document.getElementById('scene-1');
  const scene2 = document.getElementById('scene-2');
  const replay = document.getElementById('replay');

  const SPRITES = {
    idle: 'images/ohm-1-idle.png',
    flight: 'images/ohm-1-flight.png',
    point: 'images/ohm-1-point.png',
    'point-up': 'images/ohm-1-point-up.png'
  };
  // Where the pointing finger sits inside each sprite, as a fraction of its box
  const TIPS = { point: { x: 0.74, y: 0.39 }, 'point-up': { x: 0.66, y: 0.28 }, idle: { x: 0.5, y: 0.5 }, flight: { x: 0.5, y: 0.5 } };
  const ASPECT = { idle: 1, flight: 192 / 256, point: 192 / 224, 'point-up': 192 / 224 };

  let run = 0;
  let timers = [];
  const wait = (ms) => new Promise(function (resolve) { timers.push(setTimeout(resolve, ms)); });
  const alive = (id) => id === run;

  function pct(el) {
    const d = desktop.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    return { left: (r.left - d.left) / d.width * 100, top: (r.top - d.top) / d.height * 100, width: r.width / d.width * 100, height: r.height / d.height * 100 };
  }

  function setPose(pose, flip) {
    coach.className = coach.className.replace(/pose-[\w-]+/g, '').trim();
    coach.classList.add('pose-' + pose);
    coach.classList.toggle('flip', !!flip);
  }

  function coachSize() {
    const d = desktop.getBoundingClientRect();
    const w = coach.getBoundingClientRect().width / d.width * 100;
    return w;
  }

  // Tween helper: timer-driven so it advances anywhere setTimeout does
  function tween(ms, step) {
    return new Promise(function (resolve) {
      if (ms <= 0) { step(1); resolve(); return; }
      const start = performance.now();
      function frame() {
        const t = Math.max(0, Math.min(1, (performance.now() - start) / ms));
        step(t);
        if (t < 1) timers.push(setTimeout(frame, 16)); else resolve();
      }
      frame();
    });
  }
  const easeInOut = (t) => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

  // Move the coach so its finger tip (or center) lands at a desktop-relative point
  async function flyTo(x, y, pose, flip, opts) {
    opts = opts || {};
    const d = desktop.getBoundingClientRect();
    const w = coachSize();
    const h = w * ASPECT[pose] * (d.width / d.height);
    const tip = TIPS[pose];
    if (flip === undefined) flip = pose !== 'idle' && x < tip.x * w + 1;
    const tx = flip ? 1 - tip.x : tip.x;
    const left = Math.max(0.5, Math.min(99.5 - w, x - tx * w));
    const top = Math.max(-2, y - tip.y * h);
    const from = { left: parseFloat(coach.style.left) || 42, top: parseFloat(coach.style.top) || 110 };
    const dist = Math.hypot(left - from.left, top - from.top);
    const goingLeft = left < from.left;
    coach.classList.remove('settled');
    coach.classList.add('flying', 'thrust');
    setPose('flight', goingLeft);
    const ms = opts.ms || Math.max(900, Math.min(1700, dist * 18));
    const lift = Math.min(10, dist * 0.18);
    await tween(reduceMotion ? 0 : ms, function (t) {
      const e = easeInOut(t);
      const arc = Math.sin(Math.PI * t) * lift;
      coach.style.left = (from.left + (left - from.left) * e) + '%';
      coach.style.top = (from.top + (top - from.top) * e - arc) + '%';
      // Bank into the turn a little, level out on arrival
      coach.style.transform = 'rotate(' + ((goingLeft ? 1 : -1) * Math.sin(Math.PI * t) * 6) + 'deg)';
    });
    coach.style.left = left + '%';
    coach.style.top = top + '%';
    coach.style.transform = '';
    coach.classList.remove('flying');
    setPose(pose, flip);
    coach.classList.add('settled');
    coach.classList.remove('thrust');
    await wait(120);
  }

  function showOutline(el, label, pad) {
    const p = pct(el);
    pad = pad === undefined ? 0.6 : pad;
    outline.style.left = (p.left - pad) + '%';
    outline.style.top = (p.top - pad) + '%';
    outline.style.width = (p.width + pad * 2) + '%';
    outline.style.height = (p.height + pad * 2) + '%';
    outlineLabel.textContent = label || '';
    outline.classList.add('show');
  }
  function hideOutline() { outline.classList.remove('show'); }

  async function say(text, place, id) {
    caption.classList.remove('hidden');
    captionText.innerHTML = '';
    // Place the caption under the coach, or above him when there is no room, never on top of him
    const c = pct(coach);
    const cw = pct(caption).width;
    const below = c.top + c.height + 5;
    const isBelow = below < 80;
    const center = place.center ? 50 : c.left + c.width / 2;
    const left = Math.max(1, Math.min(99 - cw, center - cw / 2));
    caption.style.top = (isBelow ? below : Math.max(2, c.top - 16)) + '%';
    caption.style.left = left + '%';
    caption.style.transform = 'none';
    caption.classList.toggle('above', !isBelow);
    // Aim the notch at the coach's center
    const tail = Math.max(6, Math.min(94, (center - left) / cw * 100));
    caption.style.setProperty('--tail', tail + '%');
    const words = text.split(' ').map(function (w) {
      const s = document.createElement('span');
      s.className = 'word';
      s.textContent = w + ' ';
      captionText.appendChild(s);
      return s;
    });
    for (const w of words) {
      if (!alive(id)) return;
      w.classList.add('on');
      await wait(reduceMotion ? 0 : 150 + Math.min(w.textContent.length * 22, 200));
    }
    await wait(reduceMotion ? 600 : 900);
  }
  function hush() { caption.classList.add('hidden'); }

  function setKeys(keys) {
    keycaps.innerHTML = '';
    keys.forEach(function (k, i) {
      if (i) { const plus = document.createElement('span'); plus.textContent = '+'; keycaps.appendChild(plus); }
      const kbd = document.createElement('kbd');
      kbd.textContent = k;
      keycaps.appendChild(kbd);
    });
  }
  function hold(index) { keycaps.querySelectorAll('kbd')[index].classList.add('held'); }
  function releaseAll() { keycaps.querySelectorAll('kbd').forEach(function (k) { k.classList.remove('held'); }); }

  function showLesson(step, text, keys, noteText) {
    lesson.classList.remove('hidden');
    stepLabel.textContent = step;
    instruction.textContent = text;
    instruction.classList.remove('success');
    setKeys(keys);
    note.textContent = noteText || '';
  }
  function succeed(text) {
    instruction.textContent = text;
    instruction.classList.add('success');
    keycaps.innerHTML = '<span class="check">✓</span>';
  }

  function switchWorkspace(n) {
    desktop.querySelectorAll('.ws[data-ws]').forEach(function (p) { p.classList.toggle('active', p.dataset.ws === String(n)); });
    scene1.classList.add('fade'); scene2.classList.add('fade');
    return wait(240).then(function () {
      scene1.classList.toggle('hidden', n !== 1);
      scene2.classList.toggle('hidden', n !== 2);
      scene1.classList.remove('fade'); scene2.classList.remove('fade');
    });
  }

  function resetStage() {
    timers.forEach(clearTimeout); timers = [];
    hush(); hideOutline();
    lesson.classList.add('hidden');
    omenu.classList.add('hidden');
    replay.hidden = true;
    coach.classList.remove('settled', 'flying', 'thrust');
    setPose('idle', false);
    coach.style.left = '42%';
    coach.style.top = '110%';
    switchWorkspace(1);
  }

  async function play() {
    const id = ++run;
    resetStage();
    await wait(400);
    if (!alive(id)) return;

    const pills = document.getElementById('t-pills');
    const pill2 = pills.querySelector('[data-ws="2"]');
    const menuBtn = document.getElementById('t-menu');
    const clock = document.getElementById('t-clock');
    const status = document.getElementById('t-status');

    // 1. Arrive
    coach.classList.add('thrust');
    await flyTo(50, 52, 'idle', false, { ms: 1200 });
    if (!alive(id)) return;
    await say("Hi! I'm Ohm-1. Let's start with the desktop bar.", { center: true }, id);
    if (!alive(id)) return;

    // 2. Workspaces
    const pp = pct(pills);
    showOutline(pills, 'Workspaces', 0.5);
    await flyTo(pp.left + pp.width * 0.5, pp.top + pp.height + 7, 'point-up');
    if (!alive(id)) return;
    await say('These are your workspaces: separate desktops for different tasks. The active one is highlighted in the bar.', { top: 34 }, id);
    if (!alive(id)) return;

    // 3. Clock and status
    hideOutline();
    const cp = pct(clock);
    showOutline(clock, 'Clock and calendar', 0.5);
    await flyTo(cp.left + cp.width * 0.5, cp.top + cp.height + 7, 'point-up', false);
    if (!alive(id)) return;
    await say("Here's the date and time. Click it to open the calendar.", { top: 34 }, id);
    if (!alive(id)) return;
    hideOutline();
    const sp = pct(status);
    showOutline(status, 'System status', 0.5);
    await flyTo(sp.left + sp.width * 0.5, sp.top + sp.height + 7, 'point-up', false);
    if (!alive(id)) return;
    await say('Network, sound, and power live here. Select one to open its controls.', { top: 34, left: 40 }, id);
    if (!alive(id)) return;

    // 4. Shortcut: Super + 2
    hush(); hideOutline();
    showLesson('Step 3 of 8', 'Hold Super and tap 2 on the top row. Then release both keys.', ['Super', '2'], 'Your windows stay open when you switch workspaces.');
    const lp = pct(lesson);
    await flyTo(lp.left - 1.5, lp.top + lp.height * 0.55, 'point', false);
    if (!alive(id)) return;
    await wait(900); if (!alive(id)) return;
    hold(0); await wait(650); if (!alive(id)) return;
    hold(1); await wait(260); if (!alive(id)) return;
    await switchWorkspace(2);
    releaseAll();
    succeed("You're on workspace two. Nice.");
    showOutline(pill2, 'Workspace 2', 0.5);
    await wait(2200); if (!alive(id)) return;

    // 5. Omarchy menu
    hideOutline();
    showLesson('Step 7 of 8', 'Hold Super and tap Space to open the Omarchy menu.', ['Super', 'Space'], '');
    await wait(1100); if (!alive(id)) return;
    hold(0); await wait(650); if (!alive(id)) return;
    hold(1); await wait(260); if (!alive(id)) return;
    omenu.classList.remove('hidden');
    releaseAll();
    succeed('The Omarchy menu is open. Everything starts here.');
    const mp = pct(omenu);
    showOutline(omenu, 'Omarchy menu', 0.6);
    await flyTo(mp.left - 1, mp.top + mp.height * 0.45, 'point', false);
    if (!alive(id)) return;
    await wait(500); if (!alive(id)) return;
    lesson.classList.add('hidden');
    await say('Apps, capture, themes, setup, and updates all live in this one menu. You can also click the icon in the bar.', {}, id);
    if (!alive(id)) return;

    // 6. Wrap
    hush(); hideOutline();
    omenu.classList.add('hidden');
    await flyTo(50, 50, 'idle', false);
    if (!alive(id)) return;
    await say("That's the tour. Ready for the next lesson?", { center: true }, id);
    if (!alive(id)) return;
    replay.hidden = false;
  }

  replay.addEventListener('click', play);

  if (reduceMotion) {
    desktop.classList.add('reduced');
    resetStage();
    coach.style.left = '2%'; coach.style.top = '8%';
    setPose('point-up', false);
    showLesson('Step 3 of 8', 'Hold Super and tap 2 on the top row. Then release both keys.', ['Super', '2'], 'Your windows stay open when you switch workspaces.');
    showOutline(document.getElementById('t-pills'), 'Workspaces', 0.5);
    replay.hidden = true;
    return;
  }

  let started = false;
  function startOnce() {
    if (started) return;
    started = true;
    play();
  }
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries, obs) {
      if (entries.some(function (e) { return e.isIntersecting; })) { startOnce(); obs.disconnect(); }
    }, { threshold: 0.35 }).observe(desktop);
  } else {
    startOnce();
  }
})();

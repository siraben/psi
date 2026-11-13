'use strict';

document.querySelectorAll('[role="tablist"]').forEach(group => {
  const tabs = [...group.querySelectorAll('[role="tab"]')];
  function selectTab(tab) {
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    });
    group.dispatchEvent(new CustomEvent('tabselect', { bubbles: true }));
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next === undefined) return;
      event.preventDefault();
      selectTab(tabs[next]);
      tabs[next].focus();
    });
  });
});
document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.classList.add('is-copied');
      document.querySelector('.copy-status').textContent = 'Command copied to clipboard.';
      setTimeout(() => { button.classList.remove('is-copied'); }, 2000);
    } catch {
      const command = button.parentElement.querySelector('code');
      const range = document.createRange();
      range.selectNodeContents(command);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      document.querySelector('.copy-status').textContent = 'Copy is unavailable. The command is selected; use your copy shortcut.';
    }
  });
});


const demoPlayers = new Map();
const visibleDemos = new Set();
let playerAssets;
function loadPlayer() {
  if (window.AsciinemaPlayer) return Promise.resolve();
  if (playerAssets) return playerAssets;
  playerAssets = Promise.all([
    new Promise((resolve, reject) => {
      const style = document.createElement('link');
      style.rel = 'stylesheet';
      style.href = 'assets/player/asciinema-player.css';
      style.onload = resolve;
      style.onerror = () => { style.remove(); reject(new Error('Player stylesheet failed to load')); };
      document.head.append(style);
    }),
    new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'assets/player/asciinema-player.min.js';
      script.onload = resolve;
      script.onerror = () => { script.remove(); reject(new Error('Player script failed to load')); };
      document.head.append(script);
    }),
  ]).catch(error => { playerAssets = undefined; throw error; });
  return playerAssets;
}
const demoObserver = new IntersectionObserver(entries => {
  entries.forEach(async entry => {
    const container = entry.target;
    const player = demoPlayers.get(container);
    const ratio = entry.intersectionRatio;
    if (ratio >= 0.5) {
      visibleDemos.add(container);
      if (document.hidden) return;
      if (player) {
        if (container.dataset.state !== 'playing') { container.dataset.state = 'playing'; player.play(); }
        return;
      }
      if (container.dataset.loading) return;
      container.dataset.loading = '1';
      try {
        await loadPlayer();
        container.replaceChildren();
        const playing = visibleDemos.has(container) && !document.hidden;
        container.dataset.state = playing ? 'playing' : 'paused';
        demoPlayers.set(container, window.AsciinemaPlayer.create(container.dataset.recording, container, {
          autoplay: playing,
          loop: true,
          preload: true,
          fit: 'width',
          theme: 'asciinema',
          idleTimeLimit: 2,
          terminalFontFamily: "'IBM Plex Mono', monospace",
        }));
      } catch {
        delete container.dataset.loading;
      }
    } else if (ratio < 0.05) {
      visibleDemos.delete(container);
      if (player && container.dataset.state === 'playing') {
        container.dataset.state = 'paused';
        player.pause();
      }
    }
  });
}, { threshold: [0, 0.05, 0.5] });
document.querySelectorAll('.terminal-demo[data-recording]').forEach(container => demoObserver.observe(container));

// SVG and the accessible table are generated from the same CycloneDX records.
const dependencySection = document.getElementById('dependencies');
if (dependencySection) {
  const graph = JSON.parse(document.getElementById('dependency-data').textContent);
  const packages = new Map(graph.nodes.map(node => [node.id, node]));
  let activeGraph = graph.views.both;
  let selectedPackage = null;
  const enabledScopes = new Set(['runtime', 'build']);
  const reset = dependencySection.querySelector('.dependency-reset');
  const hintBox = dependencySection.querySelector('.dependency-hint');
  dependencySection.querySelectorAll('.dep-folder-toggle').forEach(toggle => toggle.addEventListener('click', () => {
    const open = toggle.getAttribute('aria-expanded') !== 'true';
    toggle.setAttribute('aria-expanded', String(open));
    toggle.parentElement.classList.toggle('is-open', open);
  }));
  const relations = dependencySection.querySelector('.dependency-relations');
  const selectPackage = id => {
    const selected = packages.get(id);
    if (!selected) return;
    selectedPackage = id;
    dependencySection.querySelectorAll('[data-list]').forEach(item => item.classList.toggle('is-current', item.dataset.list === id));
    const outgoing = activeGraph.edges.filter(edge => edge.source === id).map(edge => edge.target);
    const incoming = activeGraph.edges.filter(edge => edge.target === id).map(edge => edge.source);
    const neighbors = new Set([id, ...outgoing, ...incoming]);
    dependencySection.querySelectorAll('[data-package]').forEach(node => {
      const active = node.dataset.package === id;
      node.classList.toggle('is-selected', active);
      node.classList.toggle('is-muted', !neighbors.has(node.dataset.package));
      node.setAttribute('aria-pressed', String(active));
    });
    dependencySection.querySelectorAll('.edge').forEach(edge => {
      const connected = edge.dataset.source === id || edge.dataset.target === id;
      edge.classList.toggle('is-selected', connected);
      edge.classList.toggle('is-muted', !connected);
    });
    dependencySection.querySelector('#dependency-detail-name').textContent = selected.name;
    dependencySection.querySelector('.dep-path-name').textContent = selected.name;
    dependencySection.querySelector('.dep-statusbar').textContent = `${outgoing.length} dependencies, ${incoming.length} dependents`;
    dependencySection.querySelector('.dependency-detail-version').textContent = selected.version + ' · ' + (selected.scope === 'runtime' ? 'Retained at runtime' : 'Build-time only');
    dependencySection.querySelector('.dependency-detail-license').textContent = 'Package license metadata: ' + (selected.licenses.join(', ') || 'not recorded in the SBOM');
    const renderList = (selector, ids) => {
      const list = dependencySection.querySelector(selector);
      list.replaceChildren();
      list.closest('.dep-folder').querySelector('.dep-count').textContent = ids.length;
      ids.sort((a, b) => packages.get(a).name.localeCompare(packages.get(b).name)).forEach(target => {
        const li = document.createElement('li');
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = packages.get(target).name;
        const version = document.createElement('span');
        version.textContent = packages.get(target).version;
        button.append(version);
        button.addEventListener('click', () => {
          selectPackage(target);
          dependencySection.querySelector('#dependency-detail-name').focus({preventScroll: true});
        });
        li.append(button); list.append(li);
      });
      if (!ids.length) {
        const li = document.createElement('li');
        li.textContent = 'None in this view'; list.append(li);
      }
    };
    renderList('.dependency-outgoing', outgoing);
    renderList('.dependency-incoming', incoming);
    relations.hidden = false; hintBox.classList.add('is-selected'); reset.tabIndex = 0;
    dependencySection.querySelector('.dependency-status').textContent = `${selected.name} ${selected.version}: ${outgoing.length} shown dependencies, used by ${incoming.length} shown packages.`;
  };
  dependencySection.querySelector('#dependency-detail-name').tabIndex = -1;
  dependencySection.querySelectorAll('[data-package]').forEach(node => {
    const trace = on => node.closest('svg').querySelectorAll('.edge').forEach(edge => {
      const linked = on && (edge.dataset.source === node.dataset.package || edge.dataset.target === node.dataset.package);
      edge.classList.toggle('is-hover', linked);
      if (linked) edge.parentNode.appendChild(edge);
    });
    node.addEventListener('mouseenter', () => trace(true));
    node.addEventListener('mouseleave', () => trace(false));
    node.addEventListener('focus', () => trace(true));
    node.addEventListener('blur', () => trace(false));
    node.addEventListener('click', () => selectPackage(node.dataset.package));
    node.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault(); selectPackage(node.dataset.package);
      }
    });
  });
  const sideScroll = dependencySection.querySelector('.dep-side-scroll');
  let freshFrame = 0;
  new MutationObserver(() => {
    cancelAnimationFrame(freshFrame);
    freshFrame = requestAnimationFrame(() => {
      sideScroll.classList.remove('is-fresh');
      void sideScroll.offsetWidth;
      sideScroll.classList.add('is-fresh');
    });
  }).observe(sideScroll, {childList: true, characterData: true, subtree: true});
  const clearSelection = (focus = false) => {
    selectedPackage = null;
    dependencySection.querySelectorAll('[data-list]').forEach(item => item.classList.remove('is-current'));
    dependencySection.querySelectorAll('.is-selected, .is-muted').forEach(node => node.classList.remove('is-selected', 'is-muted'));
    dependencySection.querySelectorAll('[data-package]').forEach(node => node.setAttribute('aria-pressed', 'false'));
    dependencySection.querySelector('#dependency-detail-name').textContent = 'Select a package';
    dependencySection.querySelector('.dep-path-name').textContent = 'All packages';
    dependencySection.querySelector('.dep-statusbar').textContent = 'Select a package';
    dependencySection.querySelector('.dependency-detail-version').textContent = 'Select any package.';
    dependencySection.querySelector('.dependency-detail-license').textContent = 'Select a node to see its version, package license metadata, and shown connections.';
    relations.hidden = true; hintBox.classList.remove('is-selected'); reset.tabIndex = -1;
    dependencySection.querySelector('.dependency-status').textContent = 'Showing all package connections.';
    if (focus) dependencySection.querySelector('#dependency-detail-name').focus({preventScroll:true});
  };
  reset.addEventListener('click', () => clearSelection(true));
  const graphSvg = dependencySection.querySelector('.dependency-svg');
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const baseBox = graphSvg ? graphSvg.getAttribute('viewBox').trim().split(/\s+/).map(Number) : null;
  let nodeBoxes = null;
  let panFrame = 0;
  const measureNodes = () => {
    const matrix = graphSvg.getScreenCTM();
    if (!matrix || !graphSvg.clientWidth) return null;
    const inverse = matrix.inverse();
    const boxes = new Map();
    graphSvg.querySelectorAll('[data-package]').forEach(node => {
      const rect = node.getBoundingClientRect();
      const a = new DOMPoint(rect.left, rect.top).matrixTransform(inverse);
      const b = new DOMPoint(rect.right, rect.bottom).matrixTransform(inverse);
      boxes.set(node.dataset.package, [a.x, a.y, b.x, b.y]);
    });
    return boxes;
  };
  const nodeOn = id => id === graph.root || enabledScopes.has(packages.get(id).scope);
  const panTo = target => {
    const from = graphSvg.getAttribute('viewBox').trim().split(/\s+/).map(Number);
    cancelAnimationFrame(panFrame);
    if (reduceMotion) { graphSvg.setAttribute('viewBox', target.join(' ')); return; }
    const started = performance.now();
    const step = now => {
      const progress = Math.min((now - started) / 700, 1);
      const eased = progress < 0.5 ? 4 * progress ** 3 : 1 - (-2 * progress + 2) ** 3 / 2;
      graphSvg.setAttribute('viewBox', from.map((value, index) => value + (target[index] - value) * eased).join(' '));
      if (progress < 1) panFrame = requestAnimationFrame(step);
    };
    panFrame = requestAnimationFrame(step);
  };
  const applyScopes = () => {
    if (!graphSvg) return;
    graphSvg.querySelectorAll('[data-package]').forEach(node => {
      const on = nodeOn(node.dataset.package);
      node.classList.toggle('is-off', !on);
      node.setAttribute('tabindex', on ? '0' : '-1');
      node.setAttribute('aria-hidden', String(!on));
    });
    dependencySection.querySelectorAll('[data-list]').forEach(item => item.closest('li').classList.toggle('is-off', item.dataset.list !== graph.root && !enabledScopes.has(item.dataset.listScope)));
    graphSvg.querySelectorAll('.edge').forEach(edge => edge.classList.toggle('is-off', !enabledScopes.has(edge.dataset.scope)));
    const cluster = graphSvg.querySelector('.cluster');
    if (cluster) cluster.classList.toggle('is-off', !enabledScopes.has('build'));
    if (!nodeBoxes) nodeBoxes = measureNodes();
    if (!nodeBoxes) return;
    if (enabledScopes.size === 2) { panTo(baseBox); return; }
    const shown = [...nodeBoxes].filter(([id]) => nodeOn(id)).map(([, box]) => box);
    const left = Math.min(...shown.map(box => box[0])), right = Math.max(...shown.map(box => box[2]));
    const top = Math.min(...shown.map(box => box[1])), bottom = Math.max(...shown.map(box => box[3]));
    panTo([(left + right) / 2 - baseBox[2] / 2, (top + bottom) / 2 - baseBox[3] / 2, baseBox[2], baseBox[3]]);
  };
  dependencySection.querySelectorAll('[data-list]').forEach(item => item.addEventListener('click', () => {
    if (activeGraph.nodes.some(node => node.id === item.dataset.list)) selectPackage(item.dataset.list);
  }));
  const infoButton = dependencySection.querySelector('.dep-info');
  const infoPop = dependencySection.querySelector('.dep-info-pop');
  const setInfo = open => {
    infoButton.setAttribute('aria-expanded', String(open));
    infoPop.classList.toggle('is-open', open);
  };
  infoPop.querySelector('.pop-close').addEventListener('click', () => setInfo(false));
  infoButton.addEventListener('click', () => setInfo(infoButton.getAttribute('aria-expanded') !== 'true'));
  document.addEventListener('click', event => { if (!infoPop.contains(event.target) && !infoButton.contains(event.target)) setInfo(false); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') setInfo(false); });
  const groupToggle = dependencySection.querySelector('.dep-group-toggle');
  groupToggle.addEventListener('click', () => {
    const open = groupToggle.getAttribute('aria-expanded') !== 'true';
    groupToggle.setAttribute('aria-expanded', String(open));
    groupToggle.parentElement.classList.toggle('is-open', open);
  });
  const scopeButtons = [...dependencySection.querySelectorAll('.dependency-controls button[data-scope]')];
  scopeButtons.forEach(button => button.addEventListener('click', () => {
    const scope = button.dataset.scope;
    if (enabledScopes.has(scope)) {
      if (enabledScopes.size === 1) return;
      enabledScopes.delete(scope);
    } else enabledScopes.add(scope);
    const view = enabledScopes.size === 2 ? 'both' : [...enabledScopes][0];
    applyScopes();
    activeGraph = graph.views[view];
    dependencySection.querySelectorAll('[data-view]').forEach(element => { element.hidden = element.dataset.view !== view; });
    scopeButtons.forEach(control => {
      const active = enabledScopes.has(control.dataset.scope);
      control.setAttribute('aria-pressed', String(active));
      control.disabled = active && enabledScopes.size === 1;
    });
    const countEl = dependencySection.querySelector('.dependency-count'); if (countEl) countEl.textContent = `${activeGraph.nodes.length} packages / ${activeGraph.edges.length} connections`;
    if (selectedPackage && activeGraph.nodes.some(node => node.id === selectedPackage)) selectPackage(selectedPackage);
    else clearSelection();
    dependencySection.querySelector('.dependency-status').textContent = `Showing ${view === 'both' ? 'runtime and build' : view} dependencies: ${activeGraph.nodes.length} packages.`;
  }));
}

(function(){
  var links=[].slice.call(document.querySelectorAll('.site-header nav a[href^="#"]'));
  if(!links.length||!window.IntersectionObserver)return;
  var targets=links.map(function(a){return document.querySelector(a.getAttribute('href'));});
  var frame=0,current=-2;
  function update(){
    frame=0;
    var line=window.innerHeight*0.35,active=-1;
    targets.forEach(function(t,i){if(t){var bounds=t.getBoundingClientRect();if(bounds.top<=line&&bounds.bottom>line)active=i;}});
    if(active===current)return;
    current=active;
    links.forEach(function(a,i){if(i===active)a.setAttribute('aria-current','true');else a.removeAttribute('aria-current');});
  }
  function schedule(){if(!frame)frame=requestAnimationFrame(update);}
  window.addEventListener('scroll',schedule,{passive:true});
  window.addEventListener('resize',schedule);
  update();
})();

(function(){
  var DUR=420,current=null,busy=false;
  var reduce=window.matchMedia&&window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  function target(win){
    var vw=window.innerWidth,vh=window.innerHeight;
    var bar=win.querySelector('.mac-bar').offsetHeight;
    var extra=bar+6+6+2,aspect=620/430.5;
    var W=Math.min(860,vw*0.68);
    var H=extra+(W-14)/aspect;
    if(H>vh*0.72){H=vh*0.72;W=(H-extra)*aspect+14;}
    return{left:(vw-W)/2,top:(vh-H)/2,width:W,height:H};
  }
  function place(win,r){
    win.style.left=r.left+'px';win.style.top=r.top+'px';win.style.width=r.width+'px';win.style.height=r.height+'px';
  }
  function open(win){
    if(busy||current)return;
    busy=true;
    var r=win.getBoundingClientRect();
    var ph=document.createElement('div');
    ph.className='mac-ph';
    ph.style.width=r.width+'px';ph.style.height=r.height+'px';
    win.before(ph);
    var bd=document.createElement('div');
    bd.className='pop-backdrop';
    document.body.append(bd);
    bd.addEventListener('click',close);
    win.style.transition='none';
    place(win,r);
    win.classList.add('is-popup');
    document.documentElement.style.overflow='hidden';
    void win.offsetWidth;
    win.style.transition='';
    place(win,target(win));
    bd.classList.add('on');
    current={win:win,ph:ph,bd:bd};
    setTimeout(function(){busy=false;if(current)current.win.style.height='auto';},reduce?0:DUR+30);
  }
  function close(){
    if(busy||!current)return;
    busy=true;
    var c=current,r=c.ph.getBoundingClientRect();
    c.win.style.height=c.win.getBoundingClientRect().height+'px';
    void c.win.offsetWidth;
    place(c.win,r);
    c.bd.classList.remove('on');
    setTimeout(function(){
      c.win.classList.remove('is-popup');
      c.win.removeAttribute('style');
      c.ph.remove();c.bd.remove();
      document.documentElement.style.overflow='';
      current=null;busy=false;
    },reduce?0:DUR+30);
  }
  function toggle(win){current?close():open(win);}
  document.addEventListener('click',function(e){
    var b=e.target.closest&&e.target.closest('.ap-fullscreen-button');
    var w=b&&b.closest('.mac-window');
    if(!w)return;
    e.preventDefault();e.stopImmediatePropagation();toggle(w);
  },true);
  document.addEventListener('keydown',function(e){
    if(e.key==='Escape'&&current){e.preventDefault();close();return;}
    if((e.key==='f'||e.key==='F')&&!e.metaKey&&!e.ctrlKey&&!e.altKey){
      var w=e.target.closest&&e.target.closest('.mac-window');
      if(w&&w.querySelector('.ap-player')){e.preventDefault();e.stopImmediatePropagation();toggle(w);}
    }
  },true);
  window.addEventListener('resize',function(){
    if(!current)return;
    current.win.style.transition='none';
    place(current.win,target(current.win));
    current.win.style.height='auto';
    void current.win.offsetWidth;
    current.win.style.transition='';
  });
})();

const portCards = document.querySelector('.port-cards');
if (portCards) {
  const revealCards = () => portCards.classList.add('is-in');
  if (window.IntersectionObserver) {
    const portObserver = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) { revealCards(); portObserver.disconnect(); }
    }, {threshold: 0.25});
    portObserver.observe(portCards);
  } else revealCards();
}

const portStage = document.querySelector('.port-stage');
if (portStage) {
  portStage.querySelectorAll('img').forEach(img => { img.draggable = false; });
  portStage.addEventListener('dragstart', event => event.preventDefault());
  const panes = [...portStage.querySelectorAll('.stage-pane')];
  const paneFor = { linux: ['linux', 'linux-alt'], windows: ['windows'], haiku: ['haiku'] };
  const reduceStage = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const base = document.createElement('div');
  base.className = 'stage-bg';
  base.style.backgroundImage = 'url(assets/textures/photo1.jpg?v=4)';
  portStage.prepend(base);
  const spots = [[-70, -26], [64, 30], [-26, 54], [96, -48]];
  const offsets = new Map();
  let opened = 0;
  let zTop = 2;
  const dragBounds = win => {
    const stage = portStage.getBoundingClientRect();
    const rect = win.getBoundingClientRect();
    const baseLeft = rect.left - (offsets.get(win)?.x || 0);
    const baseTop = rect.top - (offsets.get(win)?.y || 0);
    const minX = stage.left + 90 - (baseLeft + rect.width) ;
    const maxX = stage.right - 90 - baseLeft;
    const minY = stage.top - baseTop;
    const maxY = stage.bottom - 48 - baseTop;
    return { minX, maxX, minY, maxY };
  };
  const place = (win, x, y) => {
    offsets.set(win, { x, y });
    win.style.translate = `${x}px ${y}px`;
  };
  const markCurrent = pane => {
    const key = pane.dataset.platform.replace('-alt', '');
    document.querySelectorAll('.port-card').forEach(card => card.classList.toggle('is-current', card.dataset.platform === key));
  };
  const bringToFront = pane => {
    zTop += 1;
    pane.style.zIndex = zTop;
    panes.forEach(other => other.classList.toggle('is-top', other === pane));
    markCurrent(pane);
  };
  const compact = window.matchMedia('(max-width: 1050px)');
  const openPane = (pane, pop) => {
    portStage.classList.remove('is-soon');
    if (compact.matches) {
      panes.forEach(other => {
        if (other === pane) return;
        other.classList.remove('is-active', 'is-top');
        offsets.delete(other.querySelector('.mac-window'));
        other.querySelector('.mac-window').style.translate = '';
      });
    }
    const win = pane.querySelector('.mac-window');
    const fresh = !pane.classList.contains('is-active');
    pane.classList.add('is-active');
    if (fresh) {
      const [x, y] = compact.matches ? [0, 0] : spots[opened % spots.length];
      const k = Math.min(1, portStage.offsetWidth / 860);
      opened += 1;
      place(win, x * k, y * k);
    }
    bringToFront(pane);
    if (pop && !reduceStage) {
      win.animate([{ transform: 'scale(0.9)' }, { transform: 'scale(1.015)', offset: 0.7 }, { transform: 'scale(1)' }], { duration: 300, easing: 'cubic-bezier(.22,.8,.24,1)' });
    }
  };
  panes.forEach(pane => {
    const win = pane.querySelector('.mac-window');
    const bar = win.querySelector('.mac-bar');
    pane.addEventListener('pointerdown', () => { if (!pane.classList.contains('is-top')) bringToFront(pane); });
    let drag = null;
    let dragFrame = 0;
    const move = () => {
      dragFrame = 0;
      if (!drag) return;
      const { minX, maxX, minY, maxY } = drag.bounds;
      place(win, Math.min(Math.max(drag.x + drag.dx, minX), maxX), Math.min(Math.max(drag.y + drag.dy, minY), maxY));
    };
    bar.addEventListener('pointerdown', event => {
      if (event.button !== 0 || compact.matches) return;
      const start = offsets.get(win) || { x: 0, y: 0 };
      drag = { id: event.pointerId, px: event.clientX, py: event.clientY, x: start.x, y: start.y, dx: 0, dy: 0, bounds: dragBounds(win) };
      bar.setPointerCapture(event.pointerId);
      win.classList.add('is-dragging');
      event.preventDefault();
    });
    bar.addEventListener('pointermove', event => {
      if (!drag || event.pointerId !== drag.id) return;
      drag.dx = event.clientX - drag.px;
      drag.dy = event.clientY - drag.py;
      if (!dragFrame) dragFrame = requestAnimationFrame(move);
    });
    const end = event => {
      if (!drag || event.pointerId !== drag.id) return;
      cancelAnimationFrame(dragFrame);
      move();
      drag = null;
      win.classList.remove('is-dragging');
    };
    bar.addEventListener('pointerup', end);
    bar.addEventListener('pointercancel', end);
    bar.addEventListener('lostpointercapture', end);
  });
  const select = platform => {
    const keys = paneFor[platform];
    if (!keys) return;
    keys.forEach((key, index) => {
      if (compact.matches && index > 0) return;
      const pane = panes.find(item => item.dataset.platform === key);
      const run = () => openPane(pane, !pane.classList.contains('is-active'));
      if (index === 0) run();
      else setTimeout(run, 260);
    });
  };
  const showSoon = card => {
    portStage.classList.add('is-soon');
    document.querySelectorAll('.port-card').forEach(other => other.classList.toggle('is-current', other === card));
  };
  document.querySelectorAll('.port-card.is-textonly').forEach(card => {
    card.addEventListener('click', () => showSoon(card));
    card.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); showSoon(card); }
    });
  });
  document.querySelectorAll('.port-card:not(.is-textonly)').forEach(card => {
    card.addEventListener('click', () => select(card.dataset.platform));
    card.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); select(card.dataset.platform); }
    });
  });
  const first = panes.find(pane => pane.dataset.platform === 'linux');
  openPane(first, false);
}

const installTabs = document.querySelector('.install-panel .install-tabs');
const installBody = document.querySelector('.install-panel .install-body');
if (installTabs && installBody) {
  const pill = installTabs.querySelector('.tab-pill');
  const movePill = animate => {
    const current = installTabs.querySelector('[aria-selected="true"]');
    if (!pill || !current) return;
    if (!animate) pill.style.transition = 'none';
    pill.style.width = `${current.offsetWidth}px`;
    pill.style.height = `${current.offsetHeight}px`;
    pill.style.transform = `translate(${current.offsetLeft}px, ${current.offsetTop}px)`;
    if (!animate) { pill.getBoundingClientRect(); pill.style.transition = ''; }
  };
  movePill(false);
  window.addEventListener('resize', () => movePill(false));
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => movePill(false));
  installTabs.addEventListener('click', () => requestAnimationFrame(() => movePill(true)));
  const reduceInstall = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let resizeToken = 0;
  installTabs.addEventListener('click', event => {
    if (!event.target.closest('[role="tab"]') || reduceInstall) return;
    const from = installBody.getBoundingClientRect().height;
    installBody.getAnimations().forEach(animation => animation.cancel());
    installBody.querySelectorAll('.install-content').forEach(panel => panel.getAnimations().forEach(animation => animation.cancel()));
    installBody.style.height = `${from}px`;
    installBody.style.clipPath = 'inset(-60px -20px 0 -20px)';
    const token = ++resizeToken;
    requestAnimationFrame(() => {
      if (token !== resizeToken) return;
      installBody.style.height = '';
      const to = installBody.getBoundingClientRect().height;
      const visible = installBody.querySelector('.install-content:not([hidden])');
      if (visible) visible.animate([{ opacity: 0.55 }, { opacity: 1 }], { duration: 260, easing: 'cubic-bezier(.22,.8,.24,1)' });
      if (Math.abs(from - to) < 1) { installBody.style.clipPath = ''; return; }
      const animation = installBody.animate([{ height: `${from}px` }, { height: `${to}px` }], { duration: 300, easing: 'cubic-bezier(.22,.8,.24,1)' });
      const release = () => { if (token === resizeToken) installBody.style.clipPath = ''; };
      animation.addEventListener('finish', release);
      animation.addEventListener('cancel', release);
    });
  }, true);
}

(function () {
  var rows = [].slice.call(document.querySelectorAll('.marquee-row'));
  if (!rows.length) return;
  function itemHtml(row, first) {
    var extra = first ? '' : ' tabindex="-1" aria-hidden="true"';
    return '<a class="m-item" href="' + row.dataset.href + '" target="_blank" rel="noopener"' + extra + '>' + row.dataset.text + '</a>';
  }
  function fill() {
    rows.forEach(function (row) {
      row.innerHTML = '<div class="marquee-track"><div class="marquee-group"></div><div class="marquee-group"></div></div>';
      var groups = row.querySelectorAll('.marquee-group');
      groups[0].innerHTML = itemHtml(row, true);
      var unit = groups[0].offsetWidth || 300;
      var count = Math.ceil(row.offsetWidth / unit) + 1;
      var one = '';
      var two = '';
      for (var i = 0; i < count; i += 1) { one += itemHtml(row, i === 0); two += itemHtml(row, false); }
      groups[0].innerHTML = one;
      groups[1].innerHTML = two;
    });
  }
  fill();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(fill);
  var timer = 0;
  window.addEventListener('resize', function () { clearTimeout(timer); timer = setTimeout(fill, 150); });
})();

// Keep the same visible effects without animating artwork outside the viewport.
const artworkObserver = new IntersectionObserver(entries => {
  entries.forEach(entry => entry.target.classList.toggle('is-animation-idle', !entry.isIntersecting));
}, { rootMargin: '100px' });
document.querySelectorAll('.feature-art, .marquee-row').forEach(artwork => {
  artwork.classList.add('is-animation-idle');
  artworkObserver.observe(artwork);
});

const textureObserver = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add('is-texture-ready');
    textureObserver.unobserve(entry.target);
  });
}, { rootMargin: '300px' });
document.querySelectorAll('.demo-media, .feature-art, .dependency-card, .extend-section, .window-backdrop, .start-card, .stage-bg').forEach(surface => textureObserver.observe(surface));

const syncPageVisibility = () => {
  document.documentElement.classList.toggle('is-page-idle', document.hidden);
  demoPlayers.forEach((player, container) => {
    const playing = !document.hidden && visibleDemos.has(container);
    if ((container.dataset.state === 'playing') === playing) return;
    container.dataset.state = playing ? 'playing' : 'paused';
    if (playing) player.play(); else player.pause();
  });
  if (!document.hidden) visibleDemos.forEach(container => {
    if (demoPlayers.has(container)) return;
    demoObserver.unobserve(container);
    demoObserver.observe(container);
  });
};
document.addEventListener('visibilitychange', syncPageVisibility);
syncPageVisibility();

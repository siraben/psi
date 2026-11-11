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
      button.textContent = 'Copied ✓';
      document.querySelector('.copy-status').textContent = 'Command copied to clipboard.';
      setTimeout(() => { button.textContent = 'Copy ⧉'; }, 2000);
    } catch {
      button.textContent = 'Select text';
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
      if (player) {
        if (container.dataset.state !== 'playing') { container.dataset.state = 'playing'; player.play(); }
        return;
      }
      if (container.dataset.loading) return;
      container.dataset.loading = '1';
      try {
        await loadPlayer();
        container.replaceChildren();
        container.dataset.state = 'playing';
        demoPlayers.set(container, window.AsciinemaPlayer.create(container.dataset.recording, container, {
          autoplay: true,
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
    } else if (ratio < 0.05 && player && container.dataset.state === 'playing') {
      container.dataset.state = 'paused';
      player.pause();
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
  const scopeButtons = [...dependencySection.querySelectorAll('[data-scope]')];
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
  var dlg=document.createElement('dialog');
  dlg.className='lightbox';
  dlg.innerHTML='<button class="lightbox-close" type="button" aria-label="Close">\u00d7</button><img alt="">';
  document.body.appendChild(dlg);
  var img=dlg.querySelector('img');
  function close(){dlg.close();}
  dlg.addEventListener('click',close);
  document.addEventListener('click',function(e){
    var a=e.target.closest&&e.target.closest('a.gallery-image');
    if(!a||e.metaKey||e.ctrlKey||e.shiftKey||!dlg.showModal)return;
    e.preventDefault();
    var thumb=a.querySelector('img');
    img.src=a.getAttribute('href');
    img.alt=thumb?thumb.alt:'';
    dlg.showModal();
  });
})();
(function(){
  var links=[].slice.call(document.querySelectorAll('.site-header nav a[href^="#"]'));
  if(!links.length||!window.IntersectionObserver)return;
  var targets=links.map(function(a){return document.querySelector(a.getAttribute('href'));});
  function update(){
    var line=window.innerHeight*0.35,active=-1;
    targets.forEach(function(t,i){if(t&&t.getBoundingClientRect().top<=line&&t.getBoundingClientRect().bottom>line)active=i;});
    links.forEach(function(a,i){if(i===active)a.setAttribute('aria-current','true');else a.removeAttribute('aria-current');});
  }
  window.addEventListener('scroll',update,{passive:true});
  window.addEventListener('resize',update);
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
  const panes = [...portStage.querySelectorAll('.stage-pane')];
  const stageFor = { linux: 'linux', windows: 'windows', haiku: 'haiku' };
  const textures = { linux: 'photo1', 'linux-alt': 'photo1', windows: 'photo3', haiku: 'photo4' };
  const reduceStage = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const bgUrl = name => `url(assets/textures/${name}.jpg?v=4)`;
  const base = document.createElement('div');
  base.className = 'stage-bg';
  const glitch = document.createElement('div');
  glitch.className = 'stage-glitch';
  portStage.prepend(glitch);
  portStage.prepend(base);
  let currentTexture = null;
  let glitchTimer = 0;
  const STRIPS = 14;
  const setBackground = texture => {
    if (texture === currentTexture) return;
    currentTexture = texture;
    base.style.backgroundImage = bgUrl(texture);
  };
  const show = (key, origin) => {
    const previous = panes.find(pane => pane.classList.contains('is-active'));
    panes.forEach(pane => pane.classList.toggle('is-active', pane.dataset.platform === key));
    document.querySelectorAll('.port-card').forEach(card => card.classList.toggle('is-current', stageFor[card.dataset.platform] === key.replace('-alt', '')));
    setBackground(textures[key]);
    const active = panes.find(pane => pane.dataset.platform === key);
    if (!origin || reduceStage || active === previous) return;
    const windowEl = active.querySelector('.mac-window');
    const box = windowEl.getBoundingClientRect();
    const originY = Math.min(Math.max((origin - box.top) / box.height, 0), 1) * 100;
    windowEl.style.transformOrigin = `-8% ${originY}%`;
    windowEl.animate([
      { transform: 'scale(0.03, 0.06)', clipPath: 'polygon(0 36%, 100% 0, 100% 100%, 0 64%)', opacity: 0.9, offset: 0 },
      { transform: 'scale(0.7, 0.55)', clipPath: 'polygon(0 4%, 100% 0, 100% 100%, 0 96%)', opacity: 1, offset: 0.55 },
      { transform: 'scale(1, 1)', clipPath: 'polygon(0 0, 100% 0, 100% 100%, 0 100%)', opacity: 1, offset: 1 }
    ], { duration: 720, easing: 'cubic-bezier(.22,.8,.24,1)' });
  };
  let cycle = 0;
  const select = (platform, origin) => {
    const key = stageFor[platform];
    if (!key) return;
    const wasActive = panes.some(pane => pane.classList.contains('is-active') && pane.dataset.platform.startsWith(key));
    clearInterval(cycle);
    if (!wasActive || !origin) show(key, wasActive ? 0 : origin);
    if (key === 'linux') {
      let alt = false;
      cycle = setInterval(() => { alt = !alt; show(alt ? 'linux-alt' : 'linux'); }, 3600);
    }
  };
  document.querySelectorAll('.port-card').forEach(card => {
    ['mouseenter', 'focus', 'click'].forEach(type => card.addEventListener(type, () => {
      const rect = card.getBoundingClientRect();
      select(card.dataset.platform, rect.top + rect.height / 2);
    }));
  });
  select('linux');
}

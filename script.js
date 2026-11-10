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

document.querySelector('.hero-demo')?.addEventListener('click', () => {
  document.getElementById('tab-haiku')?.click();
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
    if (entry.isIntersecting) {
      if (player) { player.play(); return; }
      if (container.dataset.loading) return;
      container.dataset.loading = '1';
      try {
        await loadPlayer();
        container.replaceChildren();
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
    } else if (player) {
      player.pause();
    }
  });
}, { threshold: 0.4 });
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
  const relations = dependencySection.querySelector('.dependency-relations');
  const selectPackage = id => {
    const selected = packages.get(id);
    if (!selected) return;
    selectedPackage = id;
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
    dependencySection.querySelector('.dependency-detail-version').textContent = selected.version + ' · ' + (selected.scope === 'runtime' ? 'Retained at runtime' : 'Build-time only');
    dependencySection.querySelector('.dependency-detail-license').textContent = 'Package license metadata: ' + (selected.licenses.join(', ') || 'not recorded in the SBOM');
    const renderList = (selector, ids) => {
      const list = dependencySection.querySelector(selector);
      list.replaceChildren();
      ids.sort((a, b) => packages.get(a).name.localeCompare(packages.get(b).name)).forEach(target => {
        const li = document.createElement('li');
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = packages.get(target).name;
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
    relations.hidden = false; reset.hidden = false;
    dependencySection.querySelector('.dependency-status').textContent = `${selected.name} ${selected.version}: ${outgoing.length} shown dependencies, used by ${incoming.length} shown packages.`;
  };
  dependencySection.querySelector('#dependency-detail-name').tabIndex = -1;
  dependencySection.querySelectorAll('[data-package]').forEach(node => {
    node.addEventListener('click', () => selectPackage(node.dataset.package));
    node.addEventListener('keydown', event => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault(); selectPackage(node.dataset.package);
      }
    });
  });
  const clearSelection = (focus = false) => {
    selectedPackage = null;
    dependencySection.querySelectorAll('.is-selected, .is-muted').forEach(node => node.classList.remove('is-selected', 'is-muted'));
    dependencySection.querySelectorAll('[data-package]').forEach(node => node.setAttribute('aria-pressed', 'false'));
    dependencySection.querySelector('#dependency-detail-name').textContent = 'Explore the graph';
    dependencySection.querySelector('.dependency-detail-version').textContent = 'Select any package.';
    dependencySection.querySelector('.dependency-detail-license').textContent = 'Select a node to see its version, package license metadata, and shown connections.';
    relations.hidden = true; reset.hidden = true;
    dependencySection.querySelector('.dependency-status').textContent = 'Showing all package connections.';
    if (focus) dependencySection.querySelector('#dependency-detail-name').focus({preventScroll:true});
  };
  reset.addEventListener('click', () => clearSelection(true));
  const scopeButtons = [...dependencySection.querySelectorAll('[data-scope]')];
  scopeButtons.forEach(button => button.addEventListener('click', () => {
    const scope = button.dataset.scope;
    if (enabledScopes.has(scope)) {
      if (enabledScopes.size === 1) return;
      enabledScopes.delete(scope);
    } else enabledScopes.add(scope);
    const view = enabledScopes.size === 2 ? 'both' : [...enabledScopes][0];
    activeGraph = graph.views[view];
    dependencySection.querySelectorAll('[data-view]').forEach(element => { element.hidden = element.dataset.view !== view; });
    scopeButtons.forEach(control => {
      const active = enabledScopes.has(control.dataset.scope);
      control.setAttribute('aria-pressed', String(active));
      control.disabled = active && enabledScopes.size === 1;
    });
    dependencySection.querySelector('.dependency-count').textContent = `${activeGraph.nodes.length} packages / ${activeGraph.edges.length} connections`;
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

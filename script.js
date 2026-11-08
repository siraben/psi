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
document.querySelectorAll('.terminal-demo[data-recording]').forEach(container => {
  const button = container.querySelector('.recording-poster');
  button?.addEventListener('click', async () => {
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    const label = button.querySelector('.play-recording');
    const originalLabel = label.innerHTML;
    label.textContent = 'Loading demo…';
    try {
      await loadPlayer();
      container.replaceChildren();
      const player = window.AsciinemaPlayer.create(container.dataset.recording, container, {
        autoplay: !container.closest('[role="tabpanel"]').hidden,
        preload: true,
        fit: 'width',
        theme: 'asciinema',
        idleTimeLimit: 2,
        terminalFontFamily: "'IBM Plex Mono', monospace",
      });
      demoPlayers.set(container, player);
    } catch {
      button.disabled = false;
      button.removeAttribute('aria-busy');
      label.innerHTML = originalLabel;
      document.querySelector('.copy-status').textContent = 'The player could not load. Try again or download the recording below.';
    }
  });
});
document.querySelector('.recording-tabs')?.addEventListener('tabselect', () => {
  demoPlayers.forEach((player, container) => {
    if (container.closest('[role="tabpanel"]').hidden) player.pause();
  });
});

// SVG and the accessible table are generated from the same CycloneDX records.
const dependencySection = document.getElementById('dependencies');
if (dependencySection) {
  const graph = JSON.parse(document.getElementById('dependency-data').textContent);
  const packages = new Map(graph.nodes.map(node => [node.id, node]));
  let activeGraph = graph.views.runtime;
  let selectedPackage = null;
  const enabledScopes = new Set(['runtime']);
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

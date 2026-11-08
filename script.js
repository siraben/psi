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
document.querySelectorAll('.terminal-demo[data-recording]').forEach(container => {
  container.querySelector('.recording-poster')?.addEventListener('click', () => {
    if (!window.AsciinemaPlayer) {
      document.querySelector('.copy-status').textContent = 'The player could not load. Use the download recording link below.';
      return;
    }
    container.replaceChildren();
    const player = window.AsciinemaPlayer.create(container.dataset.recording, container, {
      autoplay: true,
      preload: true,
      fit: 'width',
      theme: 'asciinema',
      idleTimeLimit: 2,
      terminalFontFamily: "'IBM Plex Mono', monospace",
    });
    demoPlayers.set(container, player);
  });
});
document.querySelector('.recording-tabs')?.addEventListener('tabselect', () => {
  demoPlayers.forEach((player, container) => {
    if (container.closest('[role="tabpanel"]').hidden) player.pause();
  });
});

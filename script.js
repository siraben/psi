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

const recordingButton = document.querySelector('.recording-poster');
document.querySelector('.hero-demo')?.addEventListener('click', () => {
  document.getElementById('tab-haiku')?.click();
});
recordingButton?.addEventListener('click', () => {
  if (!window.AsciinemaPlayer) {
    document.querySelector('.copy-status').textContent = 'The player could not load. Use the download recording link below.';
    return;
  }
  const container = document.getElementById('terminal-demo');
  container.replaceChildren();
  window.AsciinemaPlayer.create('assets/psi-terminal.cast', container, {
    autoplay: true,
    preload: true,
    fit: 'width',
    theme: 'asciinema',
    idleTimeLimit: 2,
    terminalFontFamily: "'IBM Plex Mono', monospace",
  });
});

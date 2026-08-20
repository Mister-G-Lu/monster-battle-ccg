import './style.css';
import { Engine } from './engine.js';
import { UI } from './ui.js';

const app = document.getElementById('app');
const loader = document.getElementById('loader');
const loaderMsg = document.getElementById('loader-msg');

async function boot() {
  const engine = new Engine();
  try {
    await engine.init((msg) => { loaderMsg.textContent = msg; });
  } catch (err) {
    loaderMsg.textContent = 'Failed to load engine: ' + err.message;
    console.error(err);
    return;
  }
  loader.style.display = 'none';
  app.style.display = 'block';
  const ui = new UI(app, engine);
  ui.render();
  // expose for debugging
  window.__engine = engine;
  window.__ui = ui;
}

boot();

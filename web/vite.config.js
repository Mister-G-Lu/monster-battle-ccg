import { defineConfig } from 'vite';

export default defineConfig({
  // A relative base lets this static build run from /web/dist/ on GitHub Pages
  // as well as from the Vite dev server, without hard-coding a host path.
  base: process.env.PAGES_BASE || './',
  server: {
    host: '0.0.0.0',
    port: 5173,
    // allow the sandbox preview host (e2b.app) to load the dev server
    allowedHosts: true,
  },
  preview: {
    host: '0.0.0.0',
    port: 4173,
    allowedHosts: true,
  },
  optimizeDeps: {
    // wasmoon ships a .wasm; let Vite serve it as an asset
    exclude: ['wasmoon'],
  },
});

import { defineConfig } from 'vite';

export default defineConfig({
  // Project GitHub Pages live at /monster-battle-ccg/. Local dev stays at /.
  base: process.env.GITHUB_PAGES ? '/monster-battle-ccg/' : '/',
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

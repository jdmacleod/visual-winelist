import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Proxy API calls to the FastAPI backend in development.
// In production, serve the built app behind nginx which routes /wines, /curate, etc.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/wines': 'http://localhost:8000',
      '/curate': 'http://localhost:8000',
      '/health': 'http://localhost:8000',
      '/scan': 'http://localhost:8000',
    },
  },
});

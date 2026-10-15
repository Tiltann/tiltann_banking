import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

// FiveM's NUI runtime serves this over its own local HTTP server, not from
// domain root, relative asset paths are required or the tablet loads blank.
export default defineConfig({
	base: './',
	plugins: [react(), tailwindcss()],
	build: {
		outDir: 'dist',
		emptyOutDir: true,
	},
});

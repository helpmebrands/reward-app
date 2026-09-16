import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'
import solid from 'vite-plugin-solid'

export default defineConfig({
  plugins: [
    solid(),
    VitePWA({
      // The worker owns reminder replay and push handling, which generateSW
      // cannot express, so it is hand-written and Workbox only injects the
      // precache manifest.
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',
      registerType: 'prompt',
      injectRegister: null,
      injectManifest: {
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
        // Phosphor ships a 3 MB SVG font per weight as a fallback for browsers
        // that predate woff2. Precaching them would triple the install size to
        // serve nobody — the woff2 files are what every current browser loads.
        globIgnores: ['**/Phosphor*.svg'],
      },
      devOptions: {
        enabled: true,
        type: 'module',
        navigateFallback: 'index.html',
      },
      manifest: {
        id: '/',
        name: 'Cardvantage',
        short_name: 'Cardvantage',
        description: 'Never leave a credit card benefit unclaimed.',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#12100a',
        theme_color: '#12100a',
        categories: ['finance', 'productivity'],
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          {
            src: '/icons/icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
        shortcuts: [
          {
            name: 'Expiring soon',
            short_name: 'Expiring',
            url: '/?filter=expiring',
            icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }],
          },
          {
            name: 'Add a card',
            short_name: 'Add card',
            url: '/cards/new',
            icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }],
          },
        ],
      },
    }),
  ],
  build: {
    target: 'es2022',
    sourcemap: true,
  },
  server: {
    port: 5173,
    host: true,
  },
})

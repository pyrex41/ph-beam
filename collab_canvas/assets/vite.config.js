import { defineConfig } from 'vite';
import path from 'path';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';

// Custom plugin to force eventemitter3 to use CommonJS version
const forceCommonJS = () => ({
  name: 'force-commonjs',
  resolveId(source, importer) {
    if (source === 'eventemitter3' || source.includes('eventemitter3/index.mjs')) {
      return path.resolve(__dirname, 'node_modules/eventemitter3/index.js');
    }
    return null;
  }
});

export default defineConfig({
  plugins: [
    forceCommonJS(),
    commonjs({
      include: [/node_modules/, /vendor/],
      requireReturnsDefault: 'preferred',
      defaultIsModuleExports: true,
      transformMixedEsModules: true,
      esmExternals: true
    }),
    nodeResolve({
      browser: true,
      preferBuiltins: false,
      extensions: ['.mjs', '.js', '.json', '.node']
    })
  ],
  // Optimize dependencies to avoid mixed ESM/CommonJS issues
  optimizeDeps: {
    include: ['pixi.js', 'eventemitter3', 'phoenix', 'phoenix_html', 'phoenix_live_view'],
    esbuildOptions: {
      target: 'esnext'
    }
  },
  // Build configuration
  build: {
    // Force optimization during build as well
    commonjsOptions: {
      include: /node_modules/,
      transformMixedEsModules: true
    },
    // Output directory relative to this config file
    outDir: '../priv/static/assets',
    // Don't clear output directory - Tailwind CSS also outputs here
    emptyOutDir: false,
    // Generate manifest for Phoenix integration
    manifest: true,
    rollupOptions: {
      input: {
        app: path.resolve(__dirname, 'js/app.js')
      },
      output: {
        // Output structure
        entryFileNames: 'js/[name].js',
        chunkFileNames: 'js/[name]-[hash].js',
        assetFileNames: '[ext]/[name]-[hash].[ext]'
      }
    }
  },
  // Public directory for static assets
  publicDir: 'static',
  // Server configuration for development
  server: {
    // Port for Vite dev server
    port: 5173,
    // Enable CORS for Phoenix
    cors: true,
    // Watch for changes
    watch: {
      usePolling: true
    }
  },
  // Resolve configuration
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.')
    }
  }
});

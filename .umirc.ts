import { defineConfig } from '@umijs/max';
const CompressionPlugin = require('compression-webpack-plugin');

const baseUrl = process.env.QlBaseUrl || '/';
export default defineConfig({
  hash: true,
  jsMinifier: 'terser',
  antd: {},
  locale: {
    antd: true,
    title: true,
    baseNavigator: true,
  },
  outputPath: 'static/dist',
  fastRefresh: true,
  favicons: [`https://qn.whyour.cn/favicon.svg`],
  publicPath: process.env.NODE_ENV === 'production' ? './' : '/',
  proxy: {
    [`${baseUrl}api/update`]: {
      target: 'http://127.0.0.1:5300/',
      changeOrigin: true,
      pathRewrite: { [`^${baseUrl}api/update`]: '/api' },
    },
    [`${baseUrl}api/public`]: {
      target: 'http://127.0.0.1:5400/',
      changeOrigin: true,
      pathRewrite: { [`^${baseUrl}api/public`]: '/api' },
    },
    [`${baseUrl}api`]: {
      target: 'http://127.0.0.1:5600/',
      changeOrigin: true,
      ws: true,
      pathRewrite: { [`^${baseUrl}api`]: '/api' },
    },
  },
  chainWebpack: ((config: any) => {
    config.plugin('compression-webpack-plugin').use(
      new CompressionPlugin({
        algorithm: 'gzip',
        test: new RegExp('\\.(js|css)$'),
        threshold: 10240,
        minRatio: 0.6,
      }),
    );
  }) as any,
  headScripts: [`./api/env.js`],
  copy: [
    {
      from: 'node_modules/monaco-editor/min/vs',
      to: 'static/dist/monaco-editor/min/vs',
    },
  ],
  npmClient: 'pnpm',
});

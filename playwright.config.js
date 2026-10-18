const {defineConfig} = require('@playwright/test');
module.exports = defineConfig({
  testDir: './tests/web',
  timeout: 30000,
  use: {baseURL: 'http://127.0.0.1:8765/crisperplayer/', headless: true},
  webServer: {command: 'node scripts/serve_site.js', url: 'http://127.0.0.1:8765/crisperplayer/', reuseExistingServer: false},
});

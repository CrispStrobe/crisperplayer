const {test: base, expect} = require('@playwright/test');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const test = base.extend({
  context: async ({context, browserName, playwright, baseURL}, use) => {
    if (browserName !== 'webkit') { await use(context); return; }
    // WebKit private contexts cannot persist Blob/File values in IndexedDB.
    // Use a fresh regular profile per test, never the user's Safari profile.
    // https://github.com/microsoft/playwright/issues/42795
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'crisper-webkit-'));
    let regular;
    try {
      regular = await playwright.webkit.launchPersistentContext(directory, {
        headless: true, acceptDownloads: true, baseURL,
      });
      await use(regular);
    } finally {
      if (regular) await regular.close();
      await fs.rm(directory, {recursive:true, force:true});
    }
  },
});
module.exports = {test, expect};

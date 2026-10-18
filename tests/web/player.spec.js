const {test, expect} = require('@playwright/test');
function wav(name) {
  const samples = 8000 * 60, buffer = Buffer.alloc(44 + samples * 2);
  buffer.write('RIFF'); buffer.writeUInt32LE(buffer.length - 8, 4); buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16, 16); buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(8000, 24); buffer.writeUInt32LE(16000, 28); buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36); buffer.writeUInt32LE(samples * 2, 40);
  return {name, mimeType: 'audio/wav', buffer};
}
async function add(page, files = [wav('Chapter 10.wav'), wav('Chapter 2.wav')]) {
  await expect(page.locator('#files')).toBeEnabled();
  await page.locator('#files').setInputFiles(files);
  await expect(page.locator('#play')).toBeEnabled();
}
test('local audio playback, natural order, bookmarks and persistence without uploads', async ({page}) => {
  const errors = [], uploads = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', r => { if (!['GET', 'HEAD'].includes(r.method())) uploads.push(r.url()); });
  await page.goto('./'); await add(page);
  await expect(page.locator('#track-name')).toHaveText('Track 1 of 2 · Chapter 2.wav');
  await page.locator('#play').click();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBeGreaterThan(0.1);
  await page.locator('#play').click();
  await expect(page.locator('#play')).toHaveText('Play');
  await page.locator('#seek').fill('15');
  await page.locator('#speed').selectOption('1.5');
  await page.locator('#volume').fill('0.4');
  await page.locator('#bookmark-label').fill('Find this passage');
  await page.locator('#bookmark').click();
  await expect(page.locator('#bookmarks')).toContainText('Find this passage · Track 1, 00:15');
  await page.locator('#next').click();
  await expect(page.locator('#track-name')).toHaveText('Track 2 of 2 · Chapter 10.wav');
  await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.playbackRate)).toBe(1.5);
  await page.locator('#bookmarks button').click();
  await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(15);
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(15);
  await expect.poll(() => page.locator('#audio').evaluate(a => a.volume)).toBe(0.4);
  await expect(page.locator('#speed')).toHaveValue('1.5');
  await expect(page.locator('#bookmarks')).toContainText('Find this passage');
  await page.locator('#search').fill('absent'); await expect(page.locator('#books button')).toHaveCount(0);
  await page.locator('#search').fill('chapter'); await expect(page.locator('#books button')).toHaveCount(1);
  const download = page.waitForEvent('download'); await page.locator('#export').click();
  const artifact = await download;
  const stream = await artifact.createReadStream(); const chunks = []; for await (const part of stream) chunks.push(part);
  const data = JSON.parse(Buffer.concat(chunks).toString());
  expect(data.position).toBe(15); expect(data.bookmarks).toHaveLength(1); expect(data).not.toHaveProperty('blob');
  page.once('dialog', dialog => dialog.accept()); await page.locator('#delete').click();
  await expect(page.locator('#books button')).toHaveCount(0);
  await page.reload(); await expect(page.locator('#files')).toBeEnabled();
  await expect(page.locator('#books button')).toHaveCount(0);
  expect(uploads).toEqual([]); expect(errors).toEqual([]);
});
test('independent books do not inherit the previous track position', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book A.wav')]);
  await page.locator('#seek').fill('20');
  await add(page, [wav('Book B.wav')]);
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(0);
  await page.locator('#books button', {hasText:'Book A'}).click();
  await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(20);
});
test('mobile layout, literal filenames, About and version-independent downloads', async ({page}) => {
  await page.setViewportSize({width:320, height:568}); await page.goto('./');
  await add(page, [wav('<img src=x onerror=alert(1)> a very long audiobook title that must fit the controls.wav')]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
  await expect(page.locator('#title img')).toHaveCount(0);
  await page.locator('#play').scrollIntoViewIfNeeded(); await expect(page.locator('#play')).toBeInViewport();
  await page.locator('#about-open').click(); await expect(page.locator('#about')).toBeVisible();
  await expect(page.locator('#about')).toContainText('Christian Ströbele');
  await expect(page.locator('#about')).toContainText('Licenses and source');
  await page.locator('#about-close').click();
  await expect(page.getByRole('link', {name:'Windows x64', exact:true})).toHaveAttribute('href', /releases\/latest\/download\/CrisperPlayer-windows-x64.zip$/);
});

test('editable timecode validates input and supports Enter, touch stepping and mute', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Test.wav')]);
  await page.locator('#volume').fill('0.35'); await page.locator('#mute').click();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.volume)).toBe(0);
  await page.locator('#mute').click(); await expect.poll(() => page.locator('#audio').evaluate(a => a.volume)).toBe(0.35);
  await page.locator('#elapsed').click(); await page.locator('#jump-input').fill('1:99');
  await page.locator('#jump-input').press('Enter'); await expect(page.locator('#jump-error')).toContainText('below 60');
  await page.locator('#jump-input').fill('00:10'); await page.locator('#jump-forward').click();
  await page.locator('#jump-input').press('Enter'); await expect(page.locator('#jump')).not.toBeVisible();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(40);
  await page.locator('#elapsed').click(); await page.locator('#jump-input').fill('00:05'); await page.locator('#jump-cancel').click();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(40);
});

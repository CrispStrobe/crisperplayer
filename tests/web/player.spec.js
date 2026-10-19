const {test, expect} = require('./fixtures');
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
  await page.locator('#bookmarks .bookmark-go').click();
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

async function exportProgress(page) {
  const waiting = page.waitForEvent('download');
  await page.locator('#export').click();
  const stream = await (await waiting).createReadStream(), chunks = [];
  for await (const part of stream) chunks.push(part);
  return JSON.parse(Buffer.concat(chunks).toString());
}
async function chooseBackup(page, data) {
  await page.locator('#restore-file').setInputFiles({name:'progress.json',mimeType:'application/json',buffer:Buffer.from(typeof data === 'string' ? data : JSON.stringify(data))});
}
async function bookmark(page, label) {
  await page.locator('#bookmark-label').fill(label); await page.locator('#bookmark').click();
  await expect(page.locator('#bookmarks')).toContainText(label);
}
async function removeBook(page) {
  page.once('dialog', dialog => dialog.accept()); await page.locator('#delete').click();
  await expect(page.locator('#books button')).toHaveCount(0);
}

test('browser backup restores a reimported book, merges bookmarks and preserves mute restoration', async ({page}) => {
  const uploads = []; page.on('request', r => {if (!['GET','HEAD'].includes(r.method())) uploads.push(r.url());});
  await page.goto('./'); await add(page);
  await page.locator('#seek').fill('15'); await bookmark(page, 'First passage');
  await page.locator('#next').click(); await expect(page.locator('#play')).toBeEnabled();
  await page.locator('#seek').fill('25'); await bookmark(page, 'Second passage');
  await page.locator('#speed').selectOption('1.5'); await page.locator('#volume').fill('0.35'); await page.locator('#mute').click();
  const backup = await exportProgress(page);
  expect(backup.schema).toBe(2); expect(backup.files).toHaveLength(2); expect(backup.position).toBe(25);
  expect(backup.files[0].fingerprint).toMatch(/^[a-f0-9]{64}$/);
  await removeBook(page); await add(page);
  await page.locator('#seek').fill('9'); await bookmark(page, 'Keep this bookmark');
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  await expect(page.locator('#restore-match')).toContainText('2 tracks match');
  await expect(page.locator('#restore-bookmarks')).toHaveText('Add 2 bookmarks. Keep all 1 existing bookmarks.');
  expect(await page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  await page.locator('#restore-cancel').click();
  expect(await page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(1);
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  await page.locator('#restore-confirm').click(); await expect(page.locator('#play')).toBeEnabled();
  await expect(page.locator('#track-name')).toContainText('Track 2 of 2');
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(25);
  await expect.poll(() => page.locator('#audio').evaluate(a => a.volume)).toBe(0);
  await expect(page.locator('#speed')).toHaveValue('1.5');
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(3);
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(25);
  await page.locator('#mute').click(); await expect.poll(() => page.locator('#audio').evaluate(a => a.volume)).toBe(.35);
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  await expect(page.locator('#restore-bookmarks')).toHaveText('Add 0 bookmarks. Keep all 3 existing bookmarks.');
  await page.locator('#restore-confirm').click(); await expect(page.locator('#play')).toBeEnabled();
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(3);
  expect(uploads).toEqual([]);
});

test('wrong audio, malformed backup and out-of-range bookmarks cannot change progress', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book.wav')]);
  await page.locator('#seek').fill('20'); const backup = await exportProgress(page);
  await removeBook(page);
  const other = wav('Book.wav'); other.buffer[100] = 1;
  await add(page, [other]); await page.locator('#seek').fill('9');
  await chooseBackup(page, backup); await expect(page.locator('#status')).toContainText('audio does not match');
  await expect(page.locator('#restore-preview')).not.toBeVisible();
  expect(await page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  const matching = await exportProgress(page);
  for (const [data, error] of [
    ['{oops', 'not valid JSON'],
    [{...matching, position:-1}, 'Invalid playback position'],
    [{...matching, schema:99}, 'browser progress backup'],
    [{...matching, bookmarks:[{track:0, seconds:90, label:'Invalid'}]}, 'exceeds the duration'],
    [{...matching, files:[{size:123,fingerprint:'invalid'}]}, 'Invalid audio fingerprints'],
  ]) {
    await expect(page.locator('#restore')).toBeEnabled(); await chooseBackup(page, data);
    await expect(page.locator('#status')).toContainText(error);
    await expect(page.locator('#restore-preview')).not.toBeVisible();
    expect(await page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  }
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
});

test('legacy backups require review, render literal labels and support arbitrary valid speed', async ({page}) => {
  await page.setViewportSize({width:320,height:568});
  await page.goto('./'); await add(page, [wav('Book.wav')]);
  const data = {schema:1,browserPlayer:true,title:'<img src=x onerror=alert(1)>',names:['Book.wav'],track:0,position:12,speed:1.3,bookmarks:[{track:0,seconds:8,label:'<img src=x onerror=alert(1)>'}]};
  await chooseBackup(page, data); await expect(page.locator('#restore-preview')).toBeVisible();
  await expect(page.locator('#restore-match')).toContainText('only track names and order');
  await expect(page.locator('#restore-preview img')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
  await page.locator('#restore-confirm').click(); await expect(page.locator('#play')).toBeEnabled();
  await expect(page.locator('#speed')).toHaveValue('1.3');
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(12);
  await expect(page.locator('#bookmarks img')).toHaveCount(0);
  await expect(page.locator('#bookmarks')).toContainText(data.bookmarks[0].label);
});

test('bookmark labels can be edited, canceled, deleted and persisted during playback', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book.wav')]);
  await page.locator('#seek').fill('5'); await bookmark(page, 'Original label');
  await page.locator('#play').click();
  await page.getByRole('button',{name:'Edit bookmark Original label',exact:true}).click();
  await page.locator('#bookmark-edit-label').fill('Canceled'); await page.locator('#bookmark-edit-cancel').click();
  await expect(page.locator('#bookmarks')).toContainText('Original label');
  await page.getByRole('button',{name:'Edit bookmark Original label',exact:true}).click();
  await page.locator('#bookmark-edit-label').fill('Changed <b>label</b>'); await page.locator('#bookmark-edit-label').press('Enter');
  await expect(page.locator('#bookmark-editor')).not.toBeVisible();
  await expect(page.locator('#bookmarks')).toContainText('Changed <b>label</b>');
  expect(await page.locator('#audio').evaluate(a => a.paused)).toBe(false);
  await page.locator('#play').click(); await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await page.getByRole('button',{name:'Delete bookmark Changed <b>label</b>',exact:true}).click();
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(0);
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(0);
});

test('failed storage write rolls back a restore and keeps the current library', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book.wav')]);
  await page.locator('#seek').fill('30'); await bookmark(page, 'From backup'); const backup = await exportProgress(page);
  await removeBook(page); await add(page, [wav('Book.wav')]);
  await page.locator('#seek').fill('9'); await bookmark(page, 'Keep me');
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  await page.evaluate(() => {
    const put = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function(value, ...args) {
      if (this.name === 'books' && value.position === 30) {
        IDBObjectStore.prototype.put = put;
        throw new DOMException('Test storage full', 'QuotaExceededError');
      }
      return put.call(this,value,...args);
    };
  });
  await page.locator('#restore-confirm').click(); await expect(page.locator('#restore-error')).toContainText('Test storage full');
  await page.locator('#restore-cancel').click();
  await expect(page.locator('#bookmarks .bookmark-go')).toHaveCount(1);
  await expect(page.locator('#bookmarks')).toContainText('Keep me');
  expect(await page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(9);
  await expect(page.locator('#bookmarks')).toContainText('Keep me');
});

test('switching books during restore preparation cannot overwrite the new selection', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book A.wav')]);
  await page.locator('#seek').fill('20'); const backup = await exportProgress(page);
  await add(page, [wav('Book B.wav')]); await page.locator('#seek').fill('7');
  await page.locator('#books button',{hasText:'Book A'}).click(); await expect(page.locator('#play')).toBeEnabled();
  await page.evaluate(() => {
    const verify = ProgressBackup.verify;
    ProgressBackup.verify = async (...args) => { await new Promise(resolve => setTimeout(resolve,300)); return verify(...args); };
  });
  await chooseBackup(page, backup); await page.locator('#books button',{hasText:'Book B'}).click();
  await expect(page.locator('#track-name')).toContainText('Book B.wav');
  await expect(page.locator('#status')).toContainText('selected book changed');
  await expect(page.locator('#restore-preview')).not.toBeVisible();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(7);
});

test('a decoder reporting zero on its first seek cannot erase restored progress', async ({page}) => {
  await page.goto('./'); await add(page, [wav('Book.wav')]);
  await page.locator('#seek').fill('20'); const backup = await exportProgress(page);
  await page.locator('#seek').fill('9'); await chooseBackup(page, backup);
  await expect(page.locator('#restore-preview')).toBeVisible();
  await page.evaluate(() => {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'currentTime');
    let first = true;
    Object.defineProperty(audio, 'currentTime', {
      get() {return descriptor.get.call(this);},
      set(value) {if (first && value === 20) {first = false; value = 0;} descriptor.set.call(this,value);},
    });
  });
  await page.locator('#restore-confirm').click(); await expect(page.locator('#restore-preview')).not.toBeVisible();
  await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(20);
  await page.reload(); await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(20);
});

test('slow checkpoint disables controls before a track change and seeks the new track', async ({page}) => {
  await page.goto('./'); await add(page);
  await page.evaluate(() => {
    const original = saveBook; let delay = true;
    saveBook = async book => {if (delay) {delay = false; await new Promise(resolve => setTimeout(resolve,500));} return original(book);};
  });
  await page.locator('#next').click();
  await expect(page.locator('#play')).toBeDisabled(); await expect(page.locator('#seek')).toBeDisabled();
  await page.locator('#seek').fill('25');
  await expect(page.locator('#track-name')).toContainText('Track 2 of 2');
  await bookmark(page, 'New track');
  await expect(page.locator('#bookmarks')).toContainText('New track · Track 2, 00:25');
  const backup = await exportProgress(page);
  expect(backup.position).toBe(25); expect(backup.track).toBe(1);
});

test('preview cancellation keeps playing and restoring a track end stays paused', async ({page}) => {
  await page.goto('./'); await add(page);
  const backup = {schema:1,browserPlayer:true,title:'End position',names:['Chapter 2.wav','Chapter 10.wav'],track:0,position:60,speed:1,bookmarks:[]};
  await page.locator('#seek').fill('3'); await page.locator('#play').click();
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  expect(await page.locator('#audio').evaluate(a => a.paused)).toBe(false);
  await page.locator('#restore-cancel').click();
  expect(await page.locator('#audio').evaluate(a => a.paused)).toBe(false);
  await chooseBackup(page, backup); await expect(page.locator('#restore-preview')).toBeVisible();
  await page.locator('#restore-confirm').click(); await expect(page.locator('#restore-preview')).not.toBeVisible();
  await expect(page.locator('#play')).toBeEnabled();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBe(60);
  await expect(page.locator('#track-name')).toContainText('Track 1 of 2');
  expect(await page.locator('#audio').evaluate(a => a.paused)).toBe(true);
});

test('natural playback completion still continues to the next track', async ({page}) => {
  await page.goto('./'); await add(page);
  await page.locator('#play').click();
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBeGreaterThan(.1);
  await page.locator('#seek').fill('59.7');
  await expect(page.locator('#track-name')).toContainText('Track 2 of 2', {timeout:10000});
  await expect(page.locator('#play')).toHaveText('Pause');
  await expect.poll(() => page.locator('#audio').evaluate(a => a.currentTime)).toBeGreaterThan(.1);
});

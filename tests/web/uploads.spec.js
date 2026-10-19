const {test, expect} = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
  '../../lib/services/transfer/upload_page.dart'), 'utf8');
const html = source.match(/r'''([\s\S]*)''';/)[1];

async function openTransfer(page, handle, fragment = '') {
  await page.route('**/transfer-test/', route => route.fulfill({
    contentType: 'text/html', body: html,
  }));
  await page.route('**/upload?*', handle);
  await page.route('**/import?*', handle);
  await page.goto('http://127.0.0.1:8765/transfer-test/' + fragment);
}

test('browser uploads selected bytes with authentication then imports one book', async ({page}) => {
  const requests = [];
  await openTransfer(page, async route => {
    const request = route.request();
    requests.push({url: new URL(request.url()), method: request.method(),
      auth: request.headers()['authorization'], body: request.postDataBuffer()});
    await route.fulfill({contentType: 'application/json', body: JSON.stringify(
      request.method() === 'PUT' ? {uploaded: true} : {imported: true})});
  });
  await page.locator('#code').fill('temporary-access-code');
  await page.locator('#title').fill('My audiobook');
  await page.locator('#files').setInputFiles([
    {name: 'Track 2.mp3', mimeType: 'audio/mpeg', buffer: Buffer.from('track-two')},
    {name: 'Track 10.mp3', mimeType: 'audio/mpeg', buffer: Buffer.from('track-ten')},
  ]);
  await page.getByRole('button', {name: 'Upload and import book'}).click();
  await expect(page.getByRole('status')).toContainText('Book imported');
  expect(requests.map(r => r.method)).toEqual(['PUT', 'PUT', 'POST']);
  expect(requests.every(r => r.auth === 'Bearer temporary-access-code')).toBe(true);
  expect(requests[0].url.searchParams.get('name')).toBe('Track 2.mp3');
  expect(requests[0].body.toString()).toBe('track-two');
  expect(requests[1].body.toString()).toBe('track-ten');
  expect(requests[2].url.searchParams.get('title')).toBe('My audiobook');
  expect(requests.every(r => !r.url.href.includes('temporary-access-code'))).toBe(true);
  await expect(page.locator('#title')).toHaveValue('');
});

test('browser reports rejected credentials and enables retry without importing', async ({page}) => {
  let imports = 0;
  await openTransfer(page, async route => {
    if (route.request().method() === 'POST') imports++;
    await route.fulfill({status: 401, contentType: 'application/json',
      body: JSON.stringify({error: 'Enter the access code shown in the app'})});
  });
  await page.locator('#code').fill('wrong');
  await page.locator('#files').setInputFiles({name: 'Book.mp3',
    mimeType: 'audio/mpeg', buffer: Buffer.from('audio')});
  const button = page.getByRole('button', {name: 'Upload and import book'});
  await button.click();
  await expect(page.getByRole('status')).toContainText('Enter the access code');
  await expect(button).toBeEnabled();
  expect(imports).toBe(0);
});

test('duplicate names from different source folders are rejected before transfer', async ({page}) => {
  let requests = 0;
  await openTransfer(page, async route => {requests++; await route.abort();});
  await page.locator('#code').fill('code');
  await page.locator('#files').setInputFiles([
    {name: 'Track.mp3', mimeType: 'audio/mpeg', buffer: Buffer.from('one')},
    {name: 'Track.mp3', mimeType: 'audio/mpeg', buffer: Buffer.from('two')},
  ]);
  await page.getByRole('button', {name: 'Upload and import book'}).click();
  await expect(page.getByRole('status')).toContainText('unique names');
  expect(requests).toBe(0);
});


test('pairing link prefills the code and removes its fragment from history', async ({page}) => {
  const code = 'ab'.repeat(20);
  await openTransfer(page, route => route.abort(), '#code=' + code);
  await expect(page.locator('#code')).toHaveValue(code);
  expect(new URL(page.url()).hash).toBe('');
});

test('large upload resumes after a committed chunk loses its acknowledgment', async ({page}) => {
  const size = 8 * 1024 * 1024 + 3;
  const payload = Buffer.alloc(size, 67);
  let offset = 0, begins = 0, lost = false;
  const chunks = [];
  await openTransfer(page, async route => {
    const request = route.request(), url = new URL(request.url());
    let result = {};
    if (url.pathname === '/upload' && request.method() === 'POST') {
      begins++; result = {id: 'owned-upload', offset: 0, complete: false};
    } else if (url.pathname === '/upload' && request.method() === 'GET') {
      result = {id: 'owned-upload', offset, complete: offset === size};
    } else if (request.method() === 'PATCH') {
      expect(Number(url.searchParams.get('offset'))).toBe(offset);
      const bytes = request.postDataBuffer();chunks.push(bytes);offset += bytes.length;
      if (!lost) {
        lost = true;
        await route.fulfill({status: 503, contentType: 'application/json', body: JSON.stringify({error: 'Acknowledgment lost'})});return;
      }
      result = {offset, complete: offset === size};
    } else result = {imported: true};
    await route.fulfill({contentType: 'application/json', body: JSON.stringify(result)});
  });
  await page.locator('#code').fill('test-code');
  await page.locator('#files').setInputFiles({name: 'Large.wav', mimeType: 'audio/wav', buffer: payload});
  const button = page.getByRole('button', {name: 'Upload and import book'});
  await button.click();
  await expect(page.getByRole('status')).toContainText('Acknowledgment lost');
  await expect(button).toBeEnabled();
  await button.click();
  await expect(page.getByRole('status')).toContainText('Book imported');
  expect(begins).toBe(1);
  expect(chunks.map(c => c.length)).toEqual([8 * 1024 * 1024, 3]);
  expect(Buffer.concat(chunks).equals(payload)).toBe(true);
});

test('lost import acknowledgment checks committed operation before retrying audio', async ({page}) => {
  let uploads = 0, imports = 0, operation;
  await openTransfer(page, async route => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() === 'PUT') {uploads++;}
    else if (request.method() === 'POST') {
      imports++;operation = url.searchParams.get('operation');
      await route.abort('failed');return;
    } else expect(url.searchParams.get('operation')).toBe(operation);
    await route.fulfill({contentType: 'application/json', body: JSON.stringify({imported: true})});
  });
  await page.locator('#code').fill('test-code');
  await page.locator('#files').setInputFiles({name: 'Book.mp3', mimeType: 'audio/mpeg', buffer: Buffer.from('audio')});
  const button = page.getByRole('button', {name: 'Upload and import book'});
  await button.click();
  await expect(page.getByRole('status')).toContainText('Retry');
  await expect(button).toBeEnabled();
  await button.click();
  await expect(page.getByRole('status')).toContainText('Book imported');
  expect(uploads).toBe(1);expect(imports).toBe(1);
});

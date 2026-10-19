const {test, expect} = require('@playwright/test');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
  '../../lib/services/transfer/upload_page.dart'), 'utf8');
const html = source.match(/r'''([\s\S]*)''';/)[1];

async function openTransfer(page, handle) {
  await page.route('**/transfer-test/', route => route.fulfill({
    contentType: 'text/html', body: html,
  }));
  await page.route('**/upload?*', handle);
  await page.route('**/import?*', handle);
  await page.goto('http://127.0.0.1:8765/transfer-test/');
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

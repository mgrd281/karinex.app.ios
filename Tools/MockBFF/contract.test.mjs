// Contract tests: the mock answers exactly the shapes of docs/BFF_CONTRACT.md that
// Packages/Backend decodes.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { start } from './server.mjs';

process.env.MOCK_BFF_QUIET = '1';
let server;
let base;

before(async () => {
  server = await start(0);
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const auth = (token = 'customer') => ({ Authorization: `Bearer ${token}` });

test('config is public and supports ETag', async () => {
  const first = await fetch(`${base}/v1/app/config`);
  assert.equal(first.status, 200);
  const body = await first.json();
  assert.deepEqual(body.supportHours, { timeZone: 'Europe/Berlin', weekdays: [1, 2, 3, 4, 5, 6, 7], opensAt: '06:00', closesAt: '23:00' });
  assert.equal(body.supportEmail, 'kundenservice@karinex.de');
  const etag = first.headers.get('etag');
  assert.ok(etag);
  const second = await fetch(`${base}/v1/app/config`, { headers: { 'If-None-Match': etag } });
  assert.equal(second.status, 304);
});

test('orders need a token', async () => {
  const response = await fetch(`${base}/v1/app/orders`);
  assert.equal(response.status, 401);
  const body = await response.json();
  assert.deepEqual(Object.keys(body).sort(), ['code', 'message', 'requestId']);
});

test('orders list delivery states', async () => {
  const response = await fetch(`${base}/v1/app/orders`, { headers: auth() });
  const { orders } = await response.json();
  assert.ok(orders.length > 0);
  for (const order of orders) {
    assert.match(order.orderId, /^[0-9]+$/);
    assert.ok(['pending', 'delivered', 'shipped'].includes(order.deliveryStatus));
    assert.equal(typeof order.hasLicenses, 'boolean');
  }
});

test('licenses: delivered, pending and foreign orders', async () => {
  const delivered = await fetch(`${base}/v1/app/orders/1001/licenses`, { headers: auth() });
  assert.equal(delivered.status, 200);
  const { licenses } = await delivered.json();
  assert.equal(licenses[0].lineItemId, '20001');
  assert.equal(typeof licenses[0].key, 'string');

  const pending = await fetch(`${base}/v1/app/orders/1002/licenses`, { headers: auth() });
  assert.equal(pending.status, 202);

  const foreign = await fetch(`${base}/v1/app/orders/9999/licenses`, { headers: auth() });
  assert.equal(foreign.status, 403);
});

test('invoice links are https and short-lived', async () => {
  const response = await fetch(`${base}/v1/app/orders/1001/invoice`, { headers: auth() });
  const body = await response.json();
  assert.match(body.url, /^https:\/\//);
  assert.ok(Date.parse(body.expiresAt) > Date.now());
  const missing = await fetch(`${base}/v1/app/orders/1002/invoice`, { headers: auth() });
  assert.equal(missing.status, 404);
});

test('account deletion is idempotent', async () => {
  const options = { method: 'POST', headers: { ...auth('deleter'), 'Content-Type': 'application/json' }, body: '{"confirm":true}' };
  const first = await (await fetch(`${base}/v1/app/account/delete`, options)).json();
  const second = await fetch(`${base}/v1/app/account/delete`, options);
  assert.equal(second.status, 202);
  assert.equal((await second.json()).requestId, first.requestId);
  const unconfirmed = await fetch(`${base}/v1/app/account/delete`, { ...options, body: '{}' });
  assert.equal(unconfirmed.status, 400);
});

test('devices register and unregister', async () => {
  const body = JSON.stringify({ apnsToken: 'a1b2c3', locale: 'de', country: 'DE', consent: { orderUpdates: true, deals: false } });
  const created = await fetch(`${base}/v1/app/devices`, { method: 'POST', headers: { ...auth(), 'Content-Type': 'application/json' }, body });
  assert.equal(created.status, 201);
  const removed = await fetch(`${base}/v1/app/devices/a1b2c3`, { method: 'DELETE', headers: auth() });
  assert.equal(removed.status, 204);
});

test('throttling carries Retry-After', async () => {
  const response = await fetch(`${base}/v1/app/orders`, { headers: auth('throttled') });
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '2');
});

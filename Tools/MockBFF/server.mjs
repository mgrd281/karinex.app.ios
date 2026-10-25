// Mock of the KARINEX app BFF for local development and contract tests.
//
//   node server.mjs                 # http://localhost:8787
//   PORT=9000 node server.mjs
//
// Any non-empty bearer token is accepted, except these, which select a scenario:
//   expired     every authenticated call answers 401
//   throttled   every authenticated call answers 429 with Retry-After: 2
//   empty       no orders
//
// The server never logs tokens, keys or bodies; only method, route, status and request ID.

import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import * as fixtures from './fixtures.mjs';

const configETag = `"${Buffer.from(JSON.stringify(fixtures.config)).toString('base64url').slice(0, 16)}"`;
const deletionRequests = new Map();

function send(response, status, body, headers = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  response.writeHead(status, {
    ...(payload ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
    'Cache-Control': 'no-store',
    ...headers,
  });
  response.end(payload);
}

function error(response, status, code, message, requestId, headers = {}) {
  send(response, status, { code, message, requestId }, headers);
}

function bearer(request) {
  const header = request.headers.authorization ?? '';
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1].trim() : '';
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16 * 1024) throw new Error('too_large');
    chunks.push(chunk);
  }
  if (chunks.length === 0) return undefined;
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

/** Answers one request. Exported for the tests. */
export async function handle(request, response) {
  const requestId = `req_${randomUUID().slice(0, 8)}`;
  const url = new URL(request.url, 'http://localhost');
  const path = url.pathname.replace(/\/+$/, '');
  const method = request.method ?? 'GET';
  response.on('finish', () => {
    if (process.env.MOCK_BFF_QUIET !== '1') {
      console.log(`${method} ${path} ${response.statusCode} ${requestId}`);
    }
  });

  if (method === 'GET' && path === '/v1/app/config') {
    if (request.headers['if-none-match'] === configETag) {
      return send(response, 304, undefined, { ETag: configETag });
    }
    return send(response, 200, fixtures.config, { ETag: configETag });
  }

  if (!path.startsWith('/v1/app/')) {
    return error(response, 404, 'not_found', 'Unknown route.', requestId);
  }

  const token = bearer(request);
  if (!token || token === 'expired') {
    return error(response, 401, 'invalid_token', 'The access token is missing or expired.', requestId);
  }
  if (token === 'throttled') {
    return error(response, 429, 'rate_limited', 'Too many requests.', requestId, { 'Retry-After': '2' });
  }

  if (method === 'GET' && path === '/v1/app/orders') {
    return send(response, 200, { orders: token === 'empty' ? [] : fixtures.orders });
  }

  const orderRoute = /^\/v1\/app\/orders\/([0-9]{1,20})\/(licenses|invoice)$/.exec(path);
  if (method === 'GET' && orderRoute) {
    const [, orderId, resource] = orderRoute;
    if (fixtures.foreignOrders.has(orderId)) {
      return error(response, 403, 'order_not_owned', 'The order does not belong to this customer.', requestId);
    }
    const order = fixtures.orders.find((candidate) => candidate.orderId === orderId);
    if (!order) {
      return error(response, 403, 'order_not_owned', 'The order does not belong to this customer.', requestId);
    }
    if (resource === 'licenses') {
      if (order.deliveryStatus === 'pending') return send(response, 202, undefined);
      return send(response, 200, { licenses: fixtures.licenses[orderId] ?? [] });
    }
    if (!order.hasInvoice) {
      return error(response, 404, 'invoice_not_ready', 'There is no invoice yet.', requestId);
    }
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    return send(response, 200, { url: `https://example.com/invoices/${orderId}.pdf`, expiresAt });
  }

  if (method === 'POST' && path === '/v1/app/account/delete') {
    let body;
    try {
      body = await readJSON(request);
    } catch {
      return error(response, 400, 'invalid_body', 'The body is not valid JSON.', requestId);
    }
    if (body?.confirm !== true) {
      return error(response, 400, 'confirmation_required', 'Send {"confirm": true}.', requestId);
    }
    if (!deletionRequests.has(token)) {
      deletionRequests.set(token, `del_${randomUUID().slice(0, 8)}`);
    }
    return send(response, 202, { requestId: deletionRequests.get(token) });
  }

  if (method === 'POST' && path === '/v1/app/devices') {
    let body;
    try {
      body = await readJSON(request);
    } catch {
      return error(response, 400, 'invalid_body', 'The body is not valid JSON.', requestId);
    }
    const valid = typeof body?.apnsToken === 'string' && /^[0-9a-fA-F]+$/.test(body.apnsToken)
      && typeof body.locale === 'string' && /^[A-Z]{2}$/.test(body.country ?? '')
      && typeof body.consent?.orderUpdates === 'boolean' && typeof body.consent?.deals === 'boolean';
    if (!valid) {
      return error(response, 400, 'invalid_registration', 'The registration does not match the contract.', requestId);
    }
    return send(response, 201, undefined);
  }

  if (method === 'DELETE' && /^\/v1\/app\/devices\/[0-9a-fA-F]+$/.test(path)) {
    return send(response, 204, undefined);
  }

  return error(response, 404, 'not_found', 'Unknown route.', requestId);
}

export function start(port = Number(process.env.PORT ?? 8787)) {
  const server = createServer((request, response) => {
    handle(request, response).catch(() => {
      if (!response.headersSent) error(response, 500, 'internal', 'Unexpected error.', 'req_internal');
    });
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = await start();
  console.log(`Mock BFF on http://127.0.0.1:${server.address().port}`);
}

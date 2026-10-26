// ═══════════════════════════════════════════════════════════════
// KARINEX: Recently Sold Tracker (v5, real numbers)
//
// Writes the units really sold per product in the last 30 days to the product metafields
// custom.recently_sold_count, custom.recently_sold_hours and custom.recently_sold_city, which
// the web shop and the iOS app show. No multiplier, no random variation: the shown number is
// the sold quantity of paid and unpaid orders that were not cancelled.
//
// Setup in Apps Script:
//   Projekteinstellungen → Skripteigenschaften → "Skripteigenschaft hinzufügen"
//     Property: SHOPIFY_ACCESS_TOKEN   Value: the Admin API token (shpat_…)
//   The token never goes into this code.
// ═══════════════════════════════════════════════════════════════

var SHOP_DOMAIN  = '45dv93-bk.myshopify.com';
var HOURS_WINDOW = 720; // 30 Tage
var API_VERSION  = '2025-10';

function accessToken_() {
  var token = PropertiesService.getScriptProperties().getProperty('SHOPIFY_ACCESS_TOKEN');
  if (!token) throw new Error('Skripteigenschaft SHOPIFY_ACCESS_TOKEN fehlt');
  return token;
}

function graphql_(query, variables) {
  var response = UrlFetchApp.fetch('https://' + SHOP_DOMAIN + '/admin/api/' + API_VERSION + '/graphql.json', {
    method: 'post',
    headers: { 'X-Shopify-Access-Token': accessToken_(), 'Content-Type': 'application/json' },
    payload: JSON.stringify({ query: query, variables: variables || {} }),
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) {
    throw new Error('HTTP ' + response.getResponseCode() + ': ' + response.getContentText());
  }
  var body = JSON.parse(response.getContentText());
  if (body.errors) throw new Error('GraphQL: ' + JSON.stringify(body.errors));
  return body.data;
}

// ── Shopify Webhook empfangen (orders/paid) ──────────────────────
function doPost(e) {
  try {
    updateRecentlySold();
    return ContentService.createTextOutput('OK').setMimeType(ContentService.MimeType.TEXT);
  } catch (err) {
    Logger.log('Webhook Fehler: ' + err.message);
    return ContentService.createTextOutput('Fehler').setMimeType(ContentService.MimeType.TEXT);
  }
}

// ── Haupt-Funktion ───────────────────────────────────────────────
function updateRecentlySold() {
  var since = new Date();
  since.setHours(since.getHours() - HOURS_WINDOW);
  var sinceISO = since.toISOString().split('.')[0] + 'Z';
  var search = 'created_at:>=' + sinceISO + ' -status:cancelled';

  var salesMap = {};
  var cityMap = {};
  var cursor = null;
  var hasNextPage = true;

  while (hasNextPage) {
    var data = graphql_(
      'query($cursor: String, $search: String) { orders(first: 200, sortKey: CREATED_AT, reverse: true, after: $cursor, query: $search) {' +
      ' pageInfo { hasNextPage endCursor } nodes { shippingAddress { city } billingAddress { city }' +
      ' lineItems(first: 50) { nodes { currentQuantity product { id } } } } } }',
      { cursor: cursor, search: search }
    );
    data.orders.nodes.forEach(function(order) {
      var city = (order.shippingAddress && order.shippingAddress.city) ||
                 (order.billingAddress && order.billingAddress.city) || null;
      order.lineItems.nodes.forEach(function(item) {
        var match = item.product && item.product.id.match(/Product\/(\d+)/);
        if (!match || item.currentQuantity <= 0) return;
        var pid = match[1];
        salesMap[pid] = (salesMap[pid] || 0) + item.currentQuantity;
        if (city && !cityMap[pid]) cityMap[pid] = city;
      });
    });
    hasNextPage = data.orders.pageInfo.hasNextPage;
    cursor = data.orders.pageInfo.endCursor;
  }

  Object.keys(salesMap).forEach(function(pid) {
    writeMetafields_(pid, salesMap[pid], cityMap[pid]);
    Logger.log('  ' + pid + ': ' + salesMap[pid] + ' | ' + (cityMap[pid] || '—'));
    Utilities.sleep(300);
  });

  removeStaleCounts_(salesMap);
}

// ── Metafields schreiben ─────────────────────────────────────────
function writeMetafields_(productId, count, city) {
  var ownerId = 'gid://shopify/Product/' + productId;
  var metafields = [
    { ownerId: ownerId, namespace: 'custom', key: 'recently_sold_count', value: String(count), type: 'number_integer' },
    { ownerId: ownerId, namespace: 'custom', key: 'recently_sold_hours', value: String(HOURS_WINDOW), type: 'number_integer' }
  ];
  if (city) {
    metafields.push({ ownerId: ownerId, namespace: 'custom', key: 'recently_sold_city', value: String(city), type: 'single_line_text_field' });
  }
  var data = graphql_(
    'mutation($metafields: [MetafieldsSetInput!]!) { metafieldsSet(metafields: $metafields) { userErrors { field message } } }',
    { metafields: metafields }
  );
  if (data.metafieldsSet.userErrors.length > 0) {
    Logger.log('Metafield Fehler: ' + JSON.stringify(data.metafieldsSet.userErrors));
  }
}

// ── Alte Zahlen entfernen ────────────────────────────────────────
// Products without a sale in the window keep no number, so no old (or formerly multiplied)
// value stays visible.
function removeStaleCounts_(salesMap) {
  var cursor = null;
  var hasNextPage = true;
  while (hasNextPage) {
    var data = graphql_(
      'query($cursor: String) { products(first: 250, after: $cursor) { pageInfo { hasNextPage endCursor }' +
      ' nodes { id metafield(namespace: "custom", key: "recently_sold_count") { id } } } }',
      { cursor: cursor }
    );
    data.products.nodes.forEach(function(product) {
      var pid = product.id.match(/Product\/(\d+)/)[1];
      if (!product.metafield || salesMap[pid]) return;
      var keys = ['recently_sold_count', 'recently_sold_hours', 'recently_sold_city'];
      var result = graphql_(
        'mutation($metafields: [MetafieldIdentifierInput!]!) { metafieldsDelete(metafields: $metafields) { userErrors { field message } } }',
        { metafields: keys.map(function(key) { return { ownerId: product.id, namespace: 'custom', key: key }; }) }
      );
      if (result.metafieldsDelete.userErrors.length > 0) {
        Logger.log('Löschen Fehler ' + pid + ': ' + JSON.stringify(result.metafieldsDelete.userErrors));
      } else {
        Logger.log('  ' + pid + ': entfernt (kein Verkauf in 30 Tagen)');
      }
      Utilities.sleep(300);
    });
    hasNextPage = data.products.pageInfo.hasNextPage;
    cursor = data.products.pageInfo.endCursor;
  }
}

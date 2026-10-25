// Sample answers of the mock BFF. They contain no real keys and no prices: prices and order
// totals come from Shopify only. The keys are obviously fake placeholders.

export const config = {
  supportHours: { timeZone: 'Europe/Berlin', weekdays: [1, 2, 3, 4, 5, 6, 7], opensAt: '06:00', closesAt: '23:00' },
  whatsappNumber: null,
  liveChatUrl: null,
  supportEmail: 'kundenservice@karinex.de',
  featureFlags: { licenseVault: true },
  minSupportedAppVersion: null,
};

export const orders = [
  { orderId: '1001', name: '#1001', deliveryStatus: 'delivered', hasLicenses: true, hasInvoice: true },
  { orderId: '1002', name: '#1002', deliveryStatus: 'pending', hasLicenses: true, hasInvoice: false },
  { orderId: '1003', name: '#1003', deliveryStatus: 'shipped', hasLicenses: false, hasInvoice: true },
];

export const licenses = {
  '1001': [
    {
      lineItemId: '20001',
      productTitle: 'Mock product A',
      sku: null,
      key: 'MOCK1-MOCK2-MOCK3-MOCK4-MOCK5',
      deliveredAt: '2026-10-20T09:41:00Z',
      activationGuideUrl: null,
    },
  ],
};

/** Orders that belong to another customer: the licenses and invoice endpoints answer 403. */
export const foreignOrders = new Set(['9999']);

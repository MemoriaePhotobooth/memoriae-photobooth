const test = require('node:test');
const assert = require('node:assert');
const { buildPush, buildStaffPush, short, CHANNEL_ID } = require('./payload');

test('push uses the sound channel, high priority and badge count', () => {
  const m = buildPush({ title: 'T', body: 'B', target: 'messages', count: 3 });
  assert.strictEqual(m.android.priority, 'high');
  assert.strictEqual(m.android.notification.channelId, CHANNEL_ID);
  assert.strictEqual(m.android.notification.notificationCount, 3);
  assert.deepStrictEqual(m.data, { target: 'messages' });
  assert.deepStrictEqual(m.notification, { title: 'T', body: 'B' });
});

test('no badge count when count is missing', () => {
  const m = buildPush({ title: 'T', body: 'B', target: 'announcements' });
  assert.ok(!('notificationCount' in m.android.notification));
});

test('short truncates', () => {
  assert.strictEqual(short('abcdef', 4), 'abc…');
  assert.strictEqual(short('abc', 4), 'abc');
});

test('staff push is high priority, targets staff and has no custom channel', () => {
  const m = buildStaffPush({ title: 'New booking', body: 'Full Standee', target: 'bookings' });
  assert.strictEqual(m.android.priority, 'high');
  assert.deepStrictEqual(m.data, { target: 'bookings', audience: 'staff' });
  assert.strictEqual(m.android.notification, undefined);
});

// Pure helpers (no Firebase) so the push payload can be unit-tested.
const CHANNEL_ID = 'memoriae_alerts'; // must match PushNotificationService._channelId

function short(text, max) {
  const t = String(text || '').trim();
  return t.length > max ? t.slice(0, max - 1) + '…' : t;
}

// `count` = how many unread pushes the customer has (shown on the app icon
// by launchers that support badges).
function androidConfig(count) {
  const notification = {
    channelId: CHANNEL_ID,
    sound: 'memoriae_chime', // only used by Android < 8; 8+ uses the channel's sound
    defaultVibrateTimings: true,
    visibility: 'public',
  };
  if (Number.isInteger(count) && count > 0) notification.notificationCount = count;
  return { priority: 'high', ttl: 24 * 60 * 60 * 1000, notification };
}

function buildPush({ title, body, target, count }) {
  return {
    notification: { title, body },
    data: { target },
    android: androidConfig(count),
    apns: { payload: { aps: { sound: 'default' } } },
  };
}

// Staff pushes use the default Android channel (the staff app has no custom
// channel), so no channelId here.
function buildStaffPush({ title, body, target }) {
  return {
    notification: { title, body },
    data: { target, audience: 'staff' },
    android: { priority: 'high', ttl: 24 * 60 * 60 * 1000 },
    apns: { payload: { aps: { sound: 'default' } } },
  };
}

module.exports = { CHANNEL_ID, short, androidConfig, buildPush, buildStaffPush };

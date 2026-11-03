const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();

const { short, buildPush, buildStaffPush } = require('./payload');

async function sendToUser(userId, title, body, target) {
  if (!userId) return;
  const ref = db.collection('users').doc(userId);
  const snap = await ref.get();
  const user = snap.data() || {};
  if (user.pushEnabled === false) return; // customer turned notifications off in Profile
  const tokens = user.fcmTokens;
  if (!Array.isArray(tokens) || tokens.length === 0) return;

  // Unread counter -> the number on the app icon. The app resets it to 0
  // when it is opened.
  const count = (Number.isInteger(user.unreadPush) ? user.unreadPush : 0) + 1;

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    ...buildPush({ title, body, target, count }),
  });

  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
      dead.push(tokens[i]);
    }
  });
  const update = { unreadPush: count };
  if (dead.length) update.fcmTokens = FieldValue.arrayRemove(...dead);
  await ref.update(update);
}

exports.notifyStaffMessage = onDocumentCreated('messages/{id}', async (event) => {
  const m = event.data && event.data.data();
  if (!m || m.fromStaff !== true) return;
  await sendToUser(m.userId, 'Memoriae Staff', short(m.text, 120), 'messages');
});

function bookingNotification(b) {
  const pkg = b.packageName || 'booking';
  if (b.notifyType === 'refunded') {
    return { title: 'Your refund has been sent', body: `Your refund for ${pkg} was sent by GCash.` };
  }
  if (b.notifyType === 'rescheduled') {
    return { title: 'Your booking schedule was moved', body: `${pkg} has a new date/time. Tap to see it.` };
  }
  if (b.status === 'confirmed') {
    return { title: 'Your booking is confirmed!', body: `${pkg} was approved.` };
  }
  if (b.status === 'cancelled') {
    const reason = b.rejectionReason ? ` Reason: ${short(b.rejectionReason, 80)}` : '';
    return { title: 'Your booking was declined', body: `${pkg} was not approved.${reason}` };
  }
  return null;
}

exports.notifyBookingUpdate = onDocumentWritten('bookings/{id}', async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  const before = event.data && event.data.before && event.data.before.data();
  if (!after || after.notifyCustomer !== true) return;

  const changed =
    !before ||
    before.notifyCustomer !== true ||
    before.status !== after.status ||
    before.notifyType !== after.notifyType;
  if (!changed) return;

  const n = bookingNotification(after);
  if (!n) return;
  await sendToUser(after.userId, n.title, n.body, 'bookings');
});

exports.notifyAnnouncement = onDocumentCreated('announcements/{id}', async (event) => {
  const a = event.data && event.data.data();
  if (!a) return;
  await getMessaging().send({
    topic: 'announcements',
    ...buildPush({
      title: short(a.title || 'Memoriae announcement', 60),
      body: short(a.message, 120),
      target: 'announcements',
    }),
  });
});

// Tells the customer when staff add event photos. A staff batch of 20 photos
// creates 20 documents, so the booking remembers when it last sent this push
// and only sends again after 10 minutes.
const EVENT_PHOTO_PUSH_COOLDOWN_MS = 10 * 60 * 1000;

exports.notifyEventPhotos = onDocumentCreated('eventPhotos/{id}', async (event) => {
  const p = event.data && event.data.data();
  if (!p || !p.bookingId || !p.userId) return;

  const bookingRef = db.collection('bookings').doc(p.bookingId);
  const shouldSend = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bookingRef);
    const b = snap.data() || {};
    const last = b.eventPhotosNotifiedAt && b.eventPhotosNotifiedAt.toMillis
      ? b.eventPhotosNotifiedAt.toMillis()
      : 0;
    if (Date.now() - last < EVENT_PHOTO_PUSH_COOLDOWN_MS) return false;
    tx.update(bookingRef, { eventPhotosNotifiedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (!shouldSend) return;

  await sendToUser(
    p.userId,
    'Your event photos are ready',
    'Tap to view and save your photos.',
    'bookings',
  );
});

// ---------- Staff notifications ----------
// Every staff phone that registered a token (staff/{uid}.fcmTokens).
async function staffTokenMap() {
  // Staff AND admin phones (both collections keep fcmTokens on their doc).
  const map = new Map(); // token -> doc ref, so dead tokens can be removed
  for (const name of ['staff', 'admins']) {
    const snap = await db.collection(name).get();
    snap.forEach((doc) => {
      const tokens = doc.data().fcmTokens;
      if (Array.isArray(tokens)) tokens.forEach((t) => map.set(t, doc.ref));
    });
  }
  return map;
}

async function notifyStaff(title, body, target) {
  const map = await staffTokenMap();
  const tokens = [...map.keys()];
  if (tokens.length === 0) return;

  const dead = [];
  for (let i = 0; i < tokens.length; i += 500) { // FCM accepts up to 500 per call
    const chunk = tokens.slice(i, i + 500);
    const res = await getMessaging().sendEachForMulticast({
      tokens: chunk,
      ...buildStaffPush({ title, body, target }),
    });
    res.responses.forEach((r, j) => {
      const code = r.error && r.error.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        dead.push(chunk[j]);
      }
    });
  }
  await Promise.all(
    dead.map((t) => map.get(t).update({ fcmTokens: FieldValue.arrayRemove(t) }).catch(() => {})),
  );
}

// A customer sent a chat message.
exports.notifyStaffNewMessage = onDocumentCreated('messages/{id}', async (event) => {
  const m = event.data && event.data.data();
  if (!m || m.fromStaff === true) return;
  const asking = m.refType === 'camera' && m.refTitle ? `Asking about ${m.refTitle}: ` : '';
  await notifyStaff(
    `New message from ${m.customerName || 'a customer'}`,
    asking + short(m.text, 120),
    'messages',
  );
});

// A booking just moved into review (customer submitted the payment).
exports.notifyStaffBookingReview = onDocumentWritten('bookings/{id}', async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  const before = event.data && event.data.before && event.data.before.data();
  if (!after || after.status !== 'pending_confirmation') return;
  if (before && before.status === 'pending_confirmation') return;
  await notifyStaff(
    'New booking to review',
    `${after.packageName || 'A booking'} is waiting for confirmation.`,
    'bookings',
  );
});

// A paid booking was cancelled and its refund is now waiting to be sent
// (GCash). Alerts staff and admins so it isn't missed.
exports.notifyRefundToSend = onDocumentWritten('bookings/{id}', async (event) => {
  const after = event.data && event.data.after && event.data.after.data();
  const before = event.data && event.data.before && event.data.before.data();
  if (!after || after.refundStatus !== 'pending') return;
  if (before && before.refundStatus === 'pending') return; // only on the change
  const amount = Number(after.refundAmount || 0).toLocaleString('en-PH');
  await notifyStaff(
    'Refund to send',
    `\u20b1${amount} for ${after.packageName || 'a booking'}. Send it by GCash.`,
    'bookings',
  );
});

// A customer asked for a refund on a paid booking. Alerts staff and admins.
exports.notifyRefundRequest = onDocumentCreated('refundRequests/{id}', async (event) => {
  const r = event.data && event.data.data();
  if (!r) return;
  await notifyStaff('Refund request', short(r.reason || 'A customer asked for a refund.', 120), 'bookings');
});


// ---------------------------------------------------------------------------
// Customer self-service account deletion.
//
// Called from the User app (Profile > Delete account) after the customer has
// re-entered their password. It:
//  - refuses if a booking is still waiting for review or payment, a refund is
//    still open, or a camera rental hasn't been returned yet;
//  - keeps bookings, rentals, reviews and refund records for accounting, but
//    detaches them from the account and removes the name and GCash details;
//  - deletes chat messages, chat photos and the profile document;
//  - deletes the Firebase Auth account last, so a failed attempt can be retried.
// ---------------------------------------------------------------------------
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');

const BLOCKING_BOOKING_STATUSES = ['pending_confirmation', 'awaiting_receipt'];

async function applyInChunks(docs, write) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach((d) => write(batch, d.ref));
    await batch.commit();
  }
}

exports.deleteMyAccount = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Log in to delete your account.');
  }

  const pendingBooking = await db.collection('bookings')
    .where('userId', '==', uid)
    .where('status', 'in', BLOCKING_BOOKING_STATUSES)
    .limit(1).get();
  if (!pendingBooking.empty) {
    throw new HttpsError(
      'failed-precondition',
      "You have a booking still waiting for review or payment. Please wait until it's settled, then try again.",
    );
  }

  const openRefund = await db.collection('refundRequests')
    .where('userId', '==', uid)
    .where('status', '==', 'open')
    .limit(1).get();
  if (!openRefund.empty) {
    throw new HttpsError(
      'failed-precondition',
      'You have a refund request still open. Please wait for the studio to finish it, then try again.',
    );
  }

  const activeRental = await db.collection('cameraRentals')
    .where('userId', '==', uid)
    .where('returnedAt', '==', null)
    .limit(1).get();
  if (!activeRental.empty) {
    throw new HttpsError(
      'failed-precondition',
      'You still have a camera rental that has not been returned. Please return it, then try again.',
    );
  }

  // Keep the records for accounting, but detach them from this account and
  // remove personal details (name, GCash number).
  const detach = (batch, ref) => batch.update(ref, {
    userId: 'deleted-account',
    customerName: 'Deleted customer',
    accountDeleted: true,
    gcashName: FieldValue.delete(),
    gcashNumber: FieldValue.delete(),
  });
  for (const col of ['bookings', 'cameraRentals', 'feedback', 'refundRequests']) {
    const snap = await db.collection(col).where('userId', '==', uid).get();
    await applyInChunks(snap.docs, detach);
  }

  // Chat is personal, so it is removed.
  for (const col of ['messages', 'messageImages']) {
    const snap = await db.collection(col).where('userId', '==', uid).get();
    await applyInChunks(snap.docs, (batch, ref) => batch.delete(ref));
  }
  await db.collection('threadStatus').doc(uid).delete();
  await db.collection('users').doc(uid).delete();

  // Last step: the login itself. If anything above failed, the account still
  // exists and the customer can simply try again.
  await getAuth().deleteUser(uid);
  return { ok: true };
});

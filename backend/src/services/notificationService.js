const path = require('path');
const pool = require('../database/pool');

let messaging = null;

function loadServiceAccount() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    } catch (err) {
      console.error('[FCM] Invalid FIREBASE_SERVICE_ACCOUNT_JSON:', err.message);
      return null;
    }
  }

  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (!serviceAccountPath) return null;

  try {
    return require(path.resolve(serviceAccountPath));
  } catch (err) {
    console.error('[FCM] Cannot load service account file:', err.message);
    return null;
  }
}

function getMessaging() {
  if (messaging) return messaging;

  const serviceAccount = loadServiceAccount();
  if (!serviceAccount) {
    console.warn(
      '[FCM] Push disabled — set FIREBASE_SERVICE_ACCOUNT_PATH or FIREBASE_SERVICE_ACCOUNT_JSON in backend/.env',
    );
    return null;
  }

  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    messaging = admin.messaging();
    console.log('[FCM] Firebase Admin initialized — system push enabled');
    return messaging;
  } catch (err) {
    console.error('[FCM] Failed to initialize Firebase Admin:', err.message);
    return null;
  }
}

async function saveNotification(userId, { type, title, body, data = {} }) {
  await pool.query(
    `INSERT INTO notifications (user_id, type, title, body, data)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, type, title, body, JSON.stringify(data)],
  );
}

async function getUserTokens(userId) {
  const result = await pool.query(
    'SELECT token FROM device_tokens WHERE user_id = $1',
    [userId],
  );
  return result.rows.map((r) => r.token);
}

function buildFcmMessage({ token, type, title, body, data }) {
  const dataPayload = {
    type: String(type),
    title: String(title),
    body: String(body),
    ...Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v ?? '')])),
  };

  return {
    token,
    notification: { title, body },
    data: dataPayload,
    android: {
      priority: 'high',
      ttl: 86400,
      notification: {
        channelId: 'attendance_alerts_v2',
        sound: 'default',
        defaultSound: true,
        defaultVibrateTimings: true,
        priority: 'max',
        visibility: 'public',
        notificationCount: 1,
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: 'default',
          badge: 1,
          'content-available': 1,
        },
      },
    },
  };
}

async function sendToUser(userId, { type, title, body, data = {} }) {
  await saveNotification(userId, { type, title, body, data });

  const fcm = getMessaging();
  if (!fcm) return { pushed: false, reason: 'fcm_not_configured' };

  const tokens = await getUserTokens(userId);
  if (!tokens.length) {
    console.warn(`[FCM] No device token for user ${userId} — student must open app and log in`);
    return { pushed: false, reason: 'no_token' };
  }

  const staleTokens = [];
  let sent = 0;

  await Promise.all(
    tokens.map(async (token) => {
      try {
        await fcm.send(buildFcmMessage({ token, type, title, body, data }));
        sent += 1;
      } catch (err) {
        if (
          err.code === 'messaging/registration-token-not-registered' ||
          err.code === 'messaging/invalid-registration-token'
        ) {
          staleTokens.push(token);
        } else {
          console.error(`[FCM] Send error (user ${userId}):`, err.code, err.message);
        }
      }
    }),
  );

  if (staleTokens.length) {
    await pool.query(
      'DELETE FROM device_tokens WHERE user_id = $1 AND token = ANY($2)',
      [userId, staleTokens],
    );
  }

  if (sent > 0) {
    console.log(`[FCM] Pushed "${title}" to user ${userId} (${sent} device(s))`);
  }

  return { pushed: sent > 0, sent };
}

async function notifyClassSessionStarted(classId, session) {
  const students = await pool.query(
    `SELECT DISTINCT u.id
     FROM class_enrollments ce
     JOIN users u ON u.id = ce.student_id
     WHERE ce.class_id = $1 AND u.role = 'student'`,
    [classId],
  );

  if (!students.rows.length) {
    console.warn(`[FCM] No enrolled students for class ${classId}`);
    return;
  }

  const subjectName =
    session.subjectName || session.subject_name || session.subject_code || 'Your module';
  const className = session.className || session.class_name || '';
  const sessionId = session.id || session.sessionId;
  const rangeM = session.ble_max_distance_meters || session.bleMaxDistanceMeters || 20;

  const title = 'Live attendance session';
  const body = className
    ? `${subjectName} (${className}) is live. Open FacePass to mark attendance within ${rangeM} m.`
    : `${subjectName} is live. Open FacePass to mark attendance within ${rangeM} m.`;

  const results = await Promise.all(
    students.rows.map((row) =>
      sendToUser(row.id, {
        type: 'SESSION_STARTED',
        title,
        body,
        data: {
          sessionId: sessionId || '',
          classId: classId || '',
          subjectName,
          className,
        },
      }),
    ),
  );

  const pushed = results.filter((r) => r.pushed).length;
  console.log(
    `[FCM] Session ${sessionId}: in-app saved for ${students.rows.length} student(s), system push sent to ${pushed}`,
  );
}

function logPushStatusOnStartup() {
  const serviceAccount = loadServiceAccount();
  if (!serviceAccount) {
    console.warn(
      '[FCM] OFF — add FIREBASE_SERVICE_ACCOUNT_PATH or FIREBASE_SERVICE_ACCOUNT_JSON to backend/.env',
    );
    console.warn('[FCM] Without this, notifications stay in-app (bell) only; no phone tray push.');
    return;
  }
  const fcm = getMessaging();
  if (fcm) {
    console.log('[FCM] ON — phone push notifications enabled (tray + sound when app is closed)');
  }
}

module.exports = {
  sendToUser,
  saveNotification,
  notifyClassSessionStarted,
  logPushStatusOnStartup,
};

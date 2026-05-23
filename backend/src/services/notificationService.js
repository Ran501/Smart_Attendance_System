const path = require('path');
const pool = require('../database/pool');

let messaging = null;

function getMessaging() {
  if (messaging) return messaging;

  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (!serviceAccountPath) {
    console.warn('[FCM] FIREBASE_SERVICE_ACCOUNT_PATH not set — push notifications disabled');
    return null;
  }

  try {
    const admin = require('firebase-admin');
    if (!admin.apps.length) {
      const serviceAccount = require(path.resolve(serviceAccountPath));
      admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    }
    messaging = admin.messaging();
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

async function sendToUser(userId, { type, title, body, data = {} }) {
  // Always save to DB so in-app bell shows it even without push
  await saveNotification(userId, { type, title, body, data });

  const fcm = getMessaging();
  if (!fcm) return;

  const tokens = await getUserTokens(userId);
  if (!tokens.length) return;

  const message = {
    notification: { title, body },
    data: { type, ...Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) },
    android: {
      priority: 'high',
      notification: { channelId: 'attendance_alerts', sound: 'default' },
    },
  };

  const staleTokens = [];
  await Promise.all(
    tokens.map(async (token) => {
      try {
        await fcm.send({ ...message, token });
      } catch (err) {
        if (err.code === 'messaging/registration-token-not-registered') {
          staleTokens.push(token);
        } else {
          console.error('[FCM] Send error:', err.message);
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
}

/**
 * Notify all enrolled students in a class that a live attendance session started.
 */
async function notifyClassSessionStarted(classId, session) {
  const students = await pool.query(
    `SELECT DISTINCT u.id
     FROM class_enrollments ce
     JOIN users u ON u.id = ce.student_id
     WHERE ce.class_id = $1 AND u.role = 'student'`,
    [classId],
  );

  if (!students.rows.length) return;

  const subjectName =
    session.subjectName || session.subject_name || session.subject_code || 'Your module';
  const className = session.className || session.class_name || '';
  const sessionId = session.id || session.sessionId;
  const rangeM = session.ble_max_distance_meters || session.bleMaxDistanceMeters || 20;

  const title = 'Live attendance session';
  const body = className
    ? `${subjectName} (${className}) is live. Open FacePass to mark attendance within ${rangeM} m.`
    : `${subjectName} is live. Open FacePass to mark attendance within ${rangeM} m.`;

  await Promise.all(
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

  console.log(
    `[FCM] Session started push queued for ${students.rows.length} student(s) (class ${classId})`,
  );
}

module.exports = { sendToUser, saveNotification, notifyClassSessionStarted };

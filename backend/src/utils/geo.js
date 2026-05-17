/**
 * GPS proximity helpers.
 * Phone GPS is often wrong by 10–20m (especially indoors), so we use a base
 * radius plus accuracy buffers instead of a hard 5m cutoff.
 */

const DEFAULT_HOST_RADIUS = 100;
/** Compensates for error between two independent phone GPS fixes */
const GPS_FIXED_BUFFER = 12;
const MAX_ACCURACY_BUFFER = 20;

function distanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizeAccuracy(accuracy) {
  if (accuracy == null || Number.isNaN(accuracy) || accuracy <= 0) {
    return GPS_FIXED_BUFFER;
  }
  return Math.min(accuracy, MAX_ACCURACY_BUFFER);
}

/**
 * Effective allowed distance = base + fixed buffer + both devices' accuracy.
 */
function effectiveAllowedRadius(baseRadius, hostAccuracy, studentAccuracy) {
  const base = baseRadius ?? DEFAULT_HOST_RADIUS;
  const hostBuf = normalizeAccuracy(hostAccuracy);
  const studentBuf = normalizeAccuracy(studentAccuracy);
  return base + GPS_FIXED_BUFFER + hostBuf + studentBuf;
}

function checkHostProximity({
  studentLat,
  studentLon,
  hostLat,
  hostLon,
  baseRadius,
  hostAccuracy,
  studentAccuracy,
}) {
  const distance = distanceMeters(studentLat, studentLon, hostLat, hostLon);
  const allowedRadius = effectiveAllowedRadius(
    baseRadius,
    hostAccuracy,
    studentAccuracy,
  );
  return {
    valid: distance <= allowedRadius,
    distance,
    allowedRadius,
    baseRadius: baseRadius ?? DEFAULT_HOST_RADIUS,
  };
}

function isInsideGeoFence(studentLat, studentLon, classroom, bufferMeters = 0) {
  const dist = distanceMeters(
    studentLat,
    studentLon,
    classroom.latitude,
    classroom.longitude,
  );
  return dist <= classroom.radius_meters + bufferMeters;
}

module.exports = {
  distanceMeters,
  effectiveAllowedRadius,
  checkHostProximity,
  isInsideGeoFence,
  DEFAULT_HOST_RADIUS,
  GPS_FIXED_BUFFER,
};

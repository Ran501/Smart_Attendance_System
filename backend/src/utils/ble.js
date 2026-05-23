const BLE_MAX_DISTANCE_METERS = parseFloat(process.env.BLE_MAX_DISTANCE_METERS || '20');
const BLE_MIN_RSSI = parseInt(process.env.BLE_MIN_RSSI || '-95', 10);

function validateBleProximity({ bleVerified, bleRssi }) {
  if (bleVerified !== true) {
    return {
      valid: false,
      reason:
        `Bluetooth proximity required — stay within ${BLE_MAX_DISTANCE_METERS} m of your teacher's phone with Bluetooth on`,
    };
  }
  const rssi = bleRssi != null ? Number(bleRssi) : null;
  if (rssi == null || Number.isNaN(rssi)) {
    return { valid: false, reason: 'Bluetooth signal strength missing' };
  }
  if (rssi < BLE_MIN_RSSI) {
    return {
      valid: false,
      reason: `Too far from teacher Bluetooth (${rssi} dBm). Move within ${BLE_MAX_DISTANCE_METERS} m.`,
    };
  }
  return { valid: true, rssi };
}

module.exports = {
  BLE_MAX_DISTANCE_METERS,
  BLE_MIN_RSSI,
  validateBleProximity,
};

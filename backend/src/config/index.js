require('dotenv').config();

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  databaseUrl: process.env.DATABASE_URL,
  jwt: {
    secret: process.env.JWT_SECRET || 'dev-secret-change-in-production',
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },
  faceMatchThreshold: parseFloat(process.env.FACE_MATCH_THRESHOLD || '0.70'),
  defaultSessionDurationMinutes: parseInt(
    process.env.DEFAULT_SESSION_DURATION_MINUTES || '5',
    10,
  ),
  corsOrigin: process.env.CORS_ORIGIN || '*',
};

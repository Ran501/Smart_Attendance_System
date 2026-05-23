const http = require('http');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { Server } = require('socket.io');
const config = require('./config');
const routes = require('./routes');
const { ensureRuntimeSchema } = require('./database/ensureSchema');
const { logPushStatusOnStartup } = require('./services/notificationService');

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: config.corsOrigin, methods: ['GET', 'POST'] },
});

app.use(helmet());
app.use(cors({ origin: config.corsOrigin }));
app.use(morgan(config.nodeEnv === 'production' ? 'combined' : 'dev'));
app.use(express.json({ limit: '2mb' }));

app.use((req, res, next) => {
  req.io = io;
  next();
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use('/api/v1', routes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({
    error: config.nodeEnv === 'production' ? 'Internal server error' : err.message,
  });
});

io.on('connection', (socket) => {
  socket.on('join:session', (sessionId) => {
    socket.join(`session:${sessionId}`);
  });
  socket.on('leave:session', (sessionId) => {
    socket.leave(`session:${sessionId}`);
  });
  socket.on('join:class', (classId) => {
    if (classId) socket.join(`class:${classId}`);
  });
  socket.on('leave:class', (classId) => {
    if (classId) socket.leave(`class:${classId}`);
  });
  socket.on('join:student', (studentId) => {
    if (studentId) socket.join(`student:${studentId}`);
  });
  socket.on('leave:student', (studentId) => {
    if (studentId) socket.leave(`student:${studentId}`);
  });
});

async function start() {
  await ensureRuntimeSchema();
  logPushStatusOnStartup();
  server.listen(config.port, () => {
    console.log(`Smart Attendance API running on port ${config.port}`);
  });
}

start().catch((err) => {
  console.error('Failed to start Smart Attendance API:', err);
  process.exit(1);
});

module.exports = { app, server, io };

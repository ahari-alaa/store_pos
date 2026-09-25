const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const env = require('./config/env');
const logger = require('./utils/logger');
const apiRoutes = require('./routes');
const { errorHandler, notFoundHandler } = require('./middleware/errorHandler');

const app = express();

// Security headers (section 12: "Secure HTTP headers").
// crossOriginResourcePolicy is relaxed to 'cross-origin' only for the
// static /uploads mount below, so the Flutter app (a different origin on
// web) can still load product images helmet would otherwise block.
app.use(helmet());

// CORS: restrict in production via CORS_ORIGIN; Flutter mobile clients
// don't send an Origin header at all, so this mainly matters for any
// web/admin dashboard built against this API later.
app.use(cors({ origin: env.security.corsOrigin }));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

if (env.nodeEnv !== 'test') {
  app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));
}

// Uploaded product images (see middleware/upload.js). Served as plain
// static files — no auth on the image bytes themselves, same as any CDN
// would serve them; the JWT-protected API only controls who can set or
// change which image a product points to.
app.use(
  '/uploads',
  (req, res, next) => {
    res.header('Cross-Origin-Resource-Policy', 'cross-origin');
    next();
  },
  express.static(path.join(__dirname, '..', 'uploads'))
);

app.use('/api', apiRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

if (require.main === module) {
  app.listen(env.port, () => {
    logger.info(`Store POS backend listening on port ${env.port} (${env.nodeEnv})`);
  });
}

module.exports = app;

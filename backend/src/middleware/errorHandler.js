const ApiError = require('../utils/ApiError');
const logger = require('../utils/logger');
const env = require('../config/env');

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof ApiError) {
    if (err.statusCode >= 500) logger.error(err);
    return res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
        ...(err.details ? { details: err.details } : {}),
      },
    });
  }

  // MySQL duplicate key -> surface as a clean conflict instead of a 500
  if (err && err.code === 'ER_DUP_ENTRY') {
    return res.status(409).json({
      success: false,
      error: { code: 'DUPLICATE_ENTRY', message: 'A record with this value already exists' },
    });
  }

  // MySQL FK violation on DELETE (ON DELETE RESTRICT rejected it) -> this
  // should normally never reach here, since services that delete
  // referenced rows (productService.remove, ingredientService.remove)
  // check for and report the specific reason before attempting the
  // DELETE. Kept as a defense-in-depth backstop so an unexpected/missed
  // reference surfaces as a clean 409 instead of a raw SQL error leaking
  // to the client.
  if (err && err.errno === 1451) {
    return res.status(409).json({
      success: false,
      error: {
        code: 'REFERENCED_BY_OTHER_RECORDS',
        message: 'This item is still referenced by other records and cannot be deleted.',
      },
    });
  }

  logger.error(err);
  return res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message:
        env.nodeEnv === 'production' ? 'Internal server error' : err.message || 'Unknown error',
    },
  });
}

function notFoundHandler(req, res) {
  res.status(404).json({
    success: false,
    error: { code: 'ROUTE_NOT_FOUND', message: `No route: ${req.method} ${req.originalUrl}` },
  });
}

module.exports = { errorHandler, notFoundHandler };

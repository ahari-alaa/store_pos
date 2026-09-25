/**
 * Wrap an async Express handler so a thrown/rejected error is forwarded
 * to next(err) instead of crashing the process or hanging the request.
 */
function asyncHandler(fn) {
  return function wrapped(req, res, next) {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = asyncHandler;

function ok(res, data = {}, statusCode = 200) {
  return res.status(statusCode).json({ success: true, data });
}

function created(res, data = {}) {
  return ok(res, data, 201);
}

function fail(res, statusCode, code, message, details) {
  return res.status(statusCode).json({
    success: false,
    error: { code, message, ...(details ? { details } : {}) },
  });
}

module.exports = { ok, created, fail };

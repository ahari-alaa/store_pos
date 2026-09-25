const ApiError = require('../utils/ApiError');

/**
 * Validate req[part] (body/query/params) against a Joi schema.
 * On failure, throws a 422 VALIDATION_ERROR with all field errors attached
 * so the Flutter client can show precise, per-field feedback.
 */
function validate(schema, part = 'body') {
  return function validateMiddleware(req, res, next) {
    const { error, value } = schema.validate(req[part], {
      abortEarly: false,
      stripUnknown: true,
    });
    if (error) {
      const details = error.details.map((d) => ({
        field: d.path.join('.'),
        message: d.message,
      }));
      return next(ApiError.validation('Invalid request data', details));
    }
    req[part] = value;
    next();
  };
}

module.exports = validate;

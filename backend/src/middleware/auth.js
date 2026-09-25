const jwt = require('jsonwebtoken');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const asyncHandler = require('../utils/asyncHandler');
const userRepository = require('../repositories/userRepository');

const requireAuth = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw ApiError.unauthorized('Missing or malformed Authorization header', 'NO_TOKEN');
  }

  let payload;
  try {
    payload = jwt.verify(token, env.jwt.secret);
  } catch (err) {
    if (err.name === 'TokenExpiredError')
    {
      throw ApiError.unauthorized('Session expired, please log in again', 'TOKEN_EXPIRED');
    }
    throw ApiError.unauthorized('Invalid authentication token', 'TOKEN_INVALID');
  }

  const user = await userRepository.findById(payload.sub);
  if (!user) {
    throw ApiError.unauthorized('User no longer exists', 'USER_NOT_FOUND');
  }
  if (!user.is_active) {
    throw ApiError.forbidden('This account has been deactivated', 'USER_INACTIVE');
  }

  req.user = {
    id: user.id,
    storeId: user.store_id,
    role: user.role,
    email: user.email,
    name: user.name,
  };
  next();
});

module.exports = { requireAuth };

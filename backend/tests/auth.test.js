process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/repositories/userRepository');
jest.mock('bcryptjs');

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const userRepository = require('../src/repositories/userRepository');
const authService = require('../src/services/authService');
const ApiError = require('../src/utils/ApiError');

const ACTIVE_USER = {
  id: 'user-1',
  store_id: 'store-1',
  name: 'Cashier One',
  email: 'cashier@example.com',
  password_hash: 'hashed-password',
  role: 'cashier',
  is_active: 1,
};

describe('authService.login', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('rejects an unknown email with a generic error (no user enumeration)', async () => {
    userRepository.findByEmail.mockResolvedValue(null);

    await expect(authService.login({ email: 'nobody@example.com', password: 'whatever' })).rejects
      .toMatchObject({ statusCode: 401, code: 'INVALID_CREDENTIALS' });
  });

  test('rejects a wrong password with the same generic error as unknown email', async () => {
    userRepository.findByEmail.mockResolvedValue(ACTIVE_USER);
    bcrypt.compare.mockResolvedValue(false);

    await expect(authService.login({ email: ACTIVE_USER.email, password: 'wrong' })).rejects
      .toMatchObject({ statusCode: 401, code: 'INVALID_CREDENTIALS' });
  });

  test('rejects login for a deactivated user even with the correct password', async () => {
    userRepository.findByEmail.mockResolvedValue({ ...ACTIVE_USER, is_active: 0 });
    bcrypt.compare.mockResolvedValue(true);

    await expect(authService.login({ email: ACTIVE_USER.email, password: 'correct' })).rejects
      .toMatchObject({ statusCode: 403, code: 'USER_INACTIVE' });
  });

  test('returns a signed JWT and public user fields on correct credentials', async () => {
    userRepository.findByEmail.mockResolvedValue(ACTIVE_USER);
    bcrypt.compare.mockResolvedValue(true);

    const result = await authService.login({ email: ACTIVE_USER.email, password: 'correct' });

    expect(result.access_token).toEqual(expect.any(String));
    expect(result.user).toEqual({
      id: ACTIVE_USER.id,
      store_id: ACTIVE_USER.store_id,
      name: ACTIVE_USER.name,
      email: ACTIVE_USER.email,
      role: ACTIVE_USER.role,
      is_active: true,
    });

    // Password hash must never leak into the response payload.
    expect(result.user.password_hash).toBeUndefined();

    const decoded = jwt.verify(result.access_token, process.env.JWT_SECRET);
    expect(decoded.sub).toBe(ACTIVE_USER.id);
    expect(decoded.store_id).toBe(ACTIVE_USER.store_id);
    expect(decoded.role).toBe(ACTIVE_USER.role);
  });
});

describe('authService.loginWithPin', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('rejects a PIN nobody holds with a generic error (no user enumeration)', async () => {
    userRepository.findByPinHash.mockResolvedValue(null);

    await expect(authService.loginWithPin({ pin: '1234' })).rejects.toMatchObject({
      statusCode: 401,
      code: 'INVALID_PIN',
    });
  });

  test('rejects a correct PIN belonging to a deactivated user', async () => {
    userRepository.findByPinHash.mockResolvedValue({ ...ACTIVE_USER, is_active: 0 });

    await expect(authService.loginWithPin({ pin: '1234' })).rejects.toMatchObject({
      statusCode: 403,
      code: 'USER_INACTIVE',
    });
  });

  test('logs in the exact user that PIN belongs to and issues a JWT for their id', async () => {
    userRepository.findByPinHash.mockResolvedValue(ACTIVE_USER);

    const result = await authService.loginWithPin({ pin: '1234' });

    expect(result.access_token).toEqual(expect.any(String));
    expect(result.user.id).toBe(ACTIVE_USER.id);
    expect(result.user.pin).toBeUndefined();
    expect(result.user.pin_hash).toBeUndefined();

    const decoded = jwt.verify(result.access_token, process.env.JWT_SECRET);
    expect(decoded.sub).toBe(ACTIVE_USER.id);
    expect(decoded.role).toBe(ACTIVE_USER.role);
  });

  test('two different users with different PINs each resolve to their own account', async () => {
    const ahmed = { ...ACTIVE_USER, id: 'user-ahmed', name: 'Ahmed' };
    const sara = { ...ACTIVE_USER, id: 'user-sara', name: 'Sara' };

    userRepository.findByPinHash.mockImplementation(async (hash) => {
      // authService.hashPin is deterministic per input PIN, so different
      // PINs never produce the same lookup hash here.
      if (hash === authService.hashPin('1234')) return ahmed;
      if (hash === authService.hashPin('5678')) return sara;
      return null;
    });

    const ahmedLogin = await authService.loginWithPin({ pin: '1234' });
    const saraLogin = await authService.loginWithPin({ pin: '5678' });

    expect(ahmedLogin.user.id).toBe('user-ahmed');
    expect(saraLogin.user.id).toBe('user-sara');
  });
});

describe('authService.setPin', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('rejects setting a PIN for a user outside the admin\'s store', async () => {
    userRepository.findByIdForStore.mockResolvedValue(null);

    await expect(authService.setPin('store-1', 'user-1', '1234', 'admin-1')).rejects.toMatchObject({
      statusCode: 404,
      code: 'USER_NOT_FOUND',
    });
  });

  test('rejects a PIN already in use by a different user, without naming them', async () => {
    userRepository.findByIdForStore.mockResolvedValue(ACTIVE_USER);
    userRepository.findByPinHash.mockResolvedValue({ ...ACTIVE_USER, id: 'someone-else' });

    await expect(authService.setPin('store-1', ACTIVE_USER.id, '1234', 'admin-1')).rejects.toMatchObject({
      statusCode: 409,
      code: 'PIN_TAKEN',
    });
  });

  test('allows re-saving the same PIN the user already holds', async () => {
    userRepository.findByIdForStore.mockResolvedValue(ACTIVE_USER);
    userRepository.findByPinHash.mockResolvedValue(ACTIVE_USER); // same id as target
    userRepository.updateForStore.mockResolvedValue(ACTIVE_USER);

    await expect(
      authService.setPin('store-1', ACTIVE_USER.id, '1234', 'admin-1')
    ).resolves.toMatchObject({ id: ACTIVE_USER.id });
  });

  test('stores a hash, never the plaintext PIN', async () => {
    userRepository.findByIdForStore.mockResolvedValue(ACTIVE_USER);
    userRepository.findByPinHash.mockResolvedValue(null);
    userRepository.updateForStore.mockResolvedValue(ACTIVE_USER);

    await authService.setPin('store-1', ACTIVE_USER.id, '4321', 'admin-1');

    const [, , fields] = userRepository.updateForStore.mock.calls[0];
    expect(fields.pin_hash).toBeDefined();
    expect(fields.pin_hash).not.toBe('4321');
    expect(fields.pin_hash).toBe(authService.hashPin('4321'));
  });
});

describe('authService.createUser', () => {
  beforeEach(() => jest.clearAllMocks());

  test('rejects creating a user with an email that is already taken', async () => {
    userRepository.findByEmail.mockResolvedValue(ACTIVE_USER);

    await expect(
      authService.createUser({
        name: 'New Person',
        email: ACTIVE_USER.email,
        password: 'password123',
        role: 'cashier',
        store_id: 'store-1',
      })
    ).rejects.toMatchObject({ statusCode: 409, code: 'EMAIL_TAKEN' });
  });

  test('hashes the password before storing a new user', async () => {
    userRepository.findByEmail.mockResolvedValue(null);
    bcrypt.hash.mockResolvedValue('super-hashed');
    userRepository.create.mockResolvedValue({ ...ACTIVE_USER, id: 'user-2', password_hash: 'super-hashed' });

    await authService.createUser({
      name: 'New Person',
      email: 'new@example.com',
      password: 'plainTextPassword',
      role: 'cashier',
      store_id: 'store-1',
    });

    expect(bcrypt.hash).toHaveBeenCalledWith('plainTextPassword', expect.any(Number));
    const createArgs = userRepository.create.mock.calls[0][0];
    expect(createArgs.passwordHash).toBe('super-hashed');
    expect(createArgs.passwordHash).not.toBe('plainTextPassword');
  });
});

// The deactivate/reactivate mechanism the Cashiers screen drives
// (PUT /auth/users/:id with { is_active: false|true }). These lock in the
// two properties the Flutter fix depends on: the call is store-scoped,
// and an admin can never deactivate themselves — so deactivating another
// cashier can never invalidate the acting admin's own session.
describe('authService.updateUser (deactivate / reactivate)', () => {
  beforeEach(() => jest.clearAllMocks());

  test('soft-deactivates by writing is_active = 0, never deleting the row', async () => {
    userRepository.updateForStore.mockResolvedValue({ ...ACTIVE_USER, is_active: 0 });

    const result = await authService.updateUser(
      'store-1',
      ACTIVE_USER.id,
      { is_active: false },
      'admin-1'
    );

    const [storeId, id, fields] = userRepository.updateForStore.mock.calls[0];
    expect(storeId).toBe('store-1');
    expect(id).toBe(ACTIVE_USER.id);
    expect(fields).toEqual({ is_active: 0 });
    expect(result.is_active).toBe(false);
  });

  test('reactivates by writing is_active = 1', async () => {
    userRepository.updateForStore.mockResolvedValue({ ...ACTIVE_USER, is_active: 1 });

    await authService.updateUser('store-1', ACTIVE_USER.id, { is_active: true }, 'admin-1');

    const [, , fields] = userRepository.updateForStore.mock.calls[0];
    expect(fields).toEqual({ is_active: 1 });
  });

  test('never returns the password hash or PIN hash to the client', async () => {
    userRepository.updateForStore.mockResolvedValue({
      ...ACTIVE_USER,
      is_active: 0,
      pin_hash: 'some-pin-hash',
    });

    const result = await authService.updateUser(
      'store-1',
      ACTIVE_USER.id,
      { is_active: false },
      'admin-1'
    );

    expect(result.password_hash).toBeUndefined();
    expect(result.pin_hash).toBeUndefined();
  });

  test('refuses to let an admin deactivate their own account', async () => {
    await expect(
      authService.updateUser('store-1', 'admin-1', { is_active: false }, 'admin-1')
    ).rejects.toMatchObject({ statusCode: 400, code: 'CANNOT_EDIT_SELF' });

    expect(userRepository.updateForStore).not.toHaveBeenCalled();
  });

  test('refuses to let an admin demote their own role', async () => {
    await expect(
      authService.updateUser('store-1', 'admin-1', { role: 'cashier' }, 'admin-1')
    ).rejects.toMatchObject({ statusCode: 400, code: 'CANNOT_EDIT_SELF' });
  });

  test('404s for a user in a different store (store scoping is enforced in SQL)', async () => {
    // updateForStore returns null when `WHERE id = ? AND store_id = ?`
    // matches no row — i.e. the target belongs to another store.
    userRepository.updateForStore.mockResolvedValue(null);

    await expect(
      authService.updateUser('store-1', 'user-from-store-2', { is_active: false }, 'admin-1')
    ).rejects.toMatchObject({ statusCode: 404, code: 'USER_NOT_FOUND' });
  });

  test('only writes the fields actually present in the request body', async () => {
    userRepository.updateForStore.mockResolvedValue(ACTIVE_USER);

    await authService.updateUser('store-1', ACTIVE_USER.id, { is_active: false }, 'admin-1');

    const [, , fields] = userRepository.updateForStore.mock.calls[0];
    expect(Object.keys(fields)).toEqual(['is_active']);
    expect(fields.name).toBeUndefined();
    expect(fields.role).toBeUndefined();
    expect(fields.password_hash).toBeUndefined();
  });
});

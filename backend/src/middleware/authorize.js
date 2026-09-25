const ApiError = require('../utils/ApiError');

/**
 * Role-based access control.
 *
 * Usage: router.post('/products', requireAuth, authorize('admin', 'manager'), handler)
 *
 * This enforces permissions on the SERVER regardless of what the Flutter
 * client shows or hides in its UI (section 9 of the spec: the client is
 * never the source of truth for authorization).
 */
function authorize(...allowedRoles) {
  return function authorizeMiddleware(req, res, next) {
    if (!req.user) {
      return next(ApiError.unauthorized());
    }
    if (!allowedRoles.includes(req.user.role)) {
      return next(
        ApiError.forbidden(
          `Role '${req.user.role}' is not permitted to perform this action`,
          'ROLE_NOT_ALLOWED'
        )
      );
    }
    next();
  };
}

/**
 * Role -> permission map. Kept explicit and centralized instead of scattered
 * across route files, so permission changes are a one-file review.
 */
const ROLE_PERMISSIONS = {
  admin: [
    'users.manage',
    'products.manage',
    'suppliers.manage',
    'inventory.manage',
    'reports.view',
    'expenses.manage',
    'sales.create',
    'payments.create',
    'store.configure',
    'cashier_settlements.view',
    'cashier_settlements.manage',
  ],
  manager: [
    'products.manage',
    'suppliers.manage',
    'inventory.manage',
    'reports.view',
    'expenses.manage',
    'sales.create',
    'payments.create',
    'cashier_settlements.view',
    'cashier_settlements.manage',
  ],
  // 'sales.serve'                     -> POST /sales/:id/serve|reprint (the cashier's own orders)
  // 'reports.view_own'                -> GET /reports/my-sales (personal report, always
  //                                      scoped to req.user.id — never to a client-sent id)
  // 'cashier_settlements.manage_own'  -> GET/POST /cashier-settlements/* — the cashier's own
  //                                      work-payment justificatifs (spec §1-§21). Distinct from
  //                                      'cashier_settlements.view'/'manage' below, which are the
  //                                      admin/manager-only "Paiements caissiers" screen (spec §22-§23)
  //                                      and can see/act on EVERY cashier's settlements.
  cashier: [
    'products.view',
    'sales.create',
    'payments.create',
    'sales.view_own',
    'sales.serve',
    'reports.view_own',
    'cashier_settlements.manage_own',
  ],
};

function hasPermission(role, permission) {
  return (ROLE_PERMISSIONS[role] || []).includes(permission);
}

function requirePermission(permission) {
  return function permissionMiddleware(req, res, next) {
    if (!req.user) return next(ApiError.unauthorized());
    if (!hasPermission(req.user.role, permission)) {
      return next(
        ApiError.forbidden(
          `Missing permission '${permission}' for role '${req.user.role}'`,
          'PERMISSION_DENIED'
        )
      );
    }
    next();
  };
}

module.exports = { authorize, requirePermission, hasPermission, ROLE_PERMISSIONS };

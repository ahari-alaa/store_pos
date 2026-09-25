const express = require('express');

const authRoutes = require('./authRoutes');
const productRoutes = require('./productRoutes');
const supplierRoutes = require('./supplierRoutes');
const saleRoutes = require('./saleRoutes');
const paymentRoutes = require('./paymentRoutes');
const expenseRoutes = require('./expenseRoutes');
const inventoryRoutes = require('./inventoryRoutes');
const ingredientRoutes = require('./ingredientRoutes');
const syncRoutes = require('./syncRoutes');
const reportRoutes = require('./reportRoutes');
const cashierReportRoutes = require('./cashierReportRoutes');
const cashierSettlementRoutes = require('./cashierSettlementRoutes');
const adminCashierSettlementRoutes = require('./adminCashierSettlementRoutes');

const router = express.Router();

router.get('/health', (req, res) => res.json({ success: true, data: { status: 'ok' } }));

router.use('/auth', authRoutes);
router.use('/products', productRoutes);
router.use('/suppliers', supplierRoutes);
router.use('/sales', saleRoutes);
router.use('/payments', paymentRoutes);
router.use('/expenses', expenseRoutes);
router.use('/inventory', inventoryRoutes);
router.use('/ingredients', ingredientRoutes);
router.use('/sync', syncRoutes);
// Cashier-personal endpoints first (own permission gate); every other
// /reports/* path falls through to the admin/manager-only router below.
router.use('/reports', cashierReportRoutes);
router.use('/reports', reportRoutes);
// Cashier work-payment justificatifs (spec §1-§21): the cashier's own.
router.use('/cashier-settlements', cashierSettlementRoutes);
// "Paiements caissiers" (spec §22-§23, §26, §33): admin/manager only.
router.use('/admin/cashier-settlements', adminCashierSettlementRoutes);

module.exports = router;

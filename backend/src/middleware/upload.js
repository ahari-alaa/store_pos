const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const ApiError = require('../utils/ApiError');

const UPLOADS_ROOT = path.join(__dirname, '..', '..', 'uploads');
const PRODUCTS_DIR = path.join(UPLOADS_ROOT, 'products');
const EXPENSES_DIR = path.join(UPLOADS_ROOT, 'expenses');

fs.mkdirSync(PRODUCTS_DIR, { recursive: true });
fs.mkdirSync(EXPENSES_DIR, { recursive: true });

const ALLOWED_MIME_TYPES = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

// Receipts/invoices can reasonably be a scanned PDF as well as a photo.
const ALLOWED_RECEIPT_MIME_TYPES = {
  ...ALLOWED_MIME_TYPES,
  'application/pdf': '.pdf',
};

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, PRODUCTS_DIR),
  filename: (req, file, cb) => {
    const ext = ALLOWED_MIME_TYPES[file.mimetype] || path.extname(file.originalname) || '';
    // storeId prefix keeps filenames collision-free across stores and
    // makes stray files easy to trace back if something needs cleanup.
    cb(null, `${req.user.storeId}_${req.params.id}_${crypto.randomUUID()}${ext}`);
  },
});

function fileFilter(req, file, cb) {
  if (!ALLOWED_MIME_TYPES[file.mimetype]) {
    return cb(
      ApiError.badRequest('Only JPEG, PNG, or WebP images are allowed', 'INVALID_IMAGE_TYPE')
    );
  }
  cb(null, true);
}

const uploadProductImage = multer({
  storage,
  fileFilter,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
});

/** Public URL path for a filename saved under uploads/products/. */
function productImageUrl(filename) {
  return `/uploads/products/${filename}`;
}

/** Deletes a previously-uploaded product image file, if it exists. Never
 * throws — a missing/already-deleted file just means there's nothing to
 * clean up, which isn't worth failing the request over. */
function deleteProductImageFile(imageUrl) {
  if (!imageUrl || !imageUrl.startsWith('/uploads/products/')) return;
  const filePath = path.join(UPLOADS_ROOT, imageUrl.replace('/uploads/', ''));
  fs.unlink(filePath, () => {});
}

// ---------------------------------------------------------------------
// Expense receipts/invoices (spec §21). Mirrors the product-image
// pattern above exactly, just pointed at its own directory and mime
// allowlist (adds PDF, since a scanned paper receipt is a common case).
// ---------------------------------------------------------------------
const expenseReceiptStorage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, EXPENSES_DIR),
  filename: (req, file, cb) => {
    const ext =
      ALLOWED_RECEIPT_MIME_TYPES[file.mimetype] || path.extname(file.originalname) || '';
    cb(null, `${req.user.storeId}_${req.params.id}_${crypto.randomUUID()}${ext}`);
  },
});

function receiptFileFilter(req, file, cb) {
  if (!ALLOWED_RECEIPT_MIME_TYPES[file.mimetype]) {
    return cb(
      ApiError.badRequest('Only JPEG, PNG, WebP, or PDF files are allowed', 'INVALID_RECEIPT_TYPE')
    );
  }
  cb(null, true);
}

const uploadExpenseReceipt = multer({
  storage: expenseReceiptStorage,
  fileFilter: receiptFileFilter,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB — scanned PDFs run larger than photos
});

function expenseReceiptUrl(filename) {
  return `/uploads/expenses/${filename}`;
}

function deleteExpenseReceiptFile(receiptUrl) {
  if (!receiptUrl || !receiptUrl.startsWith('/uploads/expenses/')) return;
  const filePath = path.join(UPLOADS_ROOT, receiptUrl.replace('/uploads/', ''));
  fs.unlink(filePath, () => {});
}

module.exports = {
  uploadProductImage,
  productImageUrl,
  deleteProductImageFile,
  uploadExpenseReceipt,
  expenseReceiptUrl,
  deleteExpenseReceiptFile,
};

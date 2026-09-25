const { v4: uuidv4 } = require('uuid');
const ApiError = require('../utils/ApiError');
const supplierRepository = require('../repositories/supplierRepository');

async function list(storeId, query) {
  return supplierRepository.list(storeId, {
    search: query.search,
    isActive: query.is_active,
    page: query.page,
    pageSize: query.page_size,
  });
}

async function getById(storeId, id) {
  const supplier = await supplierRepository.findById(storeId, id);
  if (!supplier) throw ApiError.notFound('Supplier not found', 'SUPPLIER_NOT_FOUND');
  return supplier;
}

async function create(storeId, input) {
  const id = input.id || uuidv4();
  const existing = await supplierRepository.findById(storeId, id);
  if (existing) {
    throw ApiError.conflict('A supplier with this id already exists', 'SUPPLIER_EXISTS');
  }
  return supplierRepository.create(storeId, { ...input, id });
}

async function update(storeId, id, input) {
  const updated = await supplierRepository.update(storeId, id, input);
  if (!updated) throw ApiError.notFound('Supplier not found', 'SUPPLIER_NOT_FOUND');
  return updated;
}

async function remove(storeId, id) {
  const removed = await supplierRepository.softDelete(storeId, id);
  if (!removed) throw ApiError.notFound('Supplier not found', 'SUPPLIER_NOT_FOUND');
  return { id };
}

module.exports = { list, getById, create, update, remove };

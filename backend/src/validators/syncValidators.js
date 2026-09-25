const Joi = require('joi');

/**
 * The Flutter sync engine pushes a batch of queued operations at once.
 * Each entry mirrors one row of the local `sync_queue` table.
 * `payload` is intentionally a free-form object because its shape depends
 * on `entity_type` (sale vs expense vs inventory adjustment); each is
 * validated against its own schema inside syncService before being applied.
 */
const syncOperation = Joi.object({
  operation_id: Joi.string().uuid().required(),
  entity_type: Joi.string().valid('sale', 'expense', 'inventory_adjustment').required(),
  entity_id: Joi.string().uuid().required(),
  operation_type: Joi.string().valid('create', 'update', 'delete').required(),
  payload: Joi.object().required(),
  client_created_at: Joi.string().isoDate().required(),
});

const pushSync = Joi.object({
  operations: Joi.array().items(syncOperation).min(1).max(500).required(),
});

module.exports = { pushSync, syncOperation };

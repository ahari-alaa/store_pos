/* eslint-disable no-console */
const env = require('../config/env');

function ts() {
  return new Date().toISOString();
}

const logger = {
  info: (...args) => console.log(`[${ts()}] INFO `, ...args),
  warn: (...args) => console.warn(`[${ts()}] WARN `, ...args),
  error: (...args) => console.error(`[${ts()}] ERROR`, ...args),
  debug: (...args) => {
    if (env.nodeEnv !== 'production') console.debug(`[${ts()}] DEBUG`, ...args);
  },
};

module.exports = logger;

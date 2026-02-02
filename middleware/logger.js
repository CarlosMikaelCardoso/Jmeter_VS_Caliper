/* middleware/logger.js */
const fs = require('fs');

const getTimestamp = () => new Date().toISOString();

const logger = {
    info: (msg) => console.log(`[${getTimestamp()}] [INFO] ${msg}`),
    warn: (msg) => console.warn(`[${getTimestamp()}] [WARN] ${msg}`),
    error: (msg) => console.error(`[${getTimestamp()}] [ERROR] ${msg}`),
    
    // Opcional: Salvar em arquivo se quiser
    // logToFile: (msg) => fs.appendFileSync('api.log', `${getTimestamp()} ${msg}\n`)
};

module.exports = logger;
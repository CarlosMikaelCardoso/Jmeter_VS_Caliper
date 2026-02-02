'use strict';
const logger = require('../logger');

module.exports.run = async (contract, args) => {
    // Query não precisa de retry de MVCC (é leitura) e nem de submitTransaction
    // args esperados: [userID]
    const stringArgs = args.map(String);
    
    logger.info(`[Query] query | Args: ${JSON.stringify(stringArgs)}`);
    
    const result = await contract.evaluateTransaction('query', ...stringArgs);
    return { result, latency: 0 }; // Latência de query é instantânea no client-side
};
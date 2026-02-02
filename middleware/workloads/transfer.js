'use strict';
const { submitWithRetry } = require('../helper');

module.exports.run = async (contract, args) => {
    // args esperados: [sourceID, destID, amount]
    // Esta é a função que mais gera conflito MVCC
    return await submitWithRetry(contract, 'transfer', args);
};
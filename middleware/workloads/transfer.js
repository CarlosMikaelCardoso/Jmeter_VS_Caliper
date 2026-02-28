'use strict';
const { submitWithRetry } = require('../helper');

module.exports.run = async (contract, args) => {
    // args esperados: [sourceID, destID, amount]
    return await submitWithRetry(contract, 'transfer', args);
};
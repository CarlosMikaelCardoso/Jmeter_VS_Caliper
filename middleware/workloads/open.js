'use strict';
const { submitWithRetry } = require('../helper');

module.exports.run = async (contract, args) => {
    // args esperados: [userID, money]
    return await submitWithRetry(contract, 'open', args);
};
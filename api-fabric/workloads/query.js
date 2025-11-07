'use strict';

class Query {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * Monta e envia a transação 'query'.
     * @param {string} accountId A conta a ser consultada.
     * @returns {Promise<string>} O resultado da consulta (saldo).
     */
    async submitTransaction(accountId) {
        const args = [accountId];
        const resultBuffer = await this.connector.query('query', args);
        return resultBuffer.toString('utf8');
    }
}

module.exports = Query;

'use strict';

class Open {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * Monta e envia a transação 'open'.
     * @param {string} accountId A conta a ser criada.
     * @param {number} amount O valor inicial.
     * @returns {Promise<Object>} { result, latency_ms }
     */
    async submitTransaction(accountId, amount) {
        const args = [accountId, amount.toString()];
        // DEVE chamar invoke com a função 'open'
        return await this.connector.invoke('open', args);
    }
}

module.exports = Open;
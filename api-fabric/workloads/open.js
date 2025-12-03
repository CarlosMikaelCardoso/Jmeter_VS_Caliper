'use strict';

class Open {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * Monta e envia a transação 'query'.
     * @param {string} accountId A conta a ser consultada.
     * @returns {Promise<Object>} Objeto com saldo (string) e latência.
     */
    async submitTransaction(accountId) {
        const args = [accountId];
        
        // * Recebe o objeto { result, latency_ms } do connector
        const response = await this.connector.query('query', args);
        
        // * Retorna o valor processado mas mantém a latência
        return {
            balance: response.result.toString('utf8'),
            latency_ms: response.latency_ms
        };
    }
}

module.exports = Open;

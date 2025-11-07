'use strict';

class Open {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * Monta e envia a transação 'open'.
     * @param {string} accountId A conta a ser criada.
     * @param {number} amount O valor inicial.
     * @returns {Promise<any>}
     */
    async submitTransaction(accountId, amount) {
        // Converte todos os argumentos para string, como o Fabric espera
        const args = [accountId, amount.toString()];
        return await this.connector.invoke('open', args);
    }
}

module.exports = Open;

'use strict';

class Transfer {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * Monta e envia a transação 'transfer'.
     * @param {string} from Conta de origem.
     * @param {string} to Conta de destino.
     * @param {number} amount Valor a transferir.
     * @returns {Promise<Object>} Resultado e latência.
     */
    async submitTransaction(from, to, amount) {
        // Argumentos: [account1, account2, money]
        const args = [from, to, amount.toString()];
        
        // Chama invoke (escrita) no conector
        return await this.connector.invoke('transfer', args);
    }
}

module.exports = Transfer;
'use strict';

class Open {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * @param {string} accountId 
     * @param {number} amount 
     */
    async submitTransaction(accountId, amount) {
        // Argumentos devem ser strings
        const args = [accountId, amount.toString()];
        
        // ATENÇÃO: A string 'open' aqui deve bater com o "if function == 'open'" no seu Go chaincode
        return await this.connector.invoke('open', args);
    }
}

module.exports = Open;
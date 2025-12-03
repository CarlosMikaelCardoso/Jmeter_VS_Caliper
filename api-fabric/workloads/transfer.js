'use strict';

class Transfer {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    async submitTransaction(from, to, amount) {
        const args = [from, to, amount.toString()];
        // Chama a função 'transfer' do chaincode
        return await this.connector.invoke('transfer', args);
    }
}

module.exports = Transfer;
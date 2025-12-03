'use strict';

class Transfer {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    async submitTransaction(from, to, amount) {
        const args = [from, to, amount.toString()];
        return await this.connector.invoke('transfer', args);
    }
}

module.exports = Transfer;
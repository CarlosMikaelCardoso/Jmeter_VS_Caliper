'use strict';

class TransferWorkload {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }
    async submitTransaction(sourceId, targetId, amount) {
        return await this.connector.invoke('transfer', [sourceId, targetId, amount.toString()]);
    }
}
module.exports = TransferWorkload;
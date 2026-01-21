'use strict';

class OpenWorkload {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }
    async submitTransaction(accountId, amount) {
        // Recebe o ID direto do JMeter (ex: r1_user_1)
        return await this.connector.invoke('open', [accountId, amount.toString()]);
    }
}
module.exports = OpenWorkload;
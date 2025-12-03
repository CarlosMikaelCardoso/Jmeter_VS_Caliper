'use strict';

class Query {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    async submitTransaction(accountId) {
        const args = [accountId];
        // Query é evaluateTransaction (não invoke)
        const response = await this.connector.query('query', args);
        
        return {
            balance: response.result.toString('utf8'),
            latency_ms: response.latency_ms
        };
    }
}

module.exports = Query;
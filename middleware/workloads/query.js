'use strict';

class QueryWorkload {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }
    async submitTransaction(accountId) {
        const response = await this.connector.query('query', [accountId]);
        return {
            balance: response.result.toString('utf8'),
            latency_ms: response.latency_ms
        };
    }
}
module.exports = QueryWorkload;
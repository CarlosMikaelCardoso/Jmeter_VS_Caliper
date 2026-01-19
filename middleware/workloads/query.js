'use strict';

// ______________________________________________________________________
// MODIFICADO: Imports para ler o arquivo de rodada
const fs = require('fs');
const path = require('path');
// ______________________________________________________________________

class Query {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    async submitTransaction(accountId) {
        // ______________________________________________________________________
        // MODIFICADO: Lógica de Isolamento
        let roundPrefix = 'r0_';
        try {
            const roundPath = path.resolve(__dirname, '..', 'current_round.txt');
            if (fs.existsSync(roundPath)) {
                const roundId = fs.readFileSync(roundPath, 'utf8').trim();
                roundPrefix = `r${roundId}_`;
            }
        } catch (err) {
            // Silencioso em caso de erro de leitura para não poluir log de performance
        }

        const uniqueAccount = roundPrefix + accountId;
        // ______________________________________________________________________

        const args = [uniqueAccount];
        // Query é evaluateTransaction (não invoke)
        const response = await this.connector.query('query', args);
        
        return {
            balance: response.result.toString('utf8'),
            latency_ms: response.latency_ms
        };
    }
}

module.exports = Query;
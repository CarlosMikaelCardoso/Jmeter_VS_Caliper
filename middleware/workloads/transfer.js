'use strict';

// ______________________________________________________________________
// MODIFICADO: Imports para ler o arquivo de rodada
const fs = require('fs');
const path = require('path');
// ______________________________________________________________________

class Transfer {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    async submitTransaction(sourceId, targetId, amount) {
        // ______________________________________________________________________
        // MODIFICADO: Lógica de Isolamento
        let roundPrefix = 'r0_';
        try {
            const roundPath = path.resolve(__dirname, '..', 'current_round.txt');
            if (fs.existsSync(roundPath)) {
                const roundId = fs.readFileSync(roundPath, 'utf8').trim();
                roundPrefix = `r${roundId}_`;
            }
        } catch (err) { }

        // Aplica prefixo em ambas as contas
        const uniqueSource = roundPrefix + sourceId;
        const uniqueTarget = roundPrefix + targetId;
        // ______________________________________________________________________

        const args = [uniqueSource, uniqueTarget, amount.toString()];
        
        return await this.connector.invoke('transfer', args);
    }
}

module.exports = Transfer;
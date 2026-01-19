'use strict';

// ______________________________________________________________________
// MODIFICADO: Imports para ler o arquivo de rodada
const fs = require('fs');
const path = require('path');
// ______________________________________________________________________

class Open {
    constructor(fabricConnector) {
        this.connector = fabricConnector;
    }

    /**
     * @param {string} accountId 
     * @param {number} amount 
     */
    async submitTransaction(accountId, amount) {
        // ______________________________________________________________________
        // MODIFICADO: Lógica de Isolamento - Ler Round e Prefixo
        let roundPrefix = 'r0_';
        try {
            // Caminho para o arquivo na pasta 'middleware' (pai de 'workloads')
            const roundPath = path.resolve(__dirname, '..', 'current_round.txt');
            if (fs.existsSync(roundPath)) {
                const roundId = fs.readFileSync(roundPath, 'utf8').trim();
                roundPrefix = `r${roundId}_`;
            }
        } catch (err) {
            console.error('[OPEN] Erro lendo round:', err.message);
        }

        // Aplica o prefixo na conta (ex: "user1" -> "r1_user1")
        const uniqueAccount = roundPrefix + accountId;
        // ______________________________________________________________________

        // Argumentos devem ser strings
        const args = [uniqueAccount, amount.toString()];
        
        // ATENÇÃO: A string 'open' aqui deve bater com o "if function == 'open'" no seu Go chaincode
        return await this.connector.invoke('open', args);
    }
}

module.exports = Open;
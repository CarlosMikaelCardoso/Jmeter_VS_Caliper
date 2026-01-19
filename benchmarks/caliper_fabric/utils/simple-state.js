/*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

'use strict';

// ______________________________________________________________________
// MODIFICADO: Imports necessários para ler o arquivo de rodada
const fs = require('fs');
const path = require('path');
// ______________________________________________________________________

const Dictionary = 'abcdefghijklmnopqrstuvwxyz';

/**
 * Class for managing simple account states.
 */
class SimpleState {

    /**
     * Initializes the instance.
     */
    constructor(workerIndex, initialMoney, moneyToTransfer, accounts = 0) {
        this.accountsGenerated = accounts;
        this.initialMoney = initialMoney;
        this.moneyToTransfer = moneyToTransfer;

        // Lê o arquivo current_round.txt para obter o ID da rodada
        let roundId = '0';
        try {
            // O arquivo deve estar na pasta 'benchmarks/caliper_fabric', que é '..' relativo a 'utils'
            const roundFilePath = path.join(__dirname, '..', 'current_round.txt');
            
            if (fs.existsSync(roundFilePath)) {
                roundId = fs.readFileSync(roundFilePath, 'utf8').trim();
            }
        } catch (e) {
            console.log('Aviso: Não foi possível ler current_round.txt, assumindo rodada 0. Erro:', e.message);
        }

        // Gera um prefixo único e legível. 
        // Ex: "w0_r1_" -> Worker 0, Rodada 1.
        // Isso garante que as chaves nunca colidam entre rodadas diferentes.
        this.accountPrefix = `w${workerIndex}_r${roundId}_`;
    }

    /**
     * Generate string by picking characters from the dictionary variable.
     * @param {number} number Character to select.
     * @returns {string} string Generated string based on the input number.
     * @private
     */
    _get26Num(number){
        let result = '';

        while(number > 0) {
            result += Dictionary.charAt(number % Dictionary.length);
            number = parseInt(number / Dictionary.length);
        }

        return result;
    }

    /**
     * Construct an account key from its index.
     * @param {number} index The account index.
     * @return {string} The account key.
     * @private
     */
    _getAccountKey(index) {
        // Agora usamos o prefixo robusto + a conversão alfabética do índice
        return this.accountPrefix + this._get26Num(index);
    }

    /**
     * Returns a random account key.
     * @return {string} Account key.
     * @private
     */
    _getRandomAccount() {
        // choose a random TX/account index based on the existing range, and restore the account name from the fragments
        const index = Math.ceil(Math.random() * this.accountsGenerated);
        return this._getAccountKey(index);
    }

    /**
     * Get the arguments for creating a new account.
     * @returns {object} The account arguments.
     */
    getOpenAccountArguments() {
        this.accountsGenerated++;
        return {
            account: this._getAccountKey(this.accountsGenerated),
            money: this.initialMoney
        };
    }

    /**
     * Get the arguments for querying an account.
     * @returns {object} The account arguments.
     */
    getQueryArguments() {
        return {
            account: this._getRandomAccount()
        };
    }

    /**
     * Get the arguments for transfering money between accounts.
     * @returns {object} The account arguments.
     */
    getTransferArguments() {
        return {
            source: this._getRandomAccount(),
            target: this._getRandomAccount(),
            amount: this.moneyToTransfer
        };
    }
}

module.exports = SimpleState;
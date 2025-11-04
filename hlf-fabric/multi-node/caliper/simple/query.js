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

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

/**
 * Workload module for the 'asset' chaincode ReadAsset function.
 */
class ReadAssetWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    /**
     * Assemble TXs for ReadAsset.
     * @return {Promise<object>} The promise for the transaction payload.
     */
    async submitTransaction() {
        this.txIndex++;
        // Lê o mesmo asset que foi criado no round 'open'
        const assetID = `asset_${this.workerIndex}_${this.txIndex}`;

        const args = {
            contractId: 'asset', // <--- NOME DO SEU CHAINCODE
            contractFunction: 'ReadAsset', // <--- NOME DA SUA FUNÇÃO
            contractArguments: [assetID], // id
            readOnly: true
        };

        return this.sutAdapter.sendRequests(args);
    }
}

/**
 * Create a new instance of the workload module.
 * @return {WorkloadModuleInterface}
 */
function createWorkloadModule() {
    return new ReadAssetWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
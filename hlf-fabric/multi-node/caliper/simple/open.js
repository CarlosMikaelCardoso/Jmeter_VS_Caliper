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
 * Workload module for the 'asset' chaincode CreateAsset function.
 */
class CreateAssetWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 3000;
    }

    /**
     * Assemble TXs for CreateAsset.
     * @return {Promise<object>} The promise for the transaction payload.
     */
    async submitTransaction() {
        this.txIndex++;
        const assetID = `asset_${this.workerIndex}_${this.txIndex}`;
        
        // Crie os 5 argumentos que o seu chaincode 'CreateAsset' espera
        const args = {
            contractId: 'asset', 
            contractFunction: 'CreateAsset', 
            contractArguments: [
                assetID,         // id
                'blue',          // color
                '10',            // size
                'Caliper',       // owner
                '100'            // appraisedValue
            ],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(args);
    }
}

/**
 * Create a new instance of the workload module.
 * @return {WorkloadModuleInterface}
 */
function createWorkloadModule() {
    return new CreateAssetWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
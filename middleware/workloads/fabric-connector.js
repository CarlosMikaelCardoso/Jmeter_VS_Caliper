/* middleware/workloads/fabric-connector.js */
'use strict';

const { Gateway, Wallets, DefaultEventHandlerStrategies } = require('fabric-network');
const fs = require('fs');
const path = require('path');
const logger = require('../logger');

async function connectToNetwork() {
    try {
        const ccpPath = path.resolve(__dirname, '..', 'connection-profile.json');
        if (!fs.existsSync(ccpPath)) {
            throw new Error(`Connection profile inexistente: ${ccpPath}`);
        }
        const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

        const walletPath = path.join(process.cwd(), 'wallet');
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        const identity = await wallet.get('admin');
        if (!identity) {
            throw new Error(`Identidade 'admin' não encontrada na wallet.`);
        }

        const gateway = new Gateway();
        
        // CONEXÃO SÍNCRONA (Igual ao Caliper)
        await gateway.connect(ccp, {
            wallet,
            identity: 'admin',
            discovery: { enabled: true, asLocalhost: true },
            eventHandlerOptions: {
                // Espera o COMMIT em todos os peers da organização
                strategy: DefaultEventHandlerStrategies.MSPID_SCOPE_ALLFORTX,
                commitTimeout: 5 
            }
        });

        const network = await gateway.getNetwork('gercom');
        // Tenta 'simple' (Caliper padrão) ou 'basic'
        const contract = network.getContract('simple'); 

        logger.info('✅ Conectado ao Fabric (Modo Síncrono - Wait for Commit)');
        return contract;

    } catch (error) {
        logger.error(`Falha ao conectar: ${error.message}`);
        return null;
    }
}

module.exports = { connectToNetwork };
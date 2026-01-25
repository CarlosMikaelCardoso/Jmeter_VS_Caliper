'use strict';

const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');

// Cache do Connection Profile em memória para evitar leitura de disco repetitiva
let cachedCCP = null;

class FabricConnector {
    constructor() {
        this.gateway = null;
        this.contract = null;
    }

    async initialize(userId, channelName, chaincodeName) {
        try {
            console.log(`[Connector] Inicializando para ${userId}...`);
            const walletPath = path.join(process.cwd(), 'wallet');
            const wallet = await Wallets.newFileSystemWallet(walletPath);

            const identity = await wallet.get(userId);
            if (!identity) {
                throw new Error(`Identidade "${userId}" não encontrada na carteira.`);
            }

            // Ler CCP apenas se ainda não estiver em cache
            if (!cachedCCP) {
                const ccpPath = path.resolve(__dirname, '..', 'config', 'connection-profile.json');
                if (!fs.existsSync(ccpPath)) {
                    throw new Error(`Perfil de conexão não encontrado em ${ccpPath}`);
                }
                cachedCCP = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
            }

            this.gateway = new Gateway();
            
            // Reutiliza o cachedCCP
            await this.gateway.connect(cachedCCP, {
                wallet,
                identity: userId,
                discovery: { enabled: true, asLocalhost: true }
            });

            const network = await this.gateway.getNetwork(channelName);
            this.contract = network.getContract(chaincodeName);
            console.log(`[Connector] Conectado ao canal: ${channelName}`);

        } catch (error) {
            console.error(`Falha ao inicializar conector: ${error}`);
            process.exit(1);
        }
    }

    // Mede o tempo de Query (Leitura)
    async query(funcName, args = []) {
        if (!this.contract) throw new Error('Contrato não inicializado.');
        
        const start = Date.now();
        const result = await this.contract.evaluateTransaction(funcName, ...args);
        const latency = Date.now() - start;

        return { result, latency_ms: latency };
    }

    // Mede o tempo de Invoke (Escrita - Consenso)
    async invoke(funcName, args = []) {
        if (!this.contract) throw new Error('Contrato não inicializado.');

        const start = Date.now();
        const result = await this.contract.submitTransaction(funcName, ...args);
        const latency = Date.now() - start;

        return { result, latency_ms: latency };
    }

    async disconnect() {
        if (this.gateway) {
            await this.gateway.disconnect();
        }
    }
}

module.exports = FabricConnector;

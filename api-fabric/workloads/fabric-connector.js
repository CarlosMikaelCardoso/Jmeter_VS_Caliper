'use strict';

const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');

class FabricConnector {
    constructor() {
        this.gateway = null;
        this.contract = null;
    }

    /**
     * Inicializa a conexão com o Gateway do Fabric.
     */
    async initialize(userId, channelName, chaincodeName) {
        try {
            console.log('Inicializando conector do Fabric...');
            const walletPath = path.join(process.cwd(), 'wallet');
            const wallet = await Wallets.newFileSystemWallet(walletPath);

            // Verifica se a identidade do usuário existe
            const identity = await wallet.get(userId);
            if (!identity) {
                console.error(`Erro: A identidade "${userId}" não foi encontrada na carteira.`);
                console.error('Execute "npm run enrollAdmin" primeiro.');
                process.exit(1);
            }

            // Carrega o perfil de conexão
            const ccpPath = path.resolve(__dirname, '..', 'config', 'connection-profile.json');
            if (!fs.existsSync(ccpPath)) {
                throw new Error(`Perfil de conexão não encontrado em ${ccpPath}`);
            }
            const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));

            // Conecta ao Gateway
            this.gateway = new Gateway();
            await this.gateway.connect(ccp, {
                wallet,
                identity: userId,
                discovery: { enabled: true, asLocalhost: true } // Assumindo que a API roda no mesmo host que o Docker
            });

            // Obtém o canal e o contrato
            const network = await this.gateway.getNetwork(channelName);
            this.contract = network.getContract(chaincodeName);

            console.log('Conector do Fabric inicializado com sucesso.');
            console.log(`Canal: ${channelName}, Chaincode: ${chaincodeName}`);

        } catch (error) {
            console.error(`Falha ao inicializar o conector do Fabric: ${error}`);
            process.exit(1);
        }
    }

/**
     * Envia uma transação de consulta (read-only).
     * @param {string} funcName Nome da função do chaincode.
     * @param {string[]} args Argumentos para a função.
     * @returns {Promise<Object>} Objeto contendo o resultado e a latência.
     */
    async query(funcName, args = []) {
        if (!this.contract) {
            throw new Error('Contrato não inicializado.');
        }
        // console.log(`(Query) Chamando: ${funcName}(${args.join(',')})`); // Comentado para reduzir I/O

        // * Início da medição precisa
        const startTime = Date.now();
        
        const result = await this.contract.evaluateTransaction(funcName, ...args);

        // * Fim da medição
        const latency = Date.now() - startTime;

        // * Retorna estrutura rica com dados e métricas
        return {
            result: result,
            latency_ms: latency
        };
    }

    /**
     * Envia uma transação de invoke (escrita).
     * @param {string} funcName Nome da função do chaincode.
     * @param {string[]} args Argumentos para a função.
     * @returns {Promise<Object>} Objeto contendo o resultado e a latência.
     */
    async invoke(funcName, args = []) {
        if (!this.contract) {
            throw new Error('Contrato não inicializado.');
        }
        // console.log(`(Invoke) Chamando: ${funcName}(${args.join(',')})`); 

        // * Início da medição precisa
        const startTime = Date.now();

        // submitTransaction espera pela submissão E commit no Peer (igual ao Caliper)
        const result = await this.contract.submitTransaction(funcName, ...args);

        // * Fim da medição
        const latency = Date.now() - startTime;

        return {
            result: result,
            latency_ms: latency
        };
    }

    /**
     * Desconecta do Gateway.
     */
    async disconnect() {
        if (this.gateway) {
            await this.gateway.disconnect();
            console.log('Desconectado do Gateway do Fabric.');
        }
    }
}

module.exports = FabricConnector;

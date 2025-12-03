/*
 * Script para "limpar" o ledger, resetando o saldo de todas as 
 * contas criadas pelo JMeter para 0.
 */
'use strict';

const { Gateway, Wallets } = require('fabric-network');
const fs = require('fs');
const path = require('path');

// --- PONTO DE CONFIGURAÇÃO ---
const NUMBER_OF_ACCOUNTS = 1000;
const CONCURRENT_JOBS = 10; // Número de transações em paralelo
const ACCOUNT_PREFIX = 'userJmeter';
const RESET_VALUE = '0';

// Configurações da API (devem ser as mesmas do 'npm start')
const CHANNEL_NAME = process.env.CHANNEL_NAME || 'gercom';
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple';
const API_USER = process.env.API_USER || 'admin';
// --- FIM DA CONFIGURAÇÃO ---


/**
 * Lógica de geração de nomes de conta, copiada do seu script 'run_jmeter_api.sh'.
 *
 */
function get26Num(n) {
    const DICTIONARY = 'abcdefghijklmnopqrstuvwxyz';
    let result = '';
    while (n >= 0) {
        result = DICTIONARY.charAt(n % DICTIONARY.length) + result;
        n = Math.floor(n / DICTIONARY.length) - 1;
    }
    return result;
}

/**
 * Função "Worker" para processar a fila de contas em paralelo.
 */
async function worker(id, contract, accountQueue, counters) {
    while (true) {
        const accountName = accountQueue.pop();
        if (!accountName) {
            // Fila vazia, worker termina
            return;
        }

        try {
            // --- MODIFICAÇÃO AQUI ---
            // Chamando 'delete' (minúsculo) com base na dica do seu .go
            await contract.submitTransaction('delete', accountName);
            console.log(`[Worker ${id}] Conta ${accountName} deletada.`);
            // --- FIM DA MODIFICAÇÃO ---

            counters.success++;
        } catch (e) {
            console.error(`[Worker ${id}] Falha ao deletar ${accountName}: ${e.message}`);
            counters.error++;
        }
    }
}


async function main() {
    let gateway;
    try {
        console.log(`--- Iniciando Script de Limpeza do Ledger ---`);
        console.log(`A resetar ${NUMBER_OF_ACCOUNTS} contas no canal '${CHANNEL_NAME}'...`);

        // 1. Gerar a lista de todas as contas
        const accountQueue = [];
        for (let i = 0; i < NUMBER_OF_ACCOUNTS; i++) {
            accountQueue.push(ACCOUNT_PREFIX + get26Num(i));
        }

        // 2. Conectar ao Gateway (lógica de conexão da API)
        const ccpPath = path.resolve(__dirname, '..', 'config', 'connection-profile.json');
        const ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
        
        const walletPath = path.join(process.cwd(), 'wallet');
        const wallet = await Wallets.newFileSystemWallet(walletPath);
        
        const identity = await wallet.get(API_USER);
        if (!identity) {
            console.error(`Erro: Identidade '${API_USER}' não encontrada na carteira.`);
            console.error('Execute "npm run enrollAdmin" primeiro.');
            return;
        }

        gateway = new Gateway();
        await gateway.connect(ccp, {
            wallet,
            identity: API_USER,
            discovery: { enabled: true, asLocalhost: true }
        });

        // 3. Obter o contrato
        const network = await gateway.getNetwork(CHANNEL_NAME);
        const contract = network.getContract(CHAINCODE_NAME);

        // 4. Iniciar os workers em paralelo
        console.log(`Iniciando ${CONCURRENT_JOBS} workers paralelos...`);
        const counters = { success: 0, error: 0 };
        const workerPromises = [];
        
        for (let i = 1; i <= CONCURRENT_JOBS; i++) {
            workerPromises.push(worker(i, contract, accountQueue, counters));
        }

        // 5. Aguardar a conclusão de todos os workers
        await Promise.all(workerPromises);

        console.log("\n--- Limpeza Concluída ---");
        console.log(`Contas resetadas com sucesso: ${counters.success}`);
        console.log(`Falhas: ${counters.error}`);

    } catch (error) {
        console.error(`\nFalha catastrófica durante a limpeza: ${error}`);
        process.exit(1);
    } finally {
        // 6. Desconectar o Gateway
        if (gateway) {
            await gateway.disconnect();
            console.log("Desconectado do Gateway.");
        }
    }
}

main();
// --- Variáveis de Ambiente Necessárias ---
// export CHANNEL_NAME="mychannel"
// export CHAINCODE_NAME="simple"
// export API_USER="admin" 
// export API_WORKERS=5  (Número de conexões físicas/Gateways)

const express = require('express');

// Workloads do Fabric
const FabricConnector = require('./workloads/fabric-connector.js');
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');

const app = express();
const port = 3000;
app.use(express.json());

// --- Configuração das Variáveis de Ambiente ---
const CHANNEL_NAME = process.env.CHANNEL_NAME || 'mychannel';
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple';
const API_USER = process.env.API_USER || 'admin';

// Configuração de Concorrência
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);

// --- Pool de Workers (Proxy Stateful) ---
// Mantém conexões persistentes (Gateways) abertas para evitar overhead de handshake SSL
const workerPool = [];
let currentWorkerIndex = 0;

// Função para obter o próximo worker (Round-Robin)
// Distribui as requisições rotativamente entre as conexões disponíveis
function getNextWorker() {
    if (workerPool.length === 0) {
        throw new Error("Nenhum worker disponível. A API ainda está inicializando?");
    }
    const worker = workerPool[currentWorkerIndex];
    currentWorkerIndex = (currentWorkerIndex + 1) % workerPool.length;
    return worker;
}

// --- Endpoints de Transação (Síncronos) ---

/**
 * Rota para abrir conta.
 * O sufixo "-async" foi mantido para compatibilidade com o script JMX,
 * mas o comportamento agora é SÍNCRONO (bloqueante).
 */
app.post('/open-async', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Campos obrigatórios ausentes (accountId, amount)." });
    }

    try {
        // 1. Seleciona uma conexão persistente
        const worker = getNextWorker();

        // 2. Executa a transação e ESPERA a confirmação do Fabric (Submit -> Orderer -> Peer Commit)
        // O objeto 'response' deve vir do conector com { result, latency_ms }
        const response = await worker.workloads.open.submitTransaction(accountId, amount);

        // 3. Retorna sucesso e a latência pura do SDK para o JMeter
        res.status(200).json({ 
            status: "OK",
            message: `Conta ${accountId} criada.`,
            latency_ms: response.latency_ms, // Métrica crítica para comparação com Caliper
            result: response.result ? response.result.toString() : null
        });

    } catch (e) {
        console.error(`Erro em /open-async (Worker ID incerto): ${e.message}`);
        res.status(500).json({ error: e.message });
    }
});

/**
 * Rota para transferência.
 * Comportamento SÍNCRONO.
 */
app.post('/transfer-async', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Campos obrigatórios ausentes (from, to, amount)." });
    }

    try {
        const worker = getNextWorker();

        // Espera todo o fluxo de consenso
        const response = await worker.workloads.transfer.submitTransaction(from, to, amount);

        res.status(200).json({ 
            status: "OK", 
            message: "Transferência realizada.",
            latency_ms: response.latency_ms,
            result: response.result ? response.result.toString() : null
        });

    } catch (e) {
        console.error(`Erro em /transfer-async: ${e.message}`);
        res.status(500).json({ error: e.message });
    }
});

/**
 * Rota para consulta (Query).
 * Já era síncrona, mas agora repassa a métrica de latência.
 */
app.get('/query/:accountId', async (req, res) => {
    const { accountId } = req.params;
    
    try {
        const worker = getNextWorker();
        
        // Query (evaluateTransaction) é mais rápida pois não vai para o Orderer
        const response = await worker.workloads.query.submitTransaction(accountId);
        
        res.status(200).json({ 
            accountId: accountId, 
            balance: response.balance, // query.js já converte buffer para string em 'balance'
            latency_ms: response.latency_ms
        });

    } catch (error) {
        console.error(`Falha ao executar 'query':`, error);
        res.status(500).json({ error: "Falha na query", details: error.message });
    }
});

// --- Endpoints de Controle/Monitoramento ---
// Mantidos para verificar saúde da API, mas 'queue' sempre estará vazia/inativa.
app.get('/health', (req, res) => {
    res.status(200).json({
        status: 'Active',
        activeWorkers: workerPool.length,
        mode: 'Synchronous Stateful Proxy'
    });
});

// --- Inicialização do Servidor e Workers ---
async function startServer() {
    console.log(`--- Inicializando API Fabric (Modo Paridade Caliper) ---`);
    console.log(`Workers Físicos (Conexões Persistentes): ${NUM_WORKERS}`);

    try {
        // Cria N conexões independentes, isolando os contextos como no Caliper
        for (let i = 0; i < NUM_WORKERS; i++) {
            console.log(`Iniciando Worker #${i + 1}...`);
            
            const connector = new FabricConnector();
            // Cada connector cria seu próprio Gateway e conexão gRPC persistente
            await connector.initialize(API_USER, CHANNEL_NAME, CHAINCODE_NAME);
            
            // Cria workloads vinculados a este conector específico
            const workloads = {
                open: new OpenWorkload(connector),
                query: new QueryWorkload(connector),
                transfer: new TransferWorkload(connector)
            };

            workerPool.push({
                id: i + 1,
                connector: connector,
                workloads: workloads
            });
        }

        console.log(`Todos os ${workerPool.length} workers foram inicializados com sucesso.`);

        app.listen(port, () => {
            console.log(`Servidor da API rodando em http://localhost:${port}`);
            console.log(`Canal: ${CHANNEL_NAME} | Chaincode: ${CHAINCODE_NAME} | Usuário: ${API_USER}`);
            console.log(`NOTA: A API agora opera em modo SÍNCRONO. Ajuste o timeout do JMeter.`);
        });

    } catch (error) {
        console.error("Erro fatal na inicialização dos workers:", error);
        process.exit(1);
    }
}

startServer();
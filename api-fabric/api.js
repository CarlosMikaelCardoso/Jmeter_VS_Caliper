// --- Variáveis de Ambiente Necessárias ---
// export CHANNEL_NAME="mychannel"
// export CHAINCODE_NAME="simple"
// export API_USER="admin" 
// export API_WORKERS=5

const express = require('express');

// Workloads do Fabric
const FabricConnector = require('./workloads/fabric-connector.js');
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');

const app = express();
const port = 3000;
app.use(express.json());

// --- Configuração ---
const CHANNEL_NAME = process.env.CHANNEL_NAME || 'mychannel';
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple';
const API_USER = process.env.API_USER || 'admin';
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);

// --- Pool de Workers ---
const workerPool = [];
let currentWorkerIndex = 0;

function getNextWorker() {
    if (workerPool.length === 0) throw new Error("API não inicializada.");
    const worker = workerPool[currentWorkerIndex];
    currentWorkerIndex = (currentWorkerIndex + 1) % workerPool.length;
    return worker;
}

// --- Endpoints Assíncronos (Fire-and-Forget) ---

app.post('/open-async', (req, res) => {
    const { accountId, amount } = req.body;
    
    // 1. Validação Rápida
    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Dados incompletos" });
    }

    // 2. Resposta Imediata para o JMeter (Alta Taxa de Envio)
    res.status(202).json({ 
        status: "Accepted", 
        message: "Transação enviada para processamento." 
    });

    // 3. Processamento em Background (A "Mágica" do Caliper)
    (async () => {
        try {
            const worker = getNextWorker();
            
            // A medição de tempo acontece DENTRO deste método
            const response = await worker.workloads.open.submitTransaction(accountId, amount);
            
            // Logamos a latência real no console da API para monitoramento
            console.log(`[OPEN] Sucesso: Conta ${accountId} | Latência Fabric: ${response.latency_ms}ms`);
        } catch (e) {
            console.error(`[OPEN] Erro Background (${accountId}): ${e.message}`);
        }
    })();
});

app.post('/transfer-async', (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Dados incompletos" });
    }

    res.status(202).json({ status: "Accepted", message: "Transferência em processamento." });

    (async () => {
        try {
            const worker = getNextWorker();
            const response = await worker.workloads.transfer.submitTransaction(from, to, amount);
            console.log(`[TRANSFER] Sucesso: ${from}->${to} | Latência Fabric: ${response.latency_ms}ms`);
        } catch (e) {
            console.error(`[TRANSFER] Erro Background: ${e.message}`);
        }
    })();
});

// Query continua síncrona pois é leitura rápida e o JMeter precisa do dado
app.get('/query/:accountId', async (req, res) => {
    try {
        const worker = getNextWorker();
        const response = await worker.workloads.query.submitTransaction(req.params.accountId);
        res.status(200).json({ 
            balance: response.balance, 
            latency_ms: response.latency_ms 
        });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// --- Inicialização ---
async function startServer() {
    try {
        console.log(`Iniciando ${NUM_WORKERS} workers persistentes...`);
        for (let i = 0; i < NUM_WORKERS; i++) {
            const connector = new FabricConnector();
            await connector.initialize(API_USER, CHANNEL_NAME, CHAINCODE_NAME);
            workerPool.push({
                id: i,
                workloads: {
                    open: new OpenWorkload(connector),
                    query: new QueryWorkload(connector),
                    transfer: new TransferWorkload(connector)
                }
            });
        }
        
        // --- CORREÇÃO AQUI: Iniciando o servidor Express ---
        app.listen(port, () => {
            console.log(`API Fabric Assíncrona rodando em http://localhost:${port}`);
        });

    } catch (e) {
        console.error("Erro fatal:", e);
        process.exit(1);
    }
}

startServer();
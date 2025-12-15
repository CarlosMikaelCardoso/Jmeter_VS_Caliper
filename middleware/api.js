// --- Variáveis de Ambiente ---
// export CHANNEL_NAME="mychannel"
// export CHAINCODE_NAME="simple"
// export API_USER="admin" 
// export API_WORKERS=5

const express = require('express');
const fs = require('fs');
const path = require('path');

const FabricConnector = require('./workloads/fabric-connector.js');
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');

const app = express();
const port = 3000;
app.use(express.json());

const CHANNEL_NAME = process.env.CHANNEL_NAME || 'mychannel';
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple';
const API_USER = process.env.API_USER || 'admin';
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);

// Caminho do log para o script Python ler depois
const LOG_FILE_PATH = path.join(__dirname, '../results/jmeter_runs/backend_errors.log');

const workerPool = [];
let currentWorkerIndex = 0;

// Controle de Backpressure
const MAX_PENDING_TX = 2000; 
let pendingTransactions = 0;

function getNextWorker() {
    if (workerPool.length === 0) throw new Error("API não inicializada.");
    const worker = workerPool[currentWorkerIndex];
    currentWorkerIndex = (currentWorkerIndex + 1) % workerPool.length;
    return worker;
}

// Função para registrar erro que aconteceu em background
function logBackendError(round, runNumber, errorDetail) {
    try {
        const logLine = `${round},${runNumber},1,${errorDetail}\n`;
        fs.appendFileSync(LOG_FILE_PATH, logLine);
    } catch (err) {
        console.error("Falha ao salvar log de erro:", err.message);
    }
}

// --- Endpoints Assíncronos (RÁPIDOS) ---

app.post('/open-async', (req, res) => {
    const { accountId, amount } = req.body;
    const runNumber = req.headers['x-run-number'] || '1'; 

    if (!accountId || amount === undefined) {
        return res.status(400).json({ error: "Dados incompletos" });
    }

    if (pendingTransactions >= MAX_PENDING_TX) {
        return res.status(429).json({ error: "Server busy" });
    }

    pendingTransactions++;

    // 1. Responde IMEDIATAMENTE ao JMeter (202 Accepted)
    res.status(202).json({ status: "Accepted", message: "Processing" });

    // 2. Processa em Background
    (async () => {
        try {
            const worker = getNextWorker();
            // * RESTAURADO: Captura a resposta para pegar a latência
            const response = await worker.workloads.open.submitTransaction(accountId, amount);
            
            // * RESTAURADO: Log de sucesso com latência
            console.log(`[OPEN] Sucesso: Conta ${accountId} | Latência Fabric: ${response.latency_ms}ms`);
            
        } catch (e) {
            console.error(`[OPEN] Erro Background: ${e.message}`);
            logBackendError("Open", runNumber, "GENERIC_ERROR");
        } finally {
            pendingTransactions--;
        }
    })();
});

app.post('/transfer-async', (req, res) => {
    const { from, to, amount } = req.body;
    const runNumber = req.headers['x-run-number'] || '1';

    if (!from || !to || amount === undefined) {
        return res.status(400).json({ error: "Dados incompletos" });
    }

    // 1. Responde IMEDIATAMENTE ao JMeter
    res.status(202).json({ status: "Accepted", message: "Processing" });

    // 2. Processa em Background
    (async () => {
        try {
            const worker = getNextWorker();
            // * RESTAURADO: Captura a resposta
            const response = await worker.workloads.transfer.submitTransaction(from, to, amount);
            
            // * RESTAURADO: Log de sucesso com latência
            console.log(`[TRANSFER] Sucesso: ${from}->${to} | Latência Fabric: ${response.latency_ms}ms`);
            
        } catch (e) {
            const msg = e.message || "";
            // Logamos o erro no terminal também para você ver acontecendo
            console.error(`[TRANSFER] Erro: ${msg}`);
            
            let type = "GENERIC_ERROR";
            if (msg.includes("MVCC_READ_CONFLICT")) type = "MVCC_CONFLICT";
            
            logBackendError("Transfer", runNumber, type);
        }
    })();
});

// Query continua Síncrona (O JMeter espera a resposta)
app.get('/query/:accountId', async (req, res) => {
    try {
        const worker = getNextWorker();
        
        // Executa a transação
        const response = await worker.workloads.query.submitTransaction(req.params.accountId);
        
        // --- DEPURAÇÃO ADICIONADA ---
        // Mostra no terminal o sucesso e a latência, igual ao Open/Transfer
        console.log(`[QUERY] Sucesso: Conta ${req.params.accountId} | Latência Fabric: ${response.latency_ms}ms`);
        
        res.status(200).json({ 
            balance: response.balance, 
            latency_ms: response.latency_ms 
        });

    } catch (e) {
        // Log de erro apenas no terminal para você ver
        console.error(`[QUERY] Erro: ${e.message}`);
        
        // IMPORTANTE: Retornamos 500. O JMeter conta isso como falha automaticamente.
        // Não usamos 'logBackendError' aqui para evitar duplicidade no gráfico.
        res.status(500).json({ error: e.message });
    }
});

// Limpeza de logs
app.post('/errors/clear', (req, res) => {
    try {
        if (fs.existsSync(LOG_FILE_PATH)) fs.unlinkSync(LOG_FILE_PATH);
        res.status(200).send("Logs limpos.");
    } catch (e) { res.status(500).send(e.message); }
});

async function startServer() {
    try {
        console.log(`Iniciando ${NUM_WORKERS} workers...`);
        const logDir = path.dirname(LOG_FILE_PATH);
        if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });

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
        app.listen(port, () => console.log(`API Async rodando na porta ${port}`));
    } catch (e) {
        console.error("Erro fatal:", e);
        process.exit(1);
    }
}

startServer();
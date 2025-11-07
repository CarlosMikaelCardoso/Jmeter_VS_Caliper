// --- Variáveis de Ambiente Necessárias ---
// export CHANNEL_NAME="mychannel"
// export CHAINCODE_NAME="simple"
// export API_USER="admin" (O usuário na wallet a ser usado)
// export API_WORKERS=5 (Concorrência da fila, igual ao seu)

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
const CHANNEL_NAME = process.env.CHANNEL_NAME || 'mychannel'; // Canal padrão
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple'; // Chaincode padrão (do seu teste)
const API_USER = process.env.API_USER || 'admin'; // Usuário da wallet
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);

// --- Instâncias de Workload ---
// Otimização: Criamos um único conector e o partilhamos com todos os workloads.
const connector = new FabricConnector();
let openWorkload, queryWorkload, transferWorkload;

// --- Fila de Trabalhos (Job Queue) ---
// Copiada da sua API Besu, mas simplificada (sem NonceManager)
let processingErrors = [];

class JobQueue {
    constructor(concurrency) {
        this.queue = [];
        this.workers = [];
        this.concurrency = concurrency;
        console.log(`Fila de trabalhos iniciada com ${concurrency} workers.`);
    }

    addJob(job) {
        this.queue.push(job);
        this.processQueue();
    }
    
    isIdle() {
        return this.queue.length === 0 && this.workers.length === 0;
    }

    processQueue() {
        if (this.queue.length > 0 && this.workers.length < this.concurrency) {
            const job = this.queue.shift();
            const worker = this.runWorker(job);
            this.workers.push(worker);

            worker.finally(() => {
                this.workers = this.workers.filter(w => w !== worker);
                this.processQueue();
            });
        }
    }

    async runWorker(job) {
        try {
            // Lógica do NonceManager removida. Apenas executamos o job.
            await job();
        } catch (error) {
            console.error("Erro ao processar trabalho da fila:", error.message);
            processingErrors.push({
                timestamp: new Date().toISOString(),
                error: error.message,
                reason: error.reason || 'N/A',
                code: error.code || 'N/A'
            });
            // (Opcional) Adicionar lógica de "retry" se desejar
        }
    }
}

const writeQueue = new JobQueue(NUM_WORKERS);

// --- Endpoints de Controle (Idênticos ao seu) ---
app.get('/queue/status', (req, res) => {
    res.status(200).json({
        isIdle: writeQueue.isIdle(),
        queueSize: writeQueue.queue.length,
        activeWorkers: writeQueue.workers.length
    });
});

app.get('/errors/get', (req, res) => {
    res.status(200).json({ errors: processingErrors });
});

app.post('/errors/clear', (req, res) => {
    console.log("Limpando log de erros de processamento.");
    processingErrors = [];
    res.status(200).json({ message: "Log de erros limpo." });
});

// --- Endpoints de Transação (Idênticos ao seu) ---
app.post('/open-async', (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) return res.status(400).json({ error: "Campos 'accountId' e 'amount' são obrigatórios." });

    writeQueue.addJob(async () => {
        try {
            const txResponse = await openWorkload.submitTransaction(accountId, amount);
            console.log(`(Fila) Transação 'open' para ${accountId} submetida.`);
        } catch (e) {
            console.error(`(Fila) Falha no 'open' para ${accountId}: ${e.message}`);
            // O erro já é capturado pelo runWorker
            throw e; // Lança o erro para o runWorker capturar
        }
    });

    res.status(202).json({ message: `Transação 'open' para ${accountId} enfileirada com sucesso.` });
});

app.post('/transfer-async', (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) return res.status(400).json({ error: "Os campos 'from', 'to' e 'amount' são obrigatórios." });

    writeQueue.addJob(async () => {
        try {
            const txResponse = await transferWorkload.submitTransaction(from, to, amount);
            console.log(`(Fila) Transação 'transfer' de ${from} para ${to} submetida.`);
        } catch (e) {
            console.error(`(Fila) Falha no 'transfer': ${e.message}`);
            throw e;
        }
    });

    res.status(202).json({ message: "Transação 'transfer' enfileirada com sucesso." });
});

app.get('/query/:accountId', async (req, res) => {
    const { accountId } = req.params;
    if (!accountId) return res.status(400).json({ error: "O campo 'accountId' é obrigatório." });

    try {
        // 'query' é uma chamada síncrona (evaluateTransaction), não precisa da fila.
        const balance = await queryWorkload.submitTransaction(accountId);
        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query' para a conta ${accountId}:`, error);
        res.status(500).json({ error: "Falha ao executar a função 'query'.", details: error.message });
    }
});

// --- Iniciar o Servidor ---
async function startServer() {
    // Inicializa o conector do Fabric ANTES de aceitar requisições
    await connector.initialize(API_USER, CHANNEL_NAME, CHAINCODE_NAME);

    // Agora que o conector está pronto, injeta-o nos workloads
    openWorkload = new OpenWorkload(connector);
    queryWorkload = new QueryWorkload(connector);
    transferWorkload = new TransferWorkload(connector);

    app.listen(port, () => {
        console.log(`Servidor da API (Fabric) a correr em http://localhost:${port}`);
        console.log(`API a usar ${NUM_WORKERS} workers.`);
        console.log(`Conectado ao canal '${CHANNEL_NAME}' e chaincode '${CHAINCODE_NAME}' como usuário '${API_USER}'.`);
    });
}

startServer();

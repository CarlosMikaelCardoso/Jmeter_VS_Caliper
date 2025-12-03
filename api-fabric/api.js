const express = require('express');
const FabricConnector = require('./workloads/fabric-connector.js');
const OpenWorkload = require('./workloads/open.js');
const QueryWorkload = require('./workloads/query.js');
const TransferWorkload = require('./workloads/transfer.js');

const app = express();
const port = 3000;
app.use(express.json());

const CHANNEL_NAME = process.env.CHANNEL_NAME || 'gercom';
const CHAINCODE_NAME = process.env.CHAINCODE_NAME || 'simple';
const API_USER = process.env.API_USER || 'admin';
const NUM_WORKERS = parseInt(process.env.API_WORKERS || '5', 10);

const workerPool = [];
let currentWorkerIndex = 0;

function getNextWorker() {
    if (workerPool.length === 0) throw new Error("API não inicializada.");
    const worker = workerPool[currentWorkerIndex];
    currentWorkerIndex = (currentWorkerIndex + 1) % workerPool.length;
    return worker;
}

app.post('/open-async', async (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) return res.status(400).json({ error: "Dados incompletos" });

    try {
        const worker = getNextWorker();
        // Chamada síncrona
        const response = await worker.workloads.open.submitTransaction(accountId, amount);
        
        res.status(200).json({ 
            status: "OK", 
            latency_ms: response.latency_ms 
        });
    } catch (e) {
        console.error(`Erro em /open-async: ${e.message}`);
        res.status(500).json({ error: e.message });
    }
});

app.post('/transfer-async', async (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) return res.status(400).json({ error: "Dados incompletos" });

    try {
        const worker = getNextWorker();
        const response = await worker.workloads.transfer.submitTransaction(from, to, amount);
        
        res.status(200).json({ 
            status: "OK", 
            latency_ms: response.latency_ms 
        });
    } catch (e) {
        console.error(`Erro em /transfer-async: ${e.message}`);
        res.status(500).json({ error: e.message });
    }
});

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

async function startServer() {
    try {
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
        console.log(`API Fabric Síncrona rodando em ${port} com ${NUM_WORKERS} workers.`);
        app.listen(port);
    } catch (e) {
        console.error("Erro fatal:", e);
        process.exit(1);
    }
}

startServer();
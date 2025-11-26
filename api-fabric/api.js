// --- Variáveis de Ambiente Necessárias ---
// export CHANNEL_NAME="mychannel"
// export CHAINCODE_NAME="simple"
// export API_USER="admin" 
// export API_WORKERS=5  (Número de conexões físicas/Gateways)
// export API_CONCURRENCY_PER_WORKER=10 (Transações simultâneas por conexão)

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
const CONCURRENCY_PER_WORKER = parseInt(process.env.API_CONCURRENCY_PER_WORKER || '10', 10);
const TOTAL_QUEUE_CONCURRENCY = NUM_WORKERS * CONCURRENCY_PER_WORKER;

// --- Pool de Workers (Semelhante ao Caliper) ---
// Armazena os objetos contendo o conector e os workloads dedicados
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

// --- Fila de Trabalhos (Job Queue) ---
let processingErrors = [];

class JobQueue {
    constructor(concurrency) {
        this.queue = [];
        this.workers = [];
        this.concurrency = concurrency;
        console.log(`Fila de trabalhos configurada com capacidade de ${concurrency} execuções simultâneas.`);
    }

    addJob(job) {
        this.queue.push(job);
        this.processQueue();
    }
    
    isIdle() {
        return this.queue.length === 0 && this.workers.length === 0;
    }

    processQueue() {
        // Enquanto houver jobs e tivermos "espaço" na concorrência, despacha
        if (this.queue.length > 0 && this.workers.length < this.concurrency) {
            const job = this.queue.shift();
            const workerPromise = this.runWorker(job);
            this.workers.push(workerPromise);

            // Quando terminar, remove da lista de ativos e tenta processar o próximo
            workerPromise.finally(() => {
                this.workers = this.workers.filter(w => w !== workerPromise);
                this.processQueue();
            });
        }
    }

    async runWorker(job) {
        try {
            await job();
        } catch (error) {
            console.error("Erro ao processar trabalho da fila:", error.message);
            processingErrors.push({
                timestamp: new Date().toISOString(),
                error: error.message,
                reason: error.reason || 'N/A',
            });
        }
    }
}

// A fila agora aceita (Workers * Concorrência_por_Worker) tarefas ao mesmo tempo
const writeQueue = new JobQueue(TOTAL_QUEUE_CONCURRENCY);

// --- Endpoints de Controle ---
app.get('/queue/status', (req, res) => {
    res.status(200).json({
        isIdle: writeQueue.isIdle(),
        queueSize: writeQueue.queue.length,
        activeWorkers: writeQueue.workers.length,
        totalCapacity: TOTAL_QUEUE_CONCURRENCY
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

// --- Endpoints de Transação ---

app.post('/open-async', (req, res) => {
    const { accountId, amount } = req.body;
    if (!accountId || amount === undefined) return res.status(400).json({ error: "Campos obrigatórios ausentes." });

    // Adiciona à fila. O Node.js vai processar isso assim que houver vaga na fila.
    writeQueue.addJob(async () => {
        // Dentro do job, escolhemos qual conexão física usar
        const worker = getNextWorker();
        try {
            // O método submitTransaction é async e retorna quando o Fabric confirma (ou falha)
            await worker.workloads.open.submitTransaction(accountId, amount);
            // console.log(`(Fila -> Worker ${worker.id}) Transação 'open' para ${accountId} concluída.`);
        } catch (e) {
            throw new Error(`Falha no 'open' (Worker ${worker.id}): ${e.message}`);
        }
    });

    res.status(202).json({ message: `Transação 'open' enfileirada.` });
});

app.post('/transfer-async', (req, res) => {
    const { from, to, amount } = req.body;
    if (!from || !to || amount === undefined) return res.status(400).json({ error: "Campos obrigatórios ausentes." });

    writeQueue.addJob(async () => {
        const worker = getNextWorker();
        try {
            await worker.workloads.transfer.submitTransaction(from, to, amount);
            // console.log(`(Fila -> Worker ${worker.id}) Transação 'transfer' concluída.`);
        } catch (e) {
            throw new Error(`Falha no 'transfer' (Worker ${worker.id}): ${e.message}`);
        }
    });

    res.status(202).json({ message: "Transação 'transfer' enfileirada." });
});

app.get('/query/:accountId', async (req, res) => {
    const { accountId } = req.params;
    
    try {
        // Queries (Leitura) não passam pela fila de escrita para não serem bloqueadas.
        // Elas usam o pool diretamente para balancear a carga entre as conexões.
        const worker = getNextWorker();
        const balance = await worker.workloads.query.submitTransaction(accountId);
        res.status(200).json({ accountId: accountId, balance: balance.toString() });
    } catch (error) {
        console.error(`Falha ao executar 'query':`, error);
        res.status(500).json({ error: "Falha na query", details: error.message });
    }
});

// --- Inicialização do Servidor e Workers ---
async function startServer() {
    console.log(`--- Inicializando API Fabric ---`);
    console.log(`Workers Físicos (Gateways): ${NUM_WORKERS}`);
    console.log(`Concorrência por Worker: ${CONCURRENCY_PER_WORKER}`);
    console.log(`Capacidade Total da Fila: ${TOTAL_QUEUE_CONCURRENCY}`);

    try {
        // Cria N conexões independentes, isolando os contextos como no Caliper
        for (let i = 0; i < NUM_WORKERS; i++) {
            console.log(`Iniciando Worker #${i + 1}...`);
            
            const connector = new FabricConnector();
            // Cada connector cria seu próprio Gateway e conexão gRPC
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
        });

    } catch (error) {
        console.error("Erro fatal na inicialização dos workers:", error);
        process.exit(1);
    }
}

startServer();
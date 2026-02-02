/* middleware/api.js */
'use strict';

const express = require('express');
const bodyParser = require('body-parser');
const { connectToNetwork } = require('./workloads/fabric-connector');
const logger = require('./logger');

// Importa os workloads
const workloads = {
    open: require('./workloads/open'),
    query: require('./workloads/query'),
    transfer: require('./workloads/transfer')
};

const app = express();
app.use(bodyParser.json());
const PORT = 3000;

let contract = null;

// Inicialização
(async () => {
    contract = await connectToNetwork();
})();

// Endpoint Genérico de Invoke (Open e Transfer)
app.post('/api/invoke', async (req, res) => {
    try {
        // Reconexão
        if (!contract) {
            contract = await connectToNetwork();
            if (!contract) return res.status(503).json({ error: 'Fabric Indisponível' });
        }

        const { functionName, args } = req.body;

        // Verifica se o workload existe
        if (!workloads[functionName]) {
            return res.status(400).json({ error: `Função '${functionName}' não mapeada nos workloads.` });
        }

        // Executa o workload específico (com retry embutido)
        const response = await workloads[functionName].run(contract, args);

        res.json({
            success: true,
            result: response.result.toString(),
            latency_ms: response.latency
        });

    } catch (error) {
        // Se chegou aqui, acabaram os retries ou foi erro grave
        res.status(500).json({ 
            success: false, 
            error: error.message 
        });
    }
});

// Endpoint de Query
app.get('/api/query', async (req, res) => {
    try {
        if (!contract) contract = await connectToNetwork();

        const { functionName, args } = req.query;
        const argsArray = Array.isArray(args) ? args : (args ? [args] : []);

        if (functionName !== 'query') { // Ajuste se seu chaincode usar outro nome
             return res.status(400).json({ error: 'Apenas função "query" suportada neste endpoint' });
        }

        const response = await workloads.query.run(contract, argsArray);

        res.json({
            success: true,
            result: response.result.toString()
        });

    } catch (error) {
        logger.error(`Erro Query: ${error.message}`);
        res.status(500).json({ error: error.message });
    }
});

app.listen(PORT, () => {
    logger.info(`🚀 API rodando na porta ${PORT}`);
});
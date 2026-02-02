'use strict';
const logger = require('./logger');

const MAX_RETRIES = 5;
const RETRY_DELAY = 100; // ms

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function submitWithRetry(contract, funcName, args) {
    let attempt = 0;
    // Converte args para string (evita erro 301)
    const stringArgs = args.map(String);

    while (attempt < MAX_RETRIES) {
        try {
            if (attempt === 0) {
                logger.info(`[Submit] ${funcName} | Args: ${JSON.stringify(stringArgs)}`);
            } else {
                logger.warn(`[Retry ${attempt}] ${funcName} | Args: ${JSON.stringify(stringArgs)}`);
            }

            const start = Date.now();
            
            // MODO SÍNCRONO: O SDK espera o commit aqui
            const result = await contract.submitTransaction(funcName, ...stringArgs);
            
            const latency = Date.now() - start;
            return { result, latency };

        } catch (error) {
            const msg = error.message || error.toString();
            
            // Se for conflito de leitura/escrita (MVCC), tenta de novo
            if (msg.includes('MVCC_READ_CONFLICT')) {
                attempt++;
                logger.warn(`⚠️  MVCC Conflict em ${funcName}. Tentando novamente em ${RETRY_DELAY}ms...`);
                await sleep(RETRY_DELAY * attempt); // Backoff exponencial simples
            } else {
                logger.error(`❌ Erro Fatal em ${funcName}: ${msg}`);
                throw error; // Outros erros (conexão, lógica) falham direto
            }
        }
    }
    throw new Error(`Falha após ${MAX_RETRIES} tentativas (MVCC Conflict).`);
}

module.exports = { submitWithRetry };
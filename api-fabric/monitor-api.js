'use strict';
const express = require('express');
const Docker = require('dockerode');
const fs = require('fs');
const path = require('path');
const os = require('os');

const app = express();
const port = 3002; // Porta dedicada para o monitor
app.use(express.json());

// --- CORREÇÃO PARA DOCKER DESKTOP ---
console.log("Tentando conectar ao socket padrão do Docker Engine (/var/run/docker.sock)...");

// Instancia o Docker. O 'dockerode' irá procurar automaticamente 
// o socket em /var/run/docker.sock (padrão do Docker Engine) quando 
// nenhum 'socketPath' é fornecido.
const docker = new Docker();

// Adiciona uma verificação de conexão para garantir que o daemon está acessível
// (Isso substitui o 'fs.existsSync(DOCKER_DESKTOP_SOCKET)' antigo)
docker.info((err, info) => {
    if (err) {
        console.error("ERRO: Falha ao conectar ao socket do Docker (/var/run/docker.sock).");
        console.error("Verifique se o daemon do Docker (dockerd) está rodando e se você tem permissão.");
        console.error("Tente executar: sudo systemctl status docker");
        console.error(`Detalhe do erro: ${err.message}`);
        process.exit(1);
    }
    if(info) {
         console.log("Conexão com o Docker Engine estabelecida com sucesso.");
    }
});
// Lista de containers da rede Fabric para monitorar
// ATENÇÃO: Se você adicionar a Org3, adicione 'peer0.org3.example.com' e 'couchdb2' aqui
const DOCKER_CONTAINERS_TO_MONITOR = [
    "orderer.example.com",
    "peer0.org1.example.com",
    "peer0.org2.example.com",
    "couchdb0",
    "couchdb1"
    // Adicione containers de chaincode (dev-peer*) dinamicamente se necessário
];

const LOG_DIR = path.join(os.tmpdir(), 'jmeter_fabric_logs');
if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
}

// Guarda os streams de monitoramento ativos
const monitoringProcesses = {};

/**
 * Função principal de monitoramento, baseada na sua API Besu
 */
function startMonitoring(runId, logStream) {
    console.log(`[${runId}] Iniciando streams de stats para ${DOCKER_CONTAINERS_TO_MONITOR.length} containers...`);
    
    // Escreve o cabeçalho para o script generateGraphs.py
    logStream.write('container,cpu,mem,net_rx,net_tx,disk_r,disk_w\n');

    const streams = DOCKER_CONTAINERS_TO_MONITOR.map(containerName => {
        const container = docker.getContainer(containerName);
        
        container.stats({ stream: true }, (err, stream) => {
            if (err) {
                console.error(`[${runId}] Erro ao iniciar stats para ${containerName}: ${err.message}`);
                return;
            }

            if (!monitoringProcesses[runId]) {
                 console.log(`[${runId}] Monitoramento parado antes do stream iniciar.`);
                 stream.destroy();
                 return;
            }
            
            // Adiciona o stream à lista para poder pará-lo depois
            monitoringProcesses[runId].streams.push(stream);

            stream.on('data', (chunk) => {
                try {
                    const stats = JSON.parse(chunk.toString());
                    if (stats.precpu_stats.system_cpu_usage === 0) {
                        // Docker pode enviar um primeiro tick com dados zerados, ignorar
                        return;
                    }

                    // --- Lógica de Cálculo de CPU (igual à da API Besu) ---
                    const cpuDelta = stats.cpu_stats.cpu_usage.total_usage - stats.precpu_stats.cpu_usage.total_usage;
                    const systemDelta = stats.cpu_stats.system_cpu_usage - stats.precpu_stats.system_cpu_usage;
                    const cpuCount = stats.cpu_stats.online_cpus || (stats.cpu_stats.cpu_usage.percpu_usage ? stats.cpu_stats.cpu_usage.percpu_usage.length : 0);
                    let cpuPercent = 0.0;
                    if (systemDelta > 0.0 && cpuDelta > 0.0 && cpuCount > 0) {
                        cpuPercent = (cpuDelta / systemDelta) * cpuCount * 100.0;
                    }
                    
                    const memUsage = (stats.memory_stats.usage / (1024 * 1024)).toFixed(2); // Em MiB
                    
                    let netRx = 0, netTx = 0, diskRead = 0, diskWrite = 0;
                    if (stats.networks) {
                        Object.values(stats.networks).forEach(net => {
                            netRx += net.rx_bytes;
                            netTx += net.tx_bytes;
                        });
                    }
                    // NOTA: stats do Fabric (blkio_stats) podem ser diferentes.
                    // Usaremos 0 se não for encontrado.
                    
                    // Formato: container,cpu,mem,net_rx,net_tx,disk_r,disk_w
                    
                    // --- CORREÇÃO DA LÓGICA DO NOME ---
                    // Remove .example.com se existir, senão usa o nome como está
                    const shortName = containerName.replace('.example.com', '');
                    // --- FIM DA CORREÇÃO ---
                    
                    const netRxKB = (netRx / 1024).toFixed(2);
                    const netTxKB = (netTx / 1024).toFixed(2);
                    const diskReadKB = (diskRead / 1024).toFixed(2);
                    const diskWriteKB = (diskWrite / 1024).toFixed(2);

                    const logLine = `${shortName},${cpuPercent.toFixed(2)}%,${memUsage}MiB,${netRxKB}KB,${netTxKB}KB,${diskReadKB}KB,${diskWriteKB}KB\n`;
                    logStream.write(logLine);

                } catch (e) {
                    // Ignora erros de parse de JSON (comuns no início do stream)
                }
            });

            stream.on('end', () => {
                console.log(`[${runId}] Stream de stats para ${containerName} terminou.`);
            });
            stream.on('error', (err) => {
                console.error(`[${runId}] Erro no stream de ${containerName}: ${err.message}`);
            });
        });
    });
}

// --- Endpoints ---

app.post('/monitor/start', (req, res) => {
    const { roundName, runNumber } = req.body;
    if (!roundName || runNumber === undefined) {
        return res.status(400).json({ error: "Campos 'roundName' e 'runNumber' são obrigatórios." });
    }
    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);

    if (monitoringProcesses[runId]) {
        return res.status(409).json({ message: `Monitoramento para ${runId} já está em execução.` });
    }

    console.log(`Iniciando monitoramento para: ${runId}. Log em: ${logPath}`);
    const logStream = fs.createWriteStream(logPath, { flags: 'w' });

    monitoringProcesses[runId] = { 
        streams: [], 
        stream: logStream 
    };
    
    startMonitoring(runId, logStream);

    res.status(202).json({ message: `Monitoramento para ${runId} iniciado.` });
});

app.post('/monitor/stop', (req, res) => {
    const { roundName, runNumber } = req.body;
    const runId = `${roundName}_run_${runNumber}`;
    const processInfo = monitoringProcesses[runId];

    if (processInfo) {
        console.log(`Parando monitoramento para: ${runId}`);
        processInfo.streams.forEach(stream => {
            if (stream && typeof stream.destroy === 'function') {
                stream.destroy();
            }
        });
        processInfo.stream.end();
        delete monitoringProcesses[runId];
        res.status(200).json({ message: `Monitoramento para ${runId} parado.` });
    } else {
        res.status(404).json({ message: `Nenhum processo de monitoramento encontrado para ${runId}.` });
    }
});

app.get('/monitor/logs/:roundName/:runNumber', (req, res) => {
    const { roundName, runNumber } = req.params;
    const runId = `${roundName}_run_${runNumber}`;
    const logPath = path.join(LOG_DIR, `docker_stats_${runId}.log`);
    
    if (fs.existsSync(logPath)) {
        res.sendFile(logPath);
    } else {
        res.status(404).send('Arquivo de log não encontrado.');
    }
});

app.listen(port, () => {
    console.log(`API de Monitoramento (Fabric/Docker) rodando em http://localhost:${port}`);
    console.log(`Logs de monitoramento serão salvos em: ${LOG_DIR}`);
});
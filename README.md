# JMeter vs Caliper

Projeto para comparar benchmarks de redes Hyperledger Fabric e Hyperledger
Besu usando JMeter e Hyperledger Caliper. O fluxo comum é selecionado por
`BACKEND` e executado a partir da raiz do projeto.

## Pré-requisitos

- Ubuntu/Debian com acesso a `sudo`;
- usuário com permissão para usar Docker;
- conexão com a internet durante a instalação das ferramentas e imagens Fabric.

## Instalação

```bash
cp .env.example .env
bash scripts/install_dependencies.sh
npm run setup
```

O instalador configura Docker Engine, Docker Compose v2, Node.js 20+, npm, Go,
Python, `jq`, `git`, `wget`, `curl`, `sar` e `netcat`. Esse deve ser o primeiro
comando executado em uma máquina nova. Depois, `npm run setup`
instala os pacotes Node pelos lockfiles e cria `.venv` com as dependências
Python dos relatórios. Ajuste `.env` para mudar número de rodadas, workers,
orderers, portas ou versões.

Para somente verificar uma máquina já configurada:

```bash
bash scripts/install_dependencies.sh --check
```

## Rede Fabric (padrão)

```bash
npm run network:up
npm run network:down
```

Esse comando baixa os binários/amostras da versão configurada, recria o canal
`FABRIC_CHANNEL`, instala o chaincode `FABRIC_CHAINCODE` e atualiza o perfil de
conexão do middleware. Para alterar a quantidade de orderers, edite `ORDERERS`
em `.env`.

## Benchmarks

Os benchmarks iniciam o monitor Docker automaticamente se a porta configurada
estiver livre. O middleware da API JMeter continua sendo iniciado por rodada.

```bash
npm run benchmark:jmeter
npm run benchmark:caliper
```

Os resultados são salvos em `results/jmeter_runs` e `results/caliper_runs`,
organizados por rodada. Para executar somente uma quantidade menor durante uma
validação, use temporariamente `TOTAL_ROUNDS` no `.env`.

## Relatório

```bash
npm run report
```

## Comandos úteis

```bash
(cd middleware && npm start)       # API JMeter, porta API_PORT
(cd middleware && npm run monitor) # monitor Docker, porta MONITOR_PORT
npm run install:all                 # reinstala dependências Node pelos locks
BACKEND=fabric npm run api:start   # inicia a API Fabric
BACKEND=besu npm run api:start     # inicia a API Besu
```

## Seleção do backend

O backend padrão é Fabric. Para usar Besu, configure no `.env`:

```dotenv
BACKEND=besu
BESU_DEPLOYER_PRIVATE_KEY=<segredo-local>
BESU_CONTRACT_ADDRESS=<endereco-do-contrato>
```

O Besu usa a API na porta `3001` e o RPC padrão em `8545`; a API Fabric usa a
porta `3000`. O endpoint `/health` verifica a disponibilidade do backend.

O código da API e os artefatos da topologia Besu estão em `api-besu/`,
`docker-compose.yaml`, `genesis_QBFT.json` e nos scripts de geração. O setup
gera as chaves localmente; as credenciais da conta de deploy e o endereço do
contrato continuam obrigatoriamente fora do Git, em `.env` ou no ambiente.
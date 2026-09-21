# JMeter vs Caliper

Projeto para comparar benchmarks de uma rede Hyperledger Fabric usando JMeter e
Hyperledger Caliper. O fluxo foi centralizado em scripts executados a partir da
raiz do projeto.

## Pré-requisitos

- Ubuntu/Debian com acesso a `sudo`;
- usuário com permissão para usar Docker;
- conexão com a internet durante a instalação das ferramentas e imagens Fabric.

## Instalação

```bash
cp .env.example .env
npm run setup
```

O setup instala as dependências de sistema ausentes, valida o Docker, instala
os pacotes Node pelos lockfiles e cria `.venv` com as dependências Python dos
relatórios. Ajuste `.env` para mudar número de rodadas, workers, orderers,
portas ou versões.

## Rede Fabric

```bash
npm run network:up
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
```

As portas padrão são `3000` para a API e `3002` para o monitor. Os endpoints
`/health` permitem verificar se os serviços estão disponíveis.
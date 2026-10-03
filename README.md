# JMeter vs Caliper: Hyperledger Benchmarking Framework

Um framework unificado para comparar o desempenho de redes **Hyperledger Fabric** e **Hyperledger Besu** (com consenso QBFT) utilizando duas poderosas ferramentas de teste de carga: **Apache JMeter** e **Hyperledger Caliper**.

Este repositório consolida a configuração de infraestrutura, os middlewares de API, e a geração automática de gráficos e relatórios. O fluxo de execução muda dinamicamente de acordo com a variável `BACKEND` selecionada no arquivo `.env`.

---

## 🏗️ Estrutura do Projeto

- `benchmarks/`: Configurações e planos de teste organizados por ferramenta e backend (`caliper_fabric`, `caliper_besu`, `jmeter_fabric`, `jmeter_besu`).
- `scripts/`: Scripts unificados em bash para automação de setup, orquestração de testes e geração de gráficos (`run_32_rounds_*.sh`).
- `api-besu/`: Middleware em Node.js (Ethers.js/Express) que expõe endpoints assíncronos (`/open-async`, `/transfer-async`, `/query/:id`) para conectar o JMeter à rede Besu.
- `middleware/`: Middleware em Node.js (Fabric Gateway) que expõe endpoints síncronos para a rede Fabric.
- `results/`: Diretório gerado automaticamente que armazenará logs (`.jtl`, `.txt`) e os relatórios gráficos consolidados (PDF/PNG) após os testes.
- `network/`: Repositório de configuração da test-network do Fabric.

---

## 🛠️ Pré-requisitos

- Ubuntu 20.04, 22.04 ou 24.04 LTS (Noble) com acesso a `sudo`. Ubuntu 26.04 ainda não homologado.
- Usuário com permissão para gerenciar grupos do Docker.
- Conexão com a internet para download das imagens, binários e bibliotecas.

---

## ⚙️ 1. Instalação e Configuração Base

O comando de setup cuidará da instalação do Docker Engine 28.x, Node.js 20+, npm, Python 3 + ambiente virtual (`.venv`), Java (para o JMeter), `jq`, `sar`, entre outros. 

```bash
# 1. Clone o repositório e crie o seu arquivo de ambiente
cp .env.example .env

# 2. Instale todas as dependências do S.O.
bash scripts/install_dependencies.sh

# 3. Baixe e instale as dependências Node/Python internas
npm run setup
```

**Problemas com permissão no Docker?** Se receber `permission denied`, adicione seu usuário ao grupo do docker e reinicie a sessão:
```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

---

## 🎯 2. Escolhendo o Backend (Fabric vs Besu)

O comportamento do framework inteiro é ditado pelo seu arquivo `.env`. Abra-o e edite a variável `BACKEND`:

```dotenv
# Escolha "fabric" ou "besu"
BACKEND=besu
TOTAL_ROUNDS=32
JMETER_WORKERS=5
CALIPER_WORKERS=5
```

### Para Hyperledger Fabric (`BACKEND=fabric`)
O setup do Fabric já cuida de tudo automaticamente (criação do canal `mychannel` e deploy do chaincode).
- **API (JMeter):** Ocorre na porta `3000`.

### Para Hyperledger Besu (`BACKEND=besu`)
O setup do Besu gera um ambiente de laboratório completo com 6 nós validadores rodando consenso QBFT (`genesis_QBFT.json`).
- **API (JMeter):** Ocorre na porta `3001` (com endpoints geradores de hash e fila de concorrência).
- **Deploy Manual do Contrato:** Como o Besu exige transações assinadas, você precisa rodar o script de deploy fornecido para publicar o contrato na blockchain recém-criada antes dos benchmarks:
  ```bash
  npm run network:up       # Sobe a rede Besu (6 nós)
  node deploy.js           # Faz o deploy e retorna o ADDRESS gerado
  ```
  *(Depois, copie o ADDRESS retornado e cole na variável `BESU_CONTRACT_ADDRESS` dentro do seu `.env` e também no campo "address" dentro do `benchmarks/caliper_besu/networkconfig.json`)*.

---

## 🚀 3. Levantando a Rede Blockchain

O comando unificado analisa seu `.env` e inicia a infraestrutura correspondente:

```bash
npm run network:up
```
*(Para desligar e limpar tudo, use `npm run network:down`)*.

---

## 📊 4. Executando os Benchmarks

Os scripts automatizam 100% da execução: iniciam as APIs, geram dados de entrada estocásticos (contas aleatórias e valores de transferências), acionam a ferramenta de stress, aguardam o esvaziamento das filas assíncronas (no Besu) e monitoram o uso de CPU e Memória (via `docker stats`).

São **três baterias internas** por rodada: `Open` (escrita), `Query` (leitura) e `Transfer` (escrita concorrente).

### Apache JMeter
```bash
npm run benchmark:jmeter
```
> O JMeter dispara requisições HTTP para as nossas APIs (`middleware/` ou `api-besu/`). Os gráficos são gerados a cada rodada dentro da respectiva pasta em `results/jmeter_runs/round_X/graphs/`.

### Hyperledger Caliper
```bash
npm run benchmark:caliper
```
> O Caliper interage diretamente com o SDK nativo da blockchain (via Gateway ou Ethereum Connector) ignorando as nossas APIs Rest. Ele gera relatórios HTML e gráficos comparativos em `results/caliper_runs/round_X/graphs/`.

*Dica: Você pode reduzir `TOTAL_ROUNDS` para 1 ou 2 no seu `.env` para realizar testes de homologação rápidos antes de uma bateria completa.*

---

## 📈 5. Relatórios Finais e Gráficos

Se a geração de gráficos acadêmicos não falhou por falta do LaTeX (`usetex=False` já configurado nativamente nos scripts Python via `matplotlib`), os gráficos detalhados estarão nas pastas das respectivas rodadas.

Para consolidar todos os dados e gerar um comparativo unificado ao fim dos testes:

```bash
npm run report
```
Isso varrerá todas as pastas e criará um relatório holístico compilando a eficiência de cada backend nas transações ao longo das 32 rodadas!

---

## 🧰 Comandos Úteis

```bash
# Iniciar as APIs manualmente para testes com Postman/Insomnia
BACKEND=fabric npm run api:start
BACKEND=besu npm run api:start

# Iniciar apenas o monitor Docker do Fabric (porta 3005)
(cd middleware && npm run monitor)

# Reinstalar todas as dependências garantindo lockfiles (clean install)
npm run install:all
```
# Análise Técnica: Discrepância de Latência entre JMeter e Caliper (Hyperledger Fabric)

## 1. O Fenômeno Observado
Durante os testes de carga na rede Hyperledger Fabric, observou-se uma discrepância significativa nos tempos de latência para operações de escrita (Open/Transfer) entre as duas ferramentas utilizadas:

| Ferramenta | Latência Média (Escrita) | Latência Média (Leitura) | Modelo de Medição |
| :--- | :--- | :--- | :--- |
| **Apache JMeter** | **~15 ms** | ~31 ms | Via API REST (Http) |
| **Hyperledger Caliper** | **~305 ms** | ~19 ms | Via SDK Nativo (gRPC) |

A diferença de **~20x** nas escritas levanta a questão: *Por que o JMeter é tão mais rápido que a ferramenta nativa de benchmark?*

## 2. A Causa Raiz: Definição de "Sucesso"

A análise do código fonte e do comportamento das ferramentas revelou que elas medem etapas diferentes do ciclo de vida da transação.

### JMeter: Latência de Ingestão (Ingestion Latency)
O JMeter interage com uma API Middleware (Node.js/Go). O código da API utiliza o padrão **Fire-and-Forget** (ou confirmação mínima).

**Fluxo:**
1. JMeter envia HTTP POST.
2. API envia Proposta ao Peer (Endorsement).
3. API envia Transação ao Orderer.
4. **Orderer retorna ACK (Recebido).**
5. **API retorna `200 OK` ao JMeter imediatamente.**

* **O que foi medido:** O tempo para a rede *aceitar* o pedido.
* **Risco:** Se a transação falhar na validação MVCC ou no consenso *após* o ACK do Orderer, o JMeter já contabilizou como "Sucesso", gerando um falso positivo de finalização.

### Caliper: Latência de Finalização (Settlement Latency)
O Caliper utiliza o SDK do Fabric com um adaptador de teste (`sutAdapter`) configurado para garantir a consistência forte.

**Fluxo:**
1. Caliper envia Proposta e Transação (igual à API).
2. **Caliper NÃO para o cronômetro no ACK do Orderer.**
3. Caliper mantém um *Listener* (via WebSocket/gRPC) escutando eventos de bloco.
4. Orderer gera o bloco (BatchTimeout/MaxMessageCount).
5. Peer valida e grava no CouchDB/LevelDB.
6. Peer emite evento "Tx Validada".
7. **Caliper recebe o evento e para o cronômetro.**

* **O que foi medido:** O tempo real para o dado se tornar imutável no Ledger (End-to-End).

## 3. Evidência no Código

A diferença fica clara comparando a implementação da submissão:

**Código da API (JMeter):**
```javascript
// Apenas submete e aguarda a resposta do envio (ACK), não o evento de commit.
const start = Date.now();
const result = await this.contract.submitTransaction(funcName, ...args);
// O 'result' aqui retorna assim que o Orderer aceita, dependendo da config do Gateway.
const latency = Date.now() - start; 
return { result, latency_ms: latency }; // ~15ms
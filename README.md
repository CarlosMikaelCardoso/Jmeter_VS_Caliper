# 1 - Criando a Rede e Instalando Dependências
## 1.1 - Criando a Rede
    cd Jmeter_VS_Caliper
    chmod +x setup_fabric_network.sh
    cd scripts/setup_fabric_network.sh
> **Isso instalará o Docker e outras dependências necessárias e logo após isso, iniciará a rede Fabric com cinco Orderers, dois Peers, dois CouchDBs, um Canal com o nome "gercom" e um Chaincode "Simple".**

> **Você pode definir a quantidade de orderers a serem criados usando o script `setup_fabric_network.sh <num_orderers>`**

# 2 - Rodando o JMeter e Caliper 
## 2.1 - Rodando o monitor Docker 
    cd Jmeter_VS_Caliper/middleware
    npm install
    node monitor.js

> **`monitor.js` inicia uma api para monitorar o consumo de CPU e Memoria RAM de cada Container da rede Fabric, caso tenha mais de 5 orderers e necessário modificar a lista dentro desse script informando o nome de/dos orderes adicionais**

## 2.2 - Rodando o JMeter
    cd Jmeter_VS_Caliper/scripts
    chmod +x run_32_rounds_jmeter.sh
    ./run_32_rounds_jmeter.sh

> **O script `run_32_rounds_jmeter.sh` irá executar 32 rodadas de testes com o JMeter, durante a bateria de testes, os resultados de cada rodada podem ser visualizados na pasta de ../results/jmeter_runs.**

## 2.3 - Rodando o Caliper
    cd Jmeter_VS_Caliper/scripts
    chmod +x run_32_rounds_caliper.sh
    ./run_32_rounds_caliper.sh

> **O script `run_32_rounds_caliper.sh` irá executar 32 rodadas de testes com o Caliper, durante a bateria de testes, os resultados de cada rodada podem ser visualizados na pasta de ../results/caliper_runs.**

> **Atenção: as APIs do Jmeter e Docker ultilizam as portas 3000 e 3002 respectivamente, garanta que estejam disponiveis antes dos testes!**

# 3 - Criando os gráficos consolidados
    cd Jmeter_VS_Caliper/scripts
    chmod +x generateFinalReport.sh
    ./generateFinalReport.sh
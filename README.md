# Hyperledger Besu - Rede QBFT Permissional

Bem-vindo ao projeto **Besu Production Docker**! Este repositório foi desenvolvido para facilitar a criação e o gerenciamento de uma rede blockchain permissionada com **Hyperledger Besu**, utilizando o mecanismo de consenso **QBFT**, ideal para ambientes de produção.

## Funcionalidades

- **Setup Automatizado:** Scripts que automatizam a geração de chaves, arquivos de configuração e a estrutura de diretórios da rede.
- **Orquestração com Docker:** Uso de Docker e Docker-Compose para subir e gerenciar os nós da rede de forma isolada e consistente.
- **Rede Permissionada:** Configuração de uma rede privada onde apenas nós e contas autorizadas podem participar.
- **Automação de Contratos:** Inclui scripts para compilar, implantar e testar smart contracts na rede.

## Requisitos

Os requisitos são instalados automaticamente pelo script `setup_besu_networks.sh`, mas é importante garantir que você tenha os seguintes pré-requisitos (cURL, wget, tar):

- **Java JDK 17+**
- **Besu v24.7.0+**
- **Docker & Docker-Compose**
- **cURL, wget, tar**

## Instalação e Configuração

Siga os passos abaixo para configurar o projeto em sua máquina:

1. Clone este repositório:
   ```bash
   git clone https://github.com/CarlosMikaelCardoso/Jmeter_VS_Caliper.git
   git clone https://github.com/hyperledger-caliper/caliper-benchmarks.git
   cd caliper-benchmarks
   git checkout v0.6.0
   ```
2. Execute o script de configuração da rede. Ele irá preparar todos os arquivos necessários para os nós.
   ```bash
   chmod +x setup_besu_networks.sh
   ./setup_besu_networks.sh
   ```

## Testes com o Caliper e Jmeter

### Se quiser comparar o desempenho dos dois, recomendo executar primeriro o Caliper, pois ele gera o contrato que o Jmeter pode usar nos seus testes.
Na pasta testes edite o "url" no networkconfig.json e coloque o IP da maquina.
# Caliper
```bash
cd testes
./run_caliper.sh <número de usuários> <número de repetições>
```
Por padrão o Caliper executa apenas uma vez o teste com 5 Workers

# Jmeter
No Jmeter precisamos executar a API para que ele consiga realizar as operações

``` bash
cd api-besu
npm install # Instala as dependências para a API
# Exporte as variáveis de ambiente necessárias para a configuração do Besu.
export DEPLOYER_PRIVATE_KEY="0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
export CONTRACT_ADDRESS="<endereço do contrato>" # Esse endereço esta no /testes/contract_address.txt 
node api_load_balancer
```
Em outro terminal

``` bash
./Jmeter_VS_Caliper/testes
./run_jmeter.sh <número de usuários> <número de repetições>
```
Por padrão o Caliper executa apenas uma vez o teste com 5 Threads

Ao final de execução de cada .sh é gerado uma pasta que contem arquivos de log e resultados dos testes
Você pode modificar os arquivos de configuração do Caliper - 5_Users/caliper/simple/config.yaml - onde pode definir a quantidade de Workers e a Qantidade de de transações a serem realizadas. Assim como no jmeter - 5_users/jmeter/*.jmx - que é separado em 3 .jmx para cada operação (Open, Query e Transfer).

## Contribuição

Contribuições são bem-vindas! Siga os passos abaixo para contribuir:

1. Faça um fork do repositório.
2. Crie uma branch para sua feature/bugfix:
   ```bash
   git checkout -b minha-feature
   ```
3. Faça commit das suas alterações:
   ```bash
   git commit -m "feat: Minha nova feature"
   ```
4. Envie para o repositório:
   ```bash
   git push origin minha-feature
   ```
5. Abra um Pull Request.

## Contato

Se tiver dúvidas ou sugestões, entre em contato:

- **Desenvolvedor:** Carlos Mikael Cardoso Da Costa
- **Email:** mikael.cardoso.costa13@gmail.com

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).

---

Obrigado por usar este projeto!

# 1 - Instalando Dependências da API do Hyperledger Fabric

```bash
    npm install
```
# 2 - Configurando a Rede do Hyperledger Fabric
```bash
    cd config
    cp ../../testes_fabric/network_fabric/test-network/organizations/peerOrganizations/org1.example.com/connection-org1.json connection-profile.json
```

# 3 - Enrolando o Admin da Organização
```bash
    npm run enrollAdmin
``` 

# 4 - Definindo Variáveis de Ambiente
```bash
    # O canal do seu chaincode (ex: gercom)
    export CHANNEL_NAME="gercom"

    # O nome do chaincode (ex: simple)
    export CHAINCODE_NAME="simple"

    # O usuário na wallet que a API usará
    export API_USER="admin"
```

# 5 - Iniciando a API
```bash
    npm start
```
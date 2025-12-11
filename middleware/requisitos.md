# 1 - Instalando Dependências da API do Hyperledger Fabric

```bash
    npm install
```

# 2 - Enrolando o Admin da Organização
```bash
    npm run enrollAdmin
``` 

# 3 - Definindo Variáveis de Ambiente
```bash
    # O canal do seu chaincode (ex: gercom)
    export CHANNEL_NAME="gercom"

    # O nome do chaincode (ex: simple)
    export CHAINCODE_NAME="simple"

    # O usuário na wallet que a API usará
    export API_USER="admin"

    # Numero de Workers da API
    export API_WORKERS=15
```

# 4 - Iniciando a API
```bash
    npm start
```


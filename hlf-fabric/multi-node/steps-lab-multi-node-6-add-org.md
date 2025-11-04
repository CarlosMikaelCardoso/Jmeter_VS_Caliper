# Adicão de uma nova Organização em um rede ativa (Com DNS)
### Documento base: https://github.com/kfsoftware/meetup-k8s-hlf-2024
# Arquitetura de uma rede com 6 nodes
![Minha foto de perfil](Arquitetura_multi_node.jpg)

## 1 - Clonar o Repositório do Projeto em todas as VMs
    git clone --branch fabric https://github.com/CarlosMikaelCardoso/Jmeter_VS_Caliper.git

## 2 - Configurar o DNS Server
### Ir ao diretorio de trabalho do cenário escolhido
    
    cd /Jmeter_VS_Caliper/hlf-fabric/multi-node || exit

## 3 - Adicionando uma nova organização na rede
    ./setup-nodeX.sh X config.yaml # X é o número do node que será criado

### Após o termino da execução desse .sh vai ser criado uma pasta em ./org_certificates/nodeX copie essa pasta para a VM onde foi instaciada os Orderes (./setup-node1.sh).

## 4 - Atualizando o canal com a nova organização
### Execute na VM onde estiver o node1 (Orderes)
    ./add-org-channelX.sh X  # X é o número do node que foi criado

## 5 - Join Channel na nova organização
### Agora transfira a pasta do node1 que está na VM dos orderers e copie para a VM que está o novo nodeX
### Para a pasta './org_certificates'
### Execute na VM onde estiver o nodeX
    ./join-channel-nodeX.sh X config.yaml # X é o número do node que foi criado

## 6 - Instalar a chaincode na nova organização
### Pegue o chaincode-configs.txt.yaml que está na VM onde foi instalado o node2 (Chaincode) e copie para a VM que está o novo nodeX
### Vá na VM que está o novo nodeX e Execute:
    ./networkconfig.sh X config.yaml  # X é o número do node que foi criado
### Instação da chaincode na nova organização
### Copie o arquivo 'asset.tar.tgz' que está na VM onde foi instalado o node2 (Chaincode) para a VM onde está o novo nodeX
    gunzip < asset.tar.gz | sudo microk8s ctr image import -
    sudo microk8s ctr images list | grep asset
    ./install-chaincode-new-org.sh nodeX config.yaml  # node'X' é o número do node que foi criado
### Pegue o nodeX.yaml e a pasta nodeX que contém os certs gerados e copie para a VM onde foi instalado o node2 (Chaincode)
### Execute na VM onde estiver o node2 (Chaincode)
    ./add-org-chaincode.sh nodeX config.yaml  # node'X' é o número do node que foi criado

## 7 - Instalação de mais orgs
### Após a instalação da nova organização, será criado um novo chaincode-configs.txt que terá as informações atualizadas da Chaincode.

## 8 - Consultar o chaincode na nova organização
### Execute na VM onde estiver o nodeX
    kubectl hlf chaincode query --config=nodeX.yaml \
    --user=nodeX-admin-nodeX-net --peer=nodeX-peer0.nodeX-net \
    --chaincode=asset --channel=demo \
    --fcn=GetAllAssets
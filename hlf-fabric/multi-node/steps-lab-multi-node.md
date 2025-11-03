# Cluster único (Com Proxy, Sem Vault)
Documento base: https://github.com/kfsoftware/meetup-k8s-hlf-2024

## 1 - Clonar o Repositório do Projeto
    git clone --branch iliada_v2 https://USUARIO_GIT_LAB:TOKEN_ACESSO@git.rnp.br/iliada-blockchain/m3/cenarios-bevel

## 2 - Configurar VMs e DNS no Host
Ir ao diretorio de trabalho do cenário escolhido
    
    cd cenarios-bevel/lab-multi-node/fabric-hlf || exit

Subindo 2 VM onde VM1: 5 CPU's, 4GB de RAM e 18 GB de disco e VM2: 2 CPU's, 3GB de RAM e 18 GB de disco
    
    ../../scripts/setup-VMs-multipass.sh 2 3 3 10
    
Edit o arquivo config.yaml, que será criado apos a executação do comando e coloque o nome associado a cada IP

    ../../scripts/setup-dns.sh config.yaml 

## 3 - Configurar o DNS e Microk8s na VM1
    multipass shell vm1
    sudo apt update && sudo apt -y upgrade
    cd /iliada/lab-multi-node/fabric-hlf || exit  
    ../../scripts/setup-microk8s.sh
    ../../scripts/config-dns-client.sh config.yaml

## 3.1 - Configurar o DNS e Microk8s na VM2
    multipass shell vm2
    sudo apt update && sudo apt -y upgrade
    cd /iliada/lab-multi-node/fabric-hlf || exit  
    ../../scripts/setup-microk8s.sh
    ../../scripts/config-dns-client.sh config.yaml

## 4 - Instalar o HLF Operator VM1 e VM2
## 4.1 - Instalar o HLF operator e depois sair da VM1

    ../../scripts/setup-hlf-operator.sh config.yaml
    exit
    # Criar snapshot caso esteja testando os scripts
    multipass stop vm1 && multipass snapshot -n hlf vm1 && multipass shell vm1

## 4.2 - Instalar o HLF operator e depois sair da VM2

    ../../scripts/setup-hlf-operator.sh config.yaml
    exit
    # Criar snapshot caso esteja testando os scripts
    multipass stop vm2 && multipass snapshot -n hlf vm2 && multipass shell vm2

Precisa sair e entrar novamente para carregar as variaveis de ambiente do plugin do hlf com o kubernetes

## 5 - Instalar as organizações com suas CAs, Orderes e Peers

    multipass shell vm1
    cd /iliada/lab-multi-node/fabric-hlf || exit  
    ./setup-orgs-vm1.sh 

    multipass shell vm2
    cd /iliada/lab-multi-node/fabric-hlf || exit  
    ./setup-orgs-vm2.sh

## 6 - Criar Canal
    Na VM2  
    ./create-channel-vm2.sh 

    Na VM1
    ./create-channel-vm1.sh

## 7 - Join Channel 
    Na VM2
    ./join-channel.sh

## 8 - Build chaincode in HOST
    exit
    cd ~/cenarios-bevel/lab-multi-node/fabric-hlf
    ../../scripts/install-docker.sh
    ./build-chaincode.sh

## 9 - Install chaincode na VM2
    multipass shell vm2
    cd /iliada/lab-multi-node/fabric-hlf || exit  
    ./install-chaincode.sh

## 10 - Consultar o chaincode 
    kubectl hlf chaincode query --config=ifba.yaml \
    --user=ifba-admin-ifba-net \
    --peer=ifba-peer0.ifba-net \
    --chaincode=asset --channel=demo \
    --fcn=GetAllAssets    

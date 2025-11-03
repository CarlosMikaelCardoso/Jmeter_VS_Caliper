# Múltiplos Clústes (Com DNS)
### Documento base: https://github.com/kfsoftware/meetup-k8s-hlf-2024
### Nesse passo a passo vamos apenas subir 2 nodes onde o node1 terá os Orderes e o node2 terá os Peers, CAs e a Chaincode.
### A ideia é que você possa subir mais nodes (Organizações) seguindo os passos do arquivo `steps-lab-multi-node-6-add-org.md`
# Arquitetura de uma rede com 6 nodes
![Minha foto de perfil](Arquitetura_multi_node.jpg)

## 1 - Clonar o Repositório do Projeto em todas as VMs
    git clone --branch instalar-o-cenario-lab-multi-node-fabric-em-vms-da-rnp https://USUARIO_GIT_LAB:TOKEN_ACESSO@git.rnp.br/iliada-blockchain/m3/cenarios-bevel

## 2 - Configurar o DNS Server
### Ir ao diretorio de trabalho do cenário escolhido
    
    cd cenarios-bevel/lab-multi-node/fabric-hlf-6-nodes || exit

## Edit o arquivo ./config.yaml, colocando os IP's das VMs e o IP do DNS (IP_VM1)
    Exemplo:
        vms:
            - name: vm1
                ip: IP_VM1
                dns: vm1.iliada
            - name: vmx
                ip: IP_VMx
                dns: vmx.iliada
        dns_ip: IP_DNS

## Para conseguir o IP do DNS, verifica-se o gateway da VM1 com o comando:
    ip route | grep default

## Ele vai retornar algo como:
    default via 192.168.122.1
    
## Com isso execute ´ip addr´ e procure o IP que esteja na mesma faixa do gateway, por exemplo:
    192.168.122.XX

### 2.1 - Configurando o DNS Server na VM1    
    ./setup-dns.sh config.yaml 

## 3 - Configurar o DNS e Microk8s em todas as VMs

    ../../scripts/setup-microk8s.sh

### 3.1 - Configurando a VM1 como dns fowarder
    ./setup-dns-fowarder.sh config.yaml

    Esse comando fará com que a VM1 encaminhe as requisições DNS das outras VMs para o IP do DNS que foi configurado no arquivo config.yaml

### 3.2 - Execute apenas nos clientes! (Não inclui a VM1)
### Lembre de sempre copiar o config.yaml entre as VMs
    ./config-dns-client.sh config.yaml
    
### 3.3 - Verificando se o DNS está funcionando
    ping vm1.iliada
    ping vm2.iliada

## 4 - Instalar o HLF Operator em todas as VMs
    ./setup-hlf-operator.sh config.yaml
    exit


### Precisa sair e entrar novamente para carregar as variaveis de ambiente do plugin do hlf com o kubernetes

## 5 - Instalar as organizações com suas CAs, Orderes e Peers na VM1

    cd /iliada/lab-multi-node/fabric-hlf-6-nodes || exit  
    ./setup-node1.sh

### 5.1 - Instalar os Peers e Ca's nos clientes em outra VM
    ./setup-nodeX.sh 2 config.yaml 
### Após o termino da execução desse .sh vai ser criado uma pasta em ./org_certificate/node2 copie essa pasta para a VM onde foi instaciada os Orderes (./setup-node1.sh). Faça isso para todos os Nodes que foram criados.

## 6 - Criar Canal na VM1
### Aqui no create channel ele usara os arquivos das pastas copiadas para criar o canal, após o termino do .sh vai criar a pasta ./org_certificates/node1. Copie e cole para todos os cliente da rede.
    ./create-channel.sh 

## 7 - Join Channel em todas as VMs
### Execute na VM onde estiver o node2
    ./join-channel-nodeX.sh 2 config.yaml

## 8 - Build chaincode em outra VM que não esteja o node2
    exit
    cd ~/cenarios-bevel/lab-multi-node/fabric-hlf-6-nodes
    ../../scripts/install-docker.sh
    ./build-chaincode.sh

### 8.2 - Extração de arquivo
### Após o build-chaicode.sh, vai ser criado o asset.tar.gz. Copie e Cole ele para a VM em que estiver o node2 e use os seguintes comandos:
   gunzip < asset.tar.gz | sudo microk8s ctr image import -
   sudo microk8s ctr images list | grep asset

### Atenção: Na adição de uma nova org esse mesmo passo tem que ser realizado. A copia do asset.tar.gz deve ser feita para a VM onde está o nodeX que está sendo adicionado.

## 9 - Install chaincode (Node2)
### A instalação da Chaincode é feita no Node2 então execute o .sh a seguir na VM que ela está.
    cd /iliada/lab-multi-node/fabric-hlf-6-nodes || exit  
    ./install-chaincode.sh

## 10 - Consultar o chaincode 
    kubectl hlf chaincode query --config=node2.yaml \
    --user=node2-admin.node2-net --peer=node2-peer0.node2-net \
    --chaincode=asset --channel=demo \
    --fcn=GetAllAssets



## Comandos uteis
### Criação de VMs
    ../../scripts/setup-VMs-multipass.sh 2 3 3 10
### Ver os pods
    kubectl get pods -A
### Ver os serviços
    kubectl get svc -A
### Ver os logs de um pod
    kubectl logs -n NOME_DO_NAMESPACE NOME_DO_POD
### Descrever um pod
    kubectl describe pod -n NOME_DO_NAMESPACE NOME_DO_POD
### Acessar o pod
    kubectl exec -n NOME_DO_NAMESPACE -it NOME_DO_POD -- /bin/bash

### Inspecionar o canal
    kubectl hlf channel inspect --channel=demo --config=node2.yaml --peer=node2-peer0.node2-net --user=node2-admin.node2-net > canal-inspect.txt

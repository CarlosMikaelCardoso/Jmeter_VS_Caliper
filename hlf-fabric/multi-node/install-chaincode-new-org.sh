#!/usr/bin/env bash
set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes
# set -x # debug mode

# --- VALIDAÇÃO E CONFIGURAÇÃO INICIAL ---
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <nome_do_novo_no> <config.yaml>"
    echo "Exemplo: ./install-chaincode-new-org.sh node3 config.yaml"
    exit 1
fi

NEW_NODE_NAME=$1
GENERAL_CONFIG=$2

if [ ! -f "chaincode.tgz" ] || [ ! -f "chaincode-configs.txt" ]; then
    echo "ERRO: Arquivos 'chaincode.tgz' e 'chaincode-configs.txt' não encontrados."
    echo "Copie-os da VM do nó âncora (node2) antes de executar este script."
    exit 1
fi


source chaincode-configs.txt 

# --- DEFINIÇÃO DAS VARIÁVEIS ---
NEW_ORG_MSP="${NEW_NODE_NAME}MSP"
NEW_NAMESPACE="${NEW_NODE_NAME}-net"
NEW_PEER="${NEW_NODE_NAME}-peer0.${NEW_NAMESPACE}"
NEW_PEER_ADMIN="${NEW_NODE_NAME}-admin.${NEW_NAMESPACE}"


function install_chaincode_on_nodeX() {
    echo "--- Instalando Chaincode no Peer do ${NEW_NODE_NAME} ---"
    # Esta função usa o chaincode.tgz copiado
    kubectl hlf chaincode install --path=./chaincode.tgz \
        --config="${NEW_NODE_NAME}.yaml" --language=golang --label=$CHAINCODE_LABEL \
        --user="${NEW_PEER_ADMIN}" --peer="${NEW_PEER}"
    sleep 5
    kubectl hlf chaincode queryinstalled --config=${NEW_NODE_NAME}.yaml --user=${NEW_PEER_ADMIN} --peer=${NEW_PEER}
}

function deploy_chaincode_container(){
  echo "--- Implantando o Container do Chaincode (localmente para ${NEW_NODE_NAME}) ---"
  
  # 1. Cria o deployment usando o PACKAGE_ID lido do 'chaincode-configs.txt'
  kubectl hlf externalchaincode sync \
    --image="${CHAINCODE_NAME}:${VERSION}" \
    --name=$CHAINCODE_NAME \
    --namespace=default \
    --package-id="${PACKAGE_ID}" \
    --tls-required=false \
    --replicas=1
  
  # Pausa para garantir que o recurso foi criado
  sleep 5

  # 2. Corrige o deployment, forçando a política para "Never"
  echo "--- Forçando a política de imagem para 'Never' ---"
  kubectl patch deployment ${CHAINCODE_NAME} -n default --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Never"}]'
  
  # 3. Aguarda o pod subir com a política correta
  echo "--- Aguardando o pod do chaincode iniciar ---"
  kubectl wait --timeout=180s --for=condition=Available deployment/${CHAINCODE_NAME} -n default
}

main() {
    # Implanta o pod 'asset' no cluster local (VM1)
    deploy_chaincode_container
    
    # Instala a definição no peer 'node3' (que irá se conectar ao pod local)
    install_chaincode_on_nodeX
    
    echo "--- Instalação e Deploy no ${NEW_NODE_NAME} concluídos ---"
    echo "Agora, execute os comandos 'approve' e 'commit' (fornecidos pelo script do node2) nesta VM."
}

main "$@"
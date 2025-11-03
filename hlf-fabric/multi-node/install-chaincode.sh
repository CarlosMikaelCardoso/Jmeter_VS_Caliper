#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

# --- Variáveis de Configuração Inicial ---
CHAINCODE_NAME="asset"
CHAINCODE_LABEL="asset"
VERSION="1.0"
SEQUENCE=1
ENDORSEMENT_POLICY="OR('node2MSP.member')"
PACKAGE_ID="" 

function setup_node2_config() {
    echo "--- Configurando o node2 ---"
    local ns="node2-net"
    local secret_name="node2-cp"
    local admin_user="node2-admin.node2-net"
    
    # Limpa configs antigos
    kubectl delete secret "${secret_name}" -n "${ns}" --ignore-not-found
    if kubectl get fabricnetworkconfigs.hlf.kungfusoftware.es "${secret_name}" --namespace="${ns}" &> /dev/null; then
      echo "NetworkConfig '${secret_name}' encontrado. Deletando..."
      kubectl hlf networkconfig delete --name="${secret_name}" --namespace="${ns}"
      sleep 5 
    else
      echo "NetworkConfig '${secret_name}' não encontrado. Pulando."
    fi

    kubectl hlf -n ${ns} networkconfig create --name=${secret_name} -o node2MSP -c demo --secret=${secret_name}
    sleep 5
    kubectl get secrets -n ${ns} ${secret_name} -o jsonpath="{.data.config\.yaml}" | base64 --decode > "node2.yaml"
    
    patch_network_config "node2.yaml" "node2MSP" "node2-peer0.node2-net" "${admin_user}"

    echo "--- Injetando credenciais do admin diretamente do segredo 'node2-admin' ---"
    local ADMIN_CERT_PEM=$(kubectl get secret node2-admin -n ${ns} -o jsonpath='{.data.cert\.pem}' | base64 --decode)
    local ADMIN_KEY_PEM=$(kubectl get secret node2-admin -n ${ns} -o jsonpath='{.data.key\.pem}' | base64 --decode)

    if [[ -z "$ADMIN_KEY_PEM" ]] || [[ -z "$ADMIN_CERT_PEM" ]]; then
        echo "ERRO CRÍTICO: Não foi possível extrair o certificado ou a chave do segredo 'node2-admin'."
        exit 1
    fi
    
    export ADMIN_CERT_PEM
    export ADMIN_KEY_PEM

    yq e -i '.organizations.node2MSP.users."'"${admin_user}"'".cert.pem = strenv(ADMIN_CERT_PEM)' "node2.yaml"
    yq e -i '.organizations.node2MSP.users."'"${admin_user}"'".key.pem = strenv(ADMIN_KEY_PEM)' "node2.yaml"
    
    echo "Credenciais do admin injetadas com sucesso no node2.yaml."
}

function patch_network_config() {
  local config_file=$1
  local org_msp=$2
  local peer_name=$3
  local user_name=$4

  echo "Corrigindo o arquivo de configuração: ${config_file} para a organização ${org_msp}"
  yq e -i ".organizations.${org_msp}.orderers = [\"node1-ord1.node1-net\", \"node1-ord2.node1-net\", \"node1-ord3.node1-net\"]" "$config_file"
  yq e -i ".channels.demo.orderers = [\"node1-ord1.node1-net\", \"node1-ord2.node1-net\", \"node1-ord3.node1-net\"]" "$config_file"

  for i in {1..3}; do
    local orderer_host="node1-ord${i}.node1-net.vm1.iliada"
    local orderer_name="node1-ord${i}.node1-net"
    local cert_path="org_certificates/node1/node1-ord${i}-tlscert.pem"
    local cert_pem=$(cat "${cert_path}" | sed 's/^[[:space:]]*//')
    yq e -i "
      .orderers[\"${orderer_name}\"].url = \"grpcs://${orderer_host}:443\" |
      .orderers[\"${orderer_name}\"].grpcOptions.allow-insecure = false |
      .orderers[\"${orderer_name}\"].tlsCACerts.pem = \"${cert_pem}\"
    " "$config_file"
  done
  
  yq e -i "
    .channels.demo.peers[\"${peer_name}\"].endorsingPeer = true |
    .channels.demo.peers[\"${peer_name}\"].chaincodeQuery = true |
    .channels.demo.peers[\"${peer_name}\"].ledgerQuery = true |
    .channels.demo.peers[\"${peer_name}\"].eventSource = true
  " "$config_file"

  yq e -i ".client.organization = \"${org_msp}\"" "$config_file"
  yq e -i ".client.user = \"${user_name}\"" "$config_file"
  echo "Arquivo ${config_file} corrigido com sucesso."
}

function package_chaincode() {
    echo "--- Empacotando o Chaincode ---"
    [ -f code.tar.gz ] && rm code.tar.gz
    [ -f chaincode.tgz ] && rm chaincode.tgz

    cat > "metadata.json" <<METADATA-EOF
{ "type": "ccaas", "label": "${CHAINCODE_LABEL}" }
METADATA-EOF

    local chaincode_address="${CHAINCODE_NAME}.default.svc.cluster.local:7052"
    cat > "connection.json" <<CONN_EOF
{ "address": "${chaincode_address}", "dial_timeout": "10s", "tls_required": false }
CONN_EOF

    tar cfz code.tar.gz connection.json
    tar cfz chaincode.tgz metadata.json code.tar.gz
    
    PACKAGE_ID=$(kubectl hlf chaincode calculatepackageid --path=chaincode.tgz --language=golang --label=$CHAINCODE_LABEL)
    echo "PACKAGE_ID=${PACKAGE_ID}"
}

function install_chaincode_on_node2() {
    echo "--- Instalando Chaincode no Peer do node2 ---"
    kubectl hlf chaincode install --path=./chaincode.tgz \
        --config=node2.yaml --language=golang --label=$CHAINCODE_LABEL \
        --user=node2-admin.node2-net --peer=node2-peer0.node2-net
    sleep 5
    kubectl hlf chaincode queryinstalled --config=node2.yaml --user=node2-admin.node2-net --peer=node2-peer0.node2-net
}

function deploy_chaincode_container(){
  echo "--- Implantando o Container do Chaincode ---"
  
  # 1. Cria o deployment com a política padrão (que tentaria usar a internet)
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

function approve_and_commit_definition() {
    echo "--- Aprovando a definição do Chaincode para o node2 ---"
    kubectl hlf chaincode approveformyorg --config=node2.yaml \
        --user=node2-admin.node2-net --peer=node2-peer0.node2-net \
        --package-id="${PACKAGE_ID}" --version "$VERSION" --sequence "$SEQUENCE" \
        --name="${CHAINCODE_NAME}" --policy="${ENDORSEMENT_POLICY}" --channel=demo
    sleep 10

    echo "--- Verificando se o commit está pronto ---"
    kubectl hlf chaincode checkcommitreadiness --channel=demo --chaincode="${CHAINCODE_NAME}" \
        --version="$VERSION" --sequence="$SEQUENCE" --policy="${ENDORSEMENT_POLICY}" \
        --config=node2.yaml --user=node2-admin.node2-net --peer=node2-peer0.node2-net
    sleep 5

    echo "--- Comitando a definição do Chaincode ---"
    kubectl hlf chaincode commit --channel=demo --name="${CHAINCODE_NAME}" \
      --version="$VERSION" --sequence="$SEQUENCE" --policy="${ENDORSEMENT_POLICY}" \
      --config=node2.yaml --user=node2-admin.node2-net \
      --commit-orgs="node2MSP" --mspid=node2MSP
}

function invoke_init_ledger(){
  echo "--- Invocando a função initLedger ---"
  kubectl hlf chaincode invoke --config=node2.yaml \
    --user=node2-admin.node2-net --peer=node2-peer0.node2-net \
    --chaincode=asset --channel=demo \
    --fcn=initLedger
}

function save_initial_configs() {
    echo "--- Salvando configurações iniciais em chaincode-configs.txt ---"
    cat <<EOF > chaincode-configs.txt
CHAINCODE_NAME=${CHAINCODE_NAME}
CHAINCODE_LABEL=${CHAINCODE_LABEL}
VERSION=${VERSION}
PACKAGE_ID=${PACKAGE_ID}
SEQUENCE=${SEQUENCE}
ENDORSEMENT_POLICY="${ENDORSEMENT_POLICY}"
EOF
    echo "Configurações salvas com sucesso. A rede está pronta para adicionar novas organizações."
}

main() {   
  setup_node2_config
  package_chaincode
  install_chaincode_on_node2
  deploy_chaincode_container
  approve_and_commit_definition
  sleep 20 
  invoke_init_ledger
  save_initial_configs
}

main "$@"

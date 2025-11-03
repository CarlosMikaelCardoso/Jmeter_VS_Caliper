#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

# --- Validação e Configuração ---
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <node_number> <caminho_para_config.yaml>"
    echo "Exemplo: $0 3 config.yaml"
    exit 1
fi

CONFIG_FILE="$2"
NODE_NUMBER="$1"
NODE_NAME="node${NODE_NUMBER}"

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

function patch_network_config_with_identity() {
    local config_file=$1
    local org_msp=$2
    local peer_name=$3
    local user_name=$4
    local ns="${NODE_NAME}-net"

    echo "Corrigindo e injetando identidade em: ${config_file}"

    # 1. Extrai a identidade completa do segredo do admin
    local ADMIN_CERT_PEM=$(kubectl get secret ${NODE_NAME}-admin -n ${ns} -o jsonpath='{.data.cert\.pem}' | base64 --decode)
    local ADMIN_KEY_PEM=$(kubectl get secret ${NODE_NAME}-admin -n ${ns} -o jsonpath='{.data.key\.pem}' | base64 --decode)

    if [[ -z "$ADMIN_KEY_PEM" ]] || [[ -z "$ADMIN_CERT_PEM" ]]; then
        echo "ERRO CRÍTICO: Não foi possível extrair o certificado ou a chave do segredo '${NODE_NAME}-admin'."
        exit 1
    fi
    
    # Exporta as variáveis para o yq
    export org_msp
    export user_name
    export ADMIN_CERT_PEM
    export ADMIN_KEY_PEM

    # Encadeia as modificações para evitar problemas com a edição in-place
    yq e '
        .client.organization = strenv(org_msp) |
        .client.user = strenv(user_name) |
        .organizations[strenv(org_msp)].users[strenv(user_name)].cert.pem = strenv(ADMIN_CERT_PEM) |
        .organizations[strenv(org_msp)].users[strenv(user_name)].key.pem = strenv(ADMIN_KEY_PEM)
    ' "${config_file}" > "${config_file}.tmp"
    
    # Substitui o arquivo original
    mv "${config_file}.tmp" "${config_file}"

    echo "Arquivo ${config_file} corrigido com a identidade do admin."
}

function create_network_config() {
  local node="${NODE_NAME}"
  local ns="${node}-net"
  local msp_name="${node}MSP"
  local identity_name="${node}-admin.${ns}"
  local secret_name="${node}-cp"
  local peer_name="${node}-peer0.${ns}"

  echo "Recriando networkconfig para ${node}..."
  kubectl delete fabricnetworkconfigs.hlf.kungfusoftware.es ${secret_name} -n ${ns} --ignore-not-found
  kubectl delete secret ${secret_name} -n ${ns} --ignore-not-found
  sleep 2

  # A lógica para obter a lista de MSPs continua a mesma
  local all_msps
  if [ -f "chaincode-configs.txt" ]; then
      source chaincode-configs.txt
      local existing_msps=$(echo "${ENDORSEMENT_POLICY}" | grep -o "'[a-zA-Z0-9]\+MSP" | sed "s/'//g" | tr '\n' ',' | sed 's/,$//')
      all_msps="node1MSP,${existing_msps},${msp_name}"
      all_msps=$(echo "${all_msps}" | awk -v RS=, '{if(!a[$1]++)print}' | paste -sd, -)
  else
      all_msps="node1MSP,node2MSP,node3MSP" # Fallback simples
  fi

  echo "Criando networkconfig base para ${node}..."
  kubectl hlf -n ${ns} networkconfig create --name=${secret_name} --identities=${identity_name} --secret=${secret_name} -o "${all_msps}" -c demo
  sleep 10

  echo "Salvando o arquivo de configuração para o disco..."
  kubectl get secrets -n ${ns} ${secret_name} -o jsonpath='{.data.config\.yaml}' | base64 --decode > "${node}.yaml"

  # CHAMADA PARA A FUNÇÃO DE CORREÇÃO (ORDERERS/PEERS)
  patch_network_config "${node}.yaml" "${msp_name}" "${peer_name}" "${identity_name}"

  # CHAMADA PARA A FUNÇÃO DE CORREÇÃO COM INJEÇÃO DE IDENTIDADE
  patch_network_config_with_identity "${node}.yaml" "${msp_name}" "${peer_name}" "${identity_name}"

  echo "Arquivo ${node}.yaml criado e totalmente configurado com sucesso."
}

main() {
  create_network_config
}

main "$@"
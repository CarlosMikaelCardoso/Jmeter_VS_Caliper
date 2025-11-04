#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
config_dir="${script_dir}/configs"
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
shared_chart_dir="${tmp_dir}/bevel/platforms/shared/charts"
start_dir=$(pwd)

# --- FUNÇÃO PARA LER O ARQUIVO YAML ---
function get_vm_info() {
  local vm_name="$1"
  local info_type="$2" # pode ser "ip" ou "dns"
  yq e ".vms[] | select(.name == \"${vm_name}\") | .${info_type}" "${start_dir}/config.yaml"
}

# --- FUNÇÃO PARA COPIAR CERTIFICADOS DOS NÓS REMOTOS ---
# function transfer_certs_from_nodeX() {
#   local org_name="$1"
#   local remote_user="$2"
#   local remote_ip=$(get_vm_info "vm${org_name: -1}" "ip")
  
#   if [ -z "${remote_user}" ] || [ -z "${remote_ip}" ]; then
#     echo "ERRO: O nome de usuário ou o IP remoto não foi fornecido."
#     return 1
#   fi

#   echo "Copiando arquivos de identidade da organização ${org_name} para a VM local..."

#   scp -r "${remote_user}@${remote_ip}:/home/fabric/cenarios-bevel/lab-multi-node/fabric-hlf-6-nodes/org_certificates/${org_name}" "./org_certificates/"

#   if [ $? -eq 0 ]; then
#     echo "Transferência de arquivos de identidade para ${org_name} concluída com sucesso."
#   else
#     echo "ERRO: Falha ao transferir arquivos de identidade de ${org_name}."
#     return 1
#   fi
# }

# --- FUNÇÃO PARA PEGAR CERTIFICADOS DO NODE1 ---
function certs_node1() {
  local base_certs_dir="org_certificates"
  mkdir -p "${base_certs_dir}"

  local IDENT_8
  IDENT_8=$(printf "%8s" "")

  local org_node1_name="node1"
  local org_node1_ns="node1-net"
  local org_node1_ca_name="node1-ca"
  local org_node1_dir="${base_certs_dir}/${org_node1_name}"

  echo "Processando organização: ${org_node1_name} (namespace: ${org_node1_ns})"
  mkdir -p "${org_node1_dir}"

  echo "  Salvando certificado CA de assinatura para ${org_node1_name}..."
  kubectl -n "${org_node1_ns}" get fabriccas "${org_node1_ca_name}" -o=jsonpath='{.status.ca_cert}' | sed -e "s/^/${IDENT_8}/" > "${org_node1_dir}/${org_node1_ca_name}-signcert.pem"

  echo "  Salvando certificado CA TLS para ${org_node1_name}..."
  kubectl -n "${org_node1_ns}" get fabriccas "${org_node1_ca_name}" -o=jsonpath='{.status.tlsca_cert}' | sed -e "s/^/${IDENT_8}/" > "${org_node1_dir}/${org_node1_ca_name}-tlscert.pem"
  
  echo "  Salvando os certificados TLS dos Orderers para as VMs externas..."
  for i in 1 2 3; do
    local orderer_name="${org_node1_name}-ord${i}"
    local orderer_cert_output_path="${org_node1_dir}/${orderer_name}-tlscert.pem"
    echo "    - Salvando certificado para ${orderer_name}..."
    
    local orderer_tls_cert=$(kubectl -n "${org_node1_ns}" get fabricorderernodes "${orderer_name}" -o=jsonpath='{.status.tlsCert}')
    if [[ -z "${orderer_tls_cert}" ]]; then
      echo "    ERRO: Não foi possível obter o certificado TLS para ${orderer_name}."
      return 1
    fi
    
    echo "${orderer_tls_cert}" | sed -e "s/^/${IDENT_8}/" > "${orderer_cert_output_path}"
    
    if [[ $? -eq 0 && -s "${orderer_cert_output_path}" ]]; then
      echo "      Certificado salvo em ${orderer_cert_output_path}"
    else
      echo "      ERRO ao salvar certificado TLS para ${orderer_name} ou o certificado está vazio."
    fi
  done
}

# --- FUNÇÃO PARA TRANSFERIR CERTIFICADOS PARA OS NÓS REMOTOS ---
# function transfer_certs_to_nodeX() {
#   local org_name="$1"
#   local remote_user="$2"
#   local remote_ip=$(get_vm_info "vm${org_name: -1}" "ip")
#   local certs_dir="./org_certificates/node1"
#   local remote_certs_dir="/home/fabric/cenarios-bevel/lab-multi-node/fabric-hlf-6-nodes/org_certificates/node1"

#   echo "Copiando certificados dos Orderers da VM1 para a VM remota ${remote_ip}..."
#   scp -r "${certs_dir}" "${remote_user}@${remote_ip}:${remote_certs_dir}"

#   if [ $? -eq 0 ]; then
#     echo "Transferência de certificados dos Orderers concluída com sucesso."
#   else
#     echo "ERRO: Falha ao transferir certificados dos Orderers para a VM remota."
#     return 1
#   fi
# }

# --- FUNÇÃO PARA CRIAR SECRETS E WALLETS NO NODE1 ---
function create_wallet_secrets_node1(){
  local org_name="node1"
  local ns="${org_name}-net"
  kubectl delete FabricMainChannel demo --ignore-not-found
  kubectl delete fabricidentities.hlf.kungfusoftware.es --all-namespaces --all


  kubectl get ns "${ns}" > /dev/null 2>&1 || kubectl create namespace "${ns}"

  kubectl hlf ca register --namespace="${ns}" --name="${org_name}-ca" --user=admin --secret=adminpw \
    --type=admin --enroll-id enroll --enroll-secret=enrollpw --mspid=node1MSP \
    --ca-url="https://node1-ca.node1-net.vm1.fabric:443" || echo "AVISO: Falha ao registrar admin para ${org_name}, pode já estar registrado. Continuando..."
  sleep 30

  kubectl hlf identity create --name node1-admin-sign --namespace="${ns}" \
    --ca-name "${org_name}-ca" --ca-namespace "${ns}" \
    --ca ca --mspid node1MSP --enroll-id admin --enroll-secret adminpw
  sleep 30

  kubectl hlf identity create --name node1-admin-tls --namespace="${ns}"  \
    --ca-name "${org_name}-ca" --ca-namespace "${ns}" \
    --ca tlsca --mspid node1MSP --enroll-id admin --enroll-secret adminpw
  sleep 30

  # Cria o namespace para o node2 (removido o loop para os outros nós para simplificar o exemplo)
  kubectl create namespace node2-net --dry-run=client -o yaml | kubectl apply -f -
  sleep 10
  # kubectl create namespace node3-net --dry-run=client -o yaml | kubectl apply -f -
  # sleep 10
  # kubectl create namespace node4-net --dry-run=client -o yaml | kubectl apply -f -
  # sleep 10
  # kubectl create namespace node5-net --dry-run=client -o yaml | kubectl apply -f -
  # sleep 10
  # kubectl create namespace node6-net --dry-run=client -o yaml | kubectl apply -f -
  # sleep 10

  # Aplica os segredos E as identidades transferidos
  echo "Aplicando segredo e identidade do node2 na vm1..."
  kubectl apply -f ./org_certificates/node2/node2-admin-secret.yaml -n node2-net
  kubectl apply -f ./org_certificates/node2/node2-admin-identity.yaml -n node2-net 
  # echo "Aplicando segredo e identidade do node3 na vm1..."
  # kubectl apply -f ./org_certificates/node3/node3-admin-secret.yaml -n node3-net
  # kubectl apply -f ./org_certificates/node3/node3-admin-identity.yaml -n node3-net 
  # echo "Aplicando segredo e identidade do node4 na vm1..."
  # kubectl apply -f ./org_certificates/node4/node4-admin-secret.yaml -n node4-net
  # kubectl apply -f ./org_certificates/node4/node4-admin-identity.yaml -n node4-net 
  # echo "Aplicando segredo e identidade do node5 na vm1..."
  # kubectl apply -f ./org_certificates/node5/node5-admin-secret.yaml -n node5-net
  # kubectl apply -f ./org_certificates/node5/node5-admin-identity.yaml -n node5-net 
  # echo "Aplicando segredo e identidade do node6 na vm1..."
  # kubectl apply -f ./org_certificates/node6/node6-admin-secret.yaml -n node6-net
  # kubectl apply -f ./org_certificates/node6/node6-admin-identity.yaml -n node6-net

  echo "Aguardando 10 segundos para os recursos do node2 serem aplicados no cluster..."
  sleep 10
}

# --- FUNÇÃO PARA CRIAR O CANAL ---
function create_channel(){
  local org_name="node1"
  local ns_orderer="${org_name}-net"
  local base_certs_dir="org_certificates"
  local node2_certs_dir="${base_certs_dir}/node2"
  local node2_ca_name="node2-ca"
  # local node3_certs_dir="${base_certs_dir}/node3"
  # local node3_ca_name="node3-ca"
  # local node4_certs_dir="${base_certs_dir}/node4"
  # local node4_ca_name="node4-ca"
  # local node5_certs_dir="${base_certs_dir}/node5"
  # local node5_ca_name="node5-ca"
  # local node6_certs_dir="${base_certs_dir}/node6"
  # local node6_ca_name="node6-ca"

  export NODE2_SIGN_ROOT_CERT
  NODE2_SIGN_ROOT_CERT=$(cat "${node2_certs_dir}/${node2_ca_name}-signcert.pem")
  export NODE2_TLS_ROOT_CERT
  NODE2_TLS_ROOT_CERT=$(cat "${node2_certs_dir}/${node2_ca_name}-tlscert.pem")

  # export NODE3_SIGN_ROOT_CERT
  # NODE3_SIGN_ROOT_CERT=$(cat "${node3_certs_dir}/${node3_ca_name}-signcert.pem")
  # export NODE3_TLS_ROOT_CERT
  # NODE3_TLS_ROOT_CERT=$(cat "${node3_certs_dir}/${node3_ca_name}-tlscert.pem")

  # export NODE4_SIGN_ROOT_CERT
  # NODE4_SIGN_ROOT_CERT=$(cat "${node4_certs_dir}/${node4_ca_name}-signcert.pem")
  # export NODE4_TLS_ROOT_CERT
  # NODE4_TLS_ROOT_CERT=$(cat "${node4_certs_dir}/${node4_ca_name}-tlscert.pem")

  # export NODE5_SIGN_ROOT_CERT
  # NODE5_SIGN_ROOT_CERT=$(cat "${node5_certs_dir}/${node5_ca_name}-signcert.pem")
  # export NODE5_TLS_ROOT_CERT
  # NODE5_TLS_ROOT_CERT=$(cat "${node5_certs_dir}/${node5_ca_name}-tlscert.pem")

  # export NODE6_SIGN_ROOT_CERT
  # NODE6_SIGN_ROOT_CERT=$(cat "${node6_certs_dir}/${node6_ca_name}-signcert.pem")
  # export NODE6_TLS_ROOT_CERT
  # NODE6_TLS_ROOT_CERT=$(cat "${node6_certs_dir}/${node6_ca_name}-tlscert.pem")

  kubectl get ns ${ns_orderer} >/dev/null 2>&1 || kubectl create namespace ${ns_orderer} 

  export IDENT_8=$(printf "%8s" "")
  export ORDERER_TLS_CERT=$(kubectl -n ${ns_orderer} get fabriccas node1-ca -o=jsonpath='{.status.tlsca_cert}' | sed -e "s/^/${IDENT_8}/" )
  export ORDERER1_TLS_CERT=$(kubectl -n ${ns_orderer} get fabricorderernodes node1-ord1 -o=jsonpath='{.status.tlsCert}' | sed -e "s/^/${IDENT_8}/" )
  export ORDERER2_TLS_CERT=$(kubectl -n ${ns_orderer} get fabricorderernodes node1-ord2 -o=jsonpath='{.status.tlsCert}' | sed -e "s/^/${IDENT_8}/" )
  export ORDERER3_TLS_CERT=$(kubectl -n ${ns_orderer} get fabricorderernodes node1-ord3 -o=jsonpath='{.status.tlsCert}' | sed -e "s/^/${IDENT_8}/" )

  cat <<EOF > /tmp/fabric_main_channel_apply.yaml
apiVersion: hlf.kungfusoftware.es/v1alpha1
kind: FabricMainChannel
metadata:
  name: demo
spec:
  name: demo
  adminOrdererOrganizations:
    - mspID: node1MSP
  adminPeerOrganizations:
    - mspID: node2MSP
  channelConfig:
    application:
      acls: null
      capabilities:
        - V2_0
      policies: null
    capabilities:
      - V2_0
    orderer:
      batchSize:
        absoluteMaxBytes: 1048576
        maxMessageCount: 10
        preferredMaxBytes: 524288
      batchTimeout: 2s
      capabilities:
        - V2_0
      etcdRaft:
        options:
          electionTick: 10
          heartbeatTick: 1
          maxInflightBlocks: 5
          snapshotIntervalSize: 16777216
          tickInterval: 500ms
      ordererType: etcdraft
      policies: null
      state: STATE_NORMAL
    policies: null
  externalOrdererOrganizations: []
  peerOrganizations: [] 
  externalPeerOrganizations: 
    - mspID: node2MSP
      signRootCert: |-
${NODE2_SIGN_ROOT_CERT}
      tlsRootCert: |-
${NODE2_TLS_ROOT_CERT}
  identities:
    node1MSP: 
      secretKey: user.yaml
      secretName: node1-admin-tls
      secretNamespace: ${ns_orderer}
    node1MSP-sign: 
      secretKey: user.yaml
      secretName: node1-admin-sign
      secretNamespace: ${ns_orderer}
    node2MSP: 
      secretKey: user.yaml
      secretName: node2-admin
      secretNamespace: node2-net
  ordererOrganizations:
    - caName: "${org_name}-ca"
      caNamespace: "${ns_orderer}"
      externalOrderersToJoin:
        - host: ${org_name}-ord1.${ns_orderer} 
          port: 7053
        - host: ${org_name}-ord2.${ns_orderer}
          port: 7053
        - host: ${org_name}-ord3.${ns_orderer}
          port: 7053
      mspID: node1MSP
      ordererEndpoints:
        - ${org_name}-ord1.${ns_orderer}.vm1.fabric:443
        - ${org_name}-ord2.${ns_orderer}.vm1.fabric:443
        - ${org_name}-ord3.${ns_orderer}.vm1.fabric:443
      orderersToJoin: []
  orderers:
    - host: ${org_name}-ord1.${ns_orderer}.vm1.fabric
      port: 443
      tlsCert: |-
${ORDERER1_TLS_CERT}
    - host: ${org_name}-ord2.${ns_orderer}.vm1.fabric
      port: 443
      tlsCert: |-
${ORDERER2_TLS_CERT}
    - host: ${org_name}-ord3.${ns_orderer}.vm1.fabric
      port: 443
      tlsCert: |-
${ORDERER3_TLS_CERT} 
EOF

  echo "DEBUG: Conteúdo do YAML que será aplicado:"
  cat /tmp/fabric_main_channel_apply.yaml
  
  kubectl apply -f /tmp/fabric_main_channel_apply.yaml

  echo "Aguardando o canal 'demo' no namespace '${ns_orderer}' ficar pronto..."
  kubectl wait FabricMainChannel/demo --for=condition=Running --timeout=300s -n "${ns_orderer}"
  echo "Canal 'demo' está pronto ou o tempo de espera esgotou."
}

# --- FUNÇÃO PRINCIPAL QUE ORQUESTRA O FLUXO ---
function main() {
  # local remote_user="fabric"
  # local vm_peers=("node2" "node3") # Para testar com múltiplos nós, adicione-os aqui.

  # Etapa 1: Copia os certificados dos peers remotos para o nó local (VM1).
  # for node in "${vm_peers[@]}"; do
  #   transfer_certs_from_nodeX "${node}" "${remote_user}"
  #   sleep 20
  # done

  # Etapa 2: Cria os segredos e identidades do node1 e aplica os segredos dos peers.
  create_wallet_secrets_node1
  sleep 20
  
  # Etapa 3: Obtém os certificados da CA e dos Orderers do node1.
  certs_node1
  sleep 20
  
  # Etapa 4: Cria o canal principal.
  create_channel
  sleep 20

  # Etapa 5: Copia os certificados dos Orderers do node1 para os peers remotos.
  # for node in "${vm_peers[@]}"; do
  #   transfer_certs_to_nodeX "${node}" "${remote_user}"
  #   sleep 20
  # done
}

main "$@"
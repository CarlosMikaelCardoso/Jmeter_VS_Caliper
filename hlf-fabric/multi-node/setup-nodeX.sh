#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

PEER_IMAGE=hyperledger/fabric-peer
PEER_VERSION=2.5.13

ORDERER_IMAGE=hyperledger/fabric-orderer
ORDERER_VERSION=2.5.13

CA_IMAGE=hyperledger/fabric-ca
CA_VERSION=1.5.15

SC_NAME="microk8s-hostpath"
BASE_CERTS_DIR="org_certificates"
mkdir -p "${BASE_CERTS_DIR}" # Garante que o diretório base exista

# --- MODIFICAÇÃO: Remover atribuições estáticas ---
# As variáveis NODE_NUMBER, NODE_NAME e DNS_SUFFIX serão definidas na função main.
# --- Fim das modificações ---


# function install_haproxy(){
#   helm repo add haproxytech https://hapraproxytech.github.io/helm-charts
#   helm repo update

#   helm upgrade --install --create-namespace --namespace "ingress-controller" \
#     haproxy haproxytech/kubernetes-ingress \
#     --version 1.44.3 --set controller.kind=DaemonSet

#   sleep 10
#   kubectl annotate service haproxy-kubernetes-ingress -n ingress-controller --overwrite "external-dns.alpha.kubernetes.io/hostname=*.${DNS_SUFFIX}"
  
#   sleep 20
# }

function install_nodeX(){
  local org_name="${NODE_NAME}"
  local ns="${org_name}-net"

  kubectl get ns ${ns} || kubectl create namespace ${ns} 

  # Create the certification authority
  kubectl hlf ca create --namespace=${ns} --image=$CA_IMAGE --version=$CA_VERSION --storage-class=$SC_NAME --capacity=1Gi --name=${org_name}-ca --enroll-id=enroll --enroll-pw=enrollpw --hosts=${org_name}-ca.${ns}.${DNS_SUFFIX} --istio-port=443

  sleep 50
  kubectl wait --namespace=${ns} --for=condition=ready --timeout=200s pod -l app=hlf-ca
  
  # test the CA  
  sleep 10
  curl -vik https://${org_name}-ca.${ns}.${DNS_SUFFIX}:443/cainfo

  kubectl hlf ca register --namespace=${ns} --name=${org_name}-ca --user=peer --secret=peerpw --type=peer --enroll-id enroll --enroll-secret=enrollpw --mspid ${org_name}MSP

  sleep 50
  kubectl hlf peer create --namespace=${ns} --statedb=leveldb --image=$PEER_IMAGE --version=$PEER_VERSION --storage-class=$SC_NAME --enroll-id=peer --mspid=${org_name}MSP --enroll-pw=peerpw --capacity=4Gi --name=${org_name}-peer0 --ca-name=${org_name}-ca.${ns} --hosts=${org_name}-peer0.${ns}.${DNS_SUFFIX} --istio-port=443

  sleep 30
  kubectl wait --namespace=${ns} --for=condition=ready --timeout=100s pod -l app=hlf-peer

  sleep 20
}

function create_wallet_secrets_nodeX(){
  local org_name="${NODE_NAME}"
  local ns="${org_name}-net"
  local msp_name="${NODE_NAME}MSP"

  kubectl get ns ${ns} > /dev/null 2>&1 || kubectl create namespace ${ns}

  kubectl hlf ca register --name="${org_name}"-ca --namespace=${ns} --user=admin --secret=adminpw \
    --type=admin --enroll-id enroll --enroll-secret=enrollpw --mspid=${msp_name} || echo "AVISO: Registro de admin para ${org_name} falhou, pode já existir."

  sleep 30

  kubectl hlf identity create --name "${org_name}"-admin --namespace ${ns} \
    --ca-name "${org_name}-ca" --ca-namespace ${ns} \
    --ca ca --mspid ${msp_name} --enroll-id admin --enroll-secret adminpw

  echo "Aguardando o segredo ${org_name}-admin estar disponível..."
  SECONDS=0 
  while ! kubectl get secret "${org_name}-admin" -n "${ns}" -o name > /dev/null 2>&1; do
    if [ "$SECONDS" -ge 30 ]; then 
      echo "ERRO: Timeout aguardando o segredo ${org_name}-admin em ${ns}."
      kubectl get events -n "${ns}" --sort-by='.metadata.creationTimestamp' # Mostra eventos recentes para depuração
      return 1
    fi
    echo "Ainda aguardando segredo ${org_name}-admin... (${SECONDS}s)"
    sleep 2
  done
  echo "Segredo ${org_name}-admin encontrado."

  local org_output_dir="${BASE_CERTS_DIR}/${org_name}"
  mkdir -p "${org_output_dir}"

  # --- Exportação do Secret ---
  echo "Exportando e limpando o segredo admin para ${org_name}..."
  sleep 30

  local RAW_SECRET_YAML=$(kubectl get secret "${org_name}-admin" -n "${ns}" -o yaml)
  if [ $? -ne 0 ] || [ -z "${RAW_SECRET_YAML}" ]; then
      echo "ERRO: Falha ao obter o YAML do segredo ${org_name}-admin da ${ns}."
      return 1
  fi
  
  local CLEANED_SECRET_YAML=$(clean_k8s_secret_yaml_embedded "${RAW_SECRET_YAML}")
  if [ -z "${CLEANED_SECRET_YAML}" ] || [ "${CLEANED_SECRET_YAML}" == "{}" ] || [ "${CLEANED_SECRET_YAML}" == "null" ] || [ "${CLEANED_SECRET_YAML}" == "{}\n" ]; then
      echo "ERRO: O YAML limpo para o segredo ${org_name}-admin está vazio ou inválido."
      return 1
  fi
  echo "${CLEANED_SECRET_YAML}" > "${org_output_dir}/${org_name}-admin-secret.yaml"
  echo "Segredo ${org_name}-admin-secret.yaml salvo e limpo em ${org_output_dir}/"

  # --- Exportação da FabricIdentity ---
  echo "Exportando e limpando a FabricIdentity para ${org_name}..."
  sleep 30

  local RAW_IDENTITY_YAML=$(kubectl get fabricidentities "${org_name}-admin" -n "${ns}" -o yaml)
  if [ $? -ne 0 ] || [ -z "${RAW_IDENTITY_YAML}" ]; then
      echo "ERRO: Falha ao obter o YAML da identidade ${org_name}-admin da ${ns}."
      return 1
  fi

  local CLEANED_IDENTITY_YAML=$(clean_k8s_secret_yaml_embedded "${RAW_IDENTITY_YAML}")
  if [ -z "${CLEANED_IDENTITY_YAML}" ] || [ "${CLEANED_IDENTITY_YAML}" == "{}" ] || [ "${CLEANED_IDENTITY_YAML}" == "null" ] || [ "${CLEANED_IDENTITY_YAML}" == "{}\n" ]; then
      echo "ERRO: O YAML limpo para a identidade ${org_name}-admin está vazio ou inválido."
      return 1
  fi
  echo "${CLEANED_IDENTITY_YAML}" > "${org_output_dir}/${org_name}-admin-identity.yaml"
  echo "FabricIdentity ${org_name}-admin-identity.yaml salva e limpa em ${org_output_dir}/"
}

function clean_k8s_secret_yaml_embedded() {
  local raw_yaml_content="$1"

  python3 -c '
import yaml, sys

raw_yaml = sys.stdin.read()
cleaned_yaml_output = "{}" # Default para um objeto YAML vazio em caso de erro

try:
    data = yaml.safe_load(raw_yaml)
    if isinstance(data, dict): # Procede apenas se um dicionário YAML válido foi carregado
        metadata = data.get("metadata") # Obtém o dicionário de metadados
        if isinstance(metadata, dict): # Verifica se metadata é realmente um dicionário
            metadata.pop("ownerReferences", None)
            metadata.pop("creationTimestamp", None)
            metadata.pop("resourceVersion", None)
            metadata.pop("uid", None)
            if not metadata: # Se o dicionário metadata ficou vazio, remove-o
                data.pop("metadata", None)
        
        # Usa yaml.dump para converter o objeto Python de volta para uma string YAML
        # sort_keys=False tenta manter a ordem original das chaves o máximo possível
        # default_flow_style=False produz um estilo de bloco mais legível
        cleaned_yaml_output = yaml.dump(data, sort_keys=False, allow_unicode=True, default_flow_style=False)
    else:
        # Se a entrada não for um dicionário YAML (ex: erro do kubectl, ou YAML inválido)
        sys.stderr.write("Python: Entrada não era um dicionário YAML válido ou estava vazia.\n")
        # A saída já é "{}" (objeto YAML vazio) por padrão

except Exception as e:
    sys.stderr.write(f"Python: Erro durante o processamento do YAML: {e}\n")
    # A saída já é "{}" (objeto YAML vazio) por padrão

print(cleaned_yaml_output)
' <<< "${raw_yaml_content}"
}

function deleteAll() {
  NAMESPACE="node${NODE_NUMBER}-net"
  # Deleta 'fabricpeers', 'fabriccas' e 'fabricidentities' usando --ignore-not-found
  kubectl delete fabricpeers.hlf.kungfusoftware.es "${NODE_NAME}-peer0" --namespace="${NAMESPACE}" --ignore-not-found
  kubectl delete fabriccas.hlf.kungfusoftware.es "${NODE_NAME}-ca" --namespace="${NAMESPACE}" --ignore-not-found
  kubectl delete fabricidentities.hlf.kungfusoftware.es "${NODE_NAME}-admin" --namespace="${NAMESPACE}" --ignore-not-found

  # Adição: Verifica a existência do networkconfig antes de tentar deletar
  if kubectl get fabricnetworkconfigs.hlf.kungfusoftware.es "${NODE_NAME}-cp" --namespace="${NAMESPACE}" &> /dev/null; then
    echo "NetworkConfig '${NODE_NAME}-cp' encontrado. Deletando..."
    # Comando de deleção sem a flag --ignore-not-found
    kubectl hlf networkconfig delete --name="${NODE_NAME}-cp" --namespace="${NAMESPACE}"
  else
    echo "NetworkConfig '${NODE_NAME}-cp' não encontrado. Pulando."
  fi
}

# Comentário sobre a modificação:
# Esta função foi corrigida para gerar arquivos de certificado PEM válidos. A versão
# anterior criava arquivos com cabeçalhos duplicados. Esta versão garante que
# o conteúdo do certificado seja extraído e formatado corretamente, fornecendo
# os dados limpos que a função 'update_channel_definition' precisa para operar
# sem causar o erro "failed to decode PEM block".

function certs() {
  local IDENT_8
  IDENT_8=$(printf "%8s" "")

  # Organização IFBA
  local org_name="${NODE_NAME}"
  local ns="${org_name}-net"
  local msp_name="${NODE_NAME}MSP"
  local org_nodeX_ca_name="${org_name}-ca" # Nome da CA usado ao salvar os arquivos
  local org_nodeX_dir="${BASE_CERTS_DIR}/${org_name}"
  mkdir -p "${org_nodeX_dir}" # Garante que o diretório da organização exista

  echo "Processando certificados CA para organização: ${org_name} (namespace: ${ns})"
  kubectl -n "${ns}" get fabriccas "${org_nodeX_ca_name}" -o=jsonpath='{.status.ca_cert}' | sed -e "s/^/${IDENT_8}/" > "${org_nodeX_dir}/${org_nodeX_ca_name}-signcert.pem"
  kubectl -n "${ns}" get fabriccas "${org_nodeX_ca_name}" -o=jsonpath='{.status.tlsca_cert}' | sed -e "s/^/${IDENT_8}/" > "${org_nodeX_dir}/${org_nodeX_ca_name}-tlscert.pem"

}

# --- NOVA FUNÇÃO ---
# A função 'set_dns_suffix' lê o arquivo de configuração, detecta o IP local
# e define a variável DNS_SUFFIX com base no nome de DNS correspondente.
function set_dns_suffix() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        echo "ERRO: Arquivo de configuração '$config_file' não encontrado."
        exit 1
    fi

    # Garante que yq está instalado
    if ! command -v yq &> /dev/null; then
        echo "Instalando yq..."
        YQ_VERSION=v4.40.5
        wget -q https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O yq && chmod +x yq && sudo mv yq /usr/bin/yq
    fi

    # Obtém o primeiro IP não-localhost da máquina
    local current_ip
    current_ip=$(hostname -I | awk '{print $1}')

    if [ -z "$current_ip" ]; then
        echo "ERRO: Não foi possível obter o endereço IP da máquina atual."
        exit 1
    fi

    echo "IP detectado na máquina atual: ${current_ip}"

    # Usa yq para encontrar o DNS correspondente ao IP no arquivo de configuração
    # A variável DNS_SUFFIX é exportada para ser usada globalmente no script.
    DNS_SUFFIX=$(yq e ".vms[] | select(.ip == \"${current_ip}\") | .dns" "${config_file}")

    if [ -z "$DNS_SUFFIX" ] || [ "$DNS_SUFFIX" == "null" ]; then
        echo "ERRO: IP ${current_ip} não encontrado ou sem DNS correspondente em ${config_file}."
        exit 1
    fi

    echo "DNS Suffix configurado dinamicamente para: ${DNS_SUFFIX}"
}

# --- FUNÇÃO MAIN MODIFICADA ---
# A função 'main' agora valida os argumentos, chama a nova função set_dns_suffix
# para configurar o DNS dinamicamente e define as variáveis NODE_NUMBER e NODE_NAME.
main() {
  if [ "$#" -ne 2 ]; then
      echo "Uso: $0 <node_number> <caminho_para_config.yaml>"
      echo "Exemplo: $0 1 config.yaml"
      exit 1
  fi

  # Define as variáveis globais com base nos argumentos
  NODE_NUMBER="$1"
  NODE_NAME="node${NODE_NUMBER}"

  # Chama a nova função para definir o DNS_SUFFIX
  set_dns_suffix "$2"

  deleteAll
  # install_haproxy
  # sleep 10
  install_nodeX
  sleep 20
  create_wallet_secrets_nodeX
  sleep 20
  certs
}

main "$@"
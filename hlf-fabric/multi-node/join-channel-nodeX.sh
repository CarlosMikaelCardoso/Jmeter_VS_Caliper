#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

# Função para a organização nodeX entrar no canal
function join_channel_nodeX(){
  # Usar a variável NODE_NAME
  local org_name="${NODE_NAME}"
  local ns="${org_name}-net"
  local base_certs_dir="org_certificates"
  local MSP_name="${org_name}MSP"
  local msp_name="${org_name}msp"
  
  # Lê os certificados dos 3 orderers
  export ORDERER1_TLS_CERT=$(cat "${base_certs_dir}/node1/node1-ord1-tlscert.pem")
  export ORDERER2_TLS_CERT=$(cat "${base_certs_dir}/node1/node1-ord2-tlscert.pem")
  export ORDERER3_TLS_CERT=$(cat "${base_certs_dir}/node1/node1-ord3-tlscert.pem")

  # MODIFICAÇÃO: Constrói o host do peer usando a variável DNS_SUFFIX
  local peer_host="${org_name}-peer0.${ns}.${DNS_SUFFIX}"

  cat <<EOF | kubectl apply -f -
apiVersion: hlf.kungfusoftware.es/v1alpha1
kind: FabricFollowerChannel
metadata:
  # Usar as variáveis
  name: demo-${msp_name}
  namespace: ${ns}
spec:
  name: demo
  mspId: ${MSP_name}
  hlfIdentity:
    # Usar as variáveis
    secretName: ${org_name}-admin
    secretKey: user.yaml
    secretNamespace: ${ns}
  anchorPeers:
    - host: ${peer_host}
      port: 443
  peersToJoin:
    - name: ${org_name}-peer0
      namespace: ${ns}
  externalPeersToJoin: []
  orderers:
    - url: grpcs://node1-ord1.node1-net.vm1.fabric:443
      certificate: |-
${ORDERER1_TLS_CERT}
    - url: grpcs://node1-ord2.node1-net.vm1.fabric:443
      certificate: |-
${ORDERER2_TLS_CERT}
    - url: grpcs://node1-ord3.node1-net.vm1.fabric:443
      certificate: |-
${ORDERER3_TLS_CERT}
EOF

  echo "Aguardando o peer da organização ${org_name} entrar no canal 'demo'..."
  kubectl wait --for=condition=Running FabricFollowerChannel/demo-${msp_name} -n "${ns}" --timeout=180s
}



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


# --- Função principal do script ---
main() {
    # Validação dos argumentos de entrada
    if [ "$#" -ne 2 ]; then
        echo "Uso: $0 <node_number> <caminho_para_config.yaml>"
        echo "Exemplo: $0 2 config.yaml"
        exit 1
    fi

    # Define as variáveis globais com base nos argumentos
    NODE_NUMBER="$1"
    NODE_NAME="node${NODE_NUMBER}"

    # Chama a função para definir o DNS_SUFFIX dinamicamente
    set_dns_suffix "$2"

    echo "Iniciando processo de join da organização ${NODE_NAME}..."
    join_channel_nodeX
}

main "$@"
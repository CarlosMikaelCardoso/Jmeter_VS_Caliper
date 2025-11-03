#!/usr/bin/env bash
set -o pipefail
set -x

function configureClientDNS() {
  local DNS_SERVER_IP="$1"

  {
    echo "[Resolve]"
    echo "DNS=${DNS_SERVER_IP}"
  } | sudo tee /etc/systemd/resolved.conf > /dev/null

  sudo systemctl restart systemd-resolved.service
}

function installTools() {
  # Verifica se o yq já existe antes de baixar
  if ! command -v yq &> /dev/null
  then
      YQ_VERSION="v4.40.5"
      wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64
      chmod +x /tmp/yq
      sudo mv /tmp/yq /usr/bin/yq
  fi
}

main() {
  if [ -z "$1" ]; then
    echo "Uso: $0 <arquivo.yaml>"
    exit 1
  fi
  local config_yaml="$1"

  # 1. Instala as ferramentas, se necessário
  installTools

  # 2. Agora, com o yq garantidamente instalado, lê a configuração
  DNS_SERVER_IP=$(yq e '.vms[0].ip' "$config_yaml")

  # 3. Executa a configuração passando o IP lido
  configureClientDNS "$DNS_SERVER_IP"
}

main "$@"
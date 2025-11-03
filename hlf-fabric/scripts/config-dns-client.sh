#!/usr/bin/env bash
# set -o errexit   # abort on nonzero exitstatus
# set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode


# Verifica se o arquivo YAML foi passado como argumento
if [ -z "$1" ]; then
  echo "Uso: $0 <arquivo.yaml>"
  exit 1
fi

config_yaml="${1}"

DNS_SERVER_IP=$(yq e '.dns_ip' "$config_yaml")


function configDNS() {
  # yq travado
  YQ_VERSION="v4.40.5"
  wget -N https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O yq
  chmod +x yq
  sudo mv yq /usr/bin/yq

  {
    echo "[Resolve]"
    echo "DNS=${DNS_SERVER_IP}" 
  } | sudo tee /etc/systemd/resolved.conf > /dev/null
  
  sudo systemctl restart systemd-resolved.service
}

main() {
  configDNS
}

main "$@"

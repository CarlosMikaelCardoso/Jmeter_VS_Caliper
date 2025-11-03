#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

start_dir=$(pwd)
repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../ && pwd -P)

tmp_dir="${repository_dir}/tmp"
shared_chart_dir="${tmp_dir}/bevel/platforms/shared/charts"

# Verifica se o arquivo YAML foi passado como argumento
if [ -z "$1" ]; then
  echo "Uso: $0 <arquivo.yaml>"
  exit 1
fi

config_yaml="${start_dir}/${1}"

DNS_SERVER_IP=$(yq e '.dns_ip' "$config_yaml")

VM_IP=$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')

function configDNS() {
  {
    echo "[Resolve]"
    echo "DNS=${DNS_SERVER_IP}" 
  } | sudo tee /etc/systemd/resolved.conf > /dev/null
  
  sudo systemctl restart systemd-resolved.service
}

function installHaProxy(){
  sudo microk8s enable metallb:"${VM_IP}-${VM_IP}"
  sudo microk8s enable dns:"${DNS_SERVER_IP}"
  sudo microk8s enable hostpath-storage

  helm upgrade --install --create-namespace --namespace "ingress-controller" \
    haproxy "${shared_chart_dir}/haproxy-ingress/haproxy-ingress-0.14.6.tgz" \
    --set controller.kind=DaemonSet -f "${shared_chart_dir}/haproxy-ingress/values.yaml"
    
  sleep 20  
  kubectl annotate service haproxy-ingress -n ingress-controller --overwrite "external-dns.alpha.kubernetes.io/hostname=*.${VM_IP}."
}



function deleteAndRecreateNamespace() {
  local namespace=$1
  kubectl delete namespace "${namespace}" --ignore-not-found
  while kubectl get namespace "${namespace}"; do sleep 1; done
  kubectl create namespace "${namespace}"
}

main() { 
  configDNS
  installHaProxy
}

main "$@"

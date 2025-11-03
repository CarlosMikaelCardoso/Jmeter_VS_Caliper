#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

start_dir=$(pwd)
#script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
#config_dir="${script_dir}/configs"

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)

tmp_dir="${repository_dir}/tmp"

# Verifica se o arquivo YAML foi passado como argumento
if [ -z "$1" ]; then
  echo "Uso: $0 <arquivo.yaml>"
  exit 1
fi

config_yaml="${start_dir}/${1}"

DNS_SERVER_IP=$(yq e '.vms[0].ip' "$config_yaml")
VM_IP=$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')



if ! [[ -d "${tmp_dir}" ]]; then
  mkdir "${tmp_dir}"
fi 


function install_hlf_operator() {
  cd "${tmp_dir}"
  # Install the Hyperledger Fabric Operator
  helm repo add kfs https://kfsoftware.github.io/hlf-helm-charts --force-update
  helm install hlf-operator --version=1.11.1 -- kfs/hlf-operator
}

function install_k8s_plugin() {
  cd "${tmp_dir}"
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew

  export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  echo "export PATH=${KREW_ROOT:-$HOME/.krew}/bin:$PATH" >> "${HOME}/.bashrc"

  kubectl krew install hlf
}

function install_istio() {
  cd "${tmp_dir}"
  local DNS_SERVER="${DNS_SERVER_IP}"
  local VM_IPS="$VM_IP"

  echo "Configurando o DNS do MicroK8s para encaminhar para ${DNS_SERVER}..."
  sudo microk8s disable dns
  sleep 5 # Pequena pausa para garantir a desativação
  sudo microk8s enable dns:"${DNS_SERVER}"

  echo "Aguardando o DNS do cluster estabilizar..."
  # Adiciona uma espera explícita para o deployment do CoreDNS ficar pronto
  sudo microk8s kubectl wait --for=condition=available deployment/coredns -n kube-system --timeout=120s
  sleep 10 # Pausa extra por segurança

  echo "DNS estabilizado. Continuando com os outros addons..."
  sudo microk8s enable community
  sudo microk8s enable metallb:"${VM_IPS}-${VM_IPS}"
  sudo microk8s enable hostpath-storage
  sudo microk8s enable istio
}

function disable_dns() {
  cd "${tmp_dir}"
  sudo microk8s disable dns
}

# function config_coredns {
#   kubectl -n kube-system get configmap coredns -o yaml | sed '/errors/a \        rewrite name asset asset.default.svc.cluster.local' | sed "s|forward . /etc/resolv.conf | forward . ${DNS_SERVER_IP}|g" |  kubectl apply -f -
  
#   sleep 10
  
#   kubectl delete pod -l k8s-app=kube-dns -n kube-system

# }

main() {
  install_hlf_operator
  install_k8s_plugin
  install_istio
  # config_coredns
}

main "$@"

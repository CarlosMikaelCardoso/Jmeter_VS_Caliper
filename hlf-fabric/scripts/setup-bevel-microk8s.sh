#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"

if ! [[ -d "${tmp_dir}" ]]; then
  mkdir "${tmp_dir}"
fi

# Versões fixas
BEVEL_VERSION="${1:-v1.3.0}"
MICROK8S_VERSION="1.32"
JQ_VERSION="1.6"
YQ_VERSION="v4.40.5"
HELM_VERSION="v3.15.3"
KUBECTL_VERSION="v1.28.0"

function installRequeriments() {
  cd "${tmp_dir}"

  # MicroK8s versão específica via Snap
  sudo snap refresh microk8s --channel=${MICROK8S_VERSION}/stable || sudo snap install microk8s --classic --channel=${MICROK8S_VERSION}/stable

  # jq travado
  sudo apt-get update
  sudo apt-get install -y jq=${JQ_VERSION}-1ubuntu0.20.04.1 || {
    echo "Instalando jq manualmente..."
    wget -N https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 -O jq
    chmod +x jq
    sudo mv jq /usr/local/bin/jq
  }

  # yq travado
  wget -N https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 -O yq
  chmod +x yq
  sudo mv yq /usr/bin/yq

  # helm travado
  wget -N https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz
  tar zxvf helm-${HELM_VERSION}-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/
  sudo rm -r linux-amd64/

  # kubectl travado
  wget -N https://dl.k8s.io/release/${KUBECTL_VERSION}/kubernetes-client-linux-amd64.tar.gz
  tar zxvf kubernetes-client-linux-amd64.tar.gz
  sudo mv kubernetes/client/bin/kubectl* /usr/local/bin/
  sudo rm -r kubernetes/
}

function cloneBevelRepositories() {
  cd "${tmp_dir}"

  if ! [[ -d "bevel" ]]; then
    git clone https://github.com/hyperledger/bevel
    cd bevel
    git checkout tags/"${BEVEL_VERSION}" -b "${BEVEL_VERSION}"
  else
    cd bevel
    git fetch --tags
    git checkout tags/"${BEVEL_VERSION}" -b "${BEVEL_VERSION}" || git checkout "${BEVEL_VERSION}"
  fi

  cd "${tmp_dir}"
  if ! [[ -d "bevel-samples" ]]; then
    git clone https://github.com/hyperledger/bevel-samples
  fi
  cd bevel-samples
  git checkout
}

function configHomeMicrok8s() {
  cd "${HOME}"

  if ! [[ -d ".kube" ]]; then
    mkdir .kube
  fi

  microk8sConfig="$(sudo microk8s config)"
  echo "${microk8sConfig}" > "${HOME}/.kube/config"
  sudo chown "${USER}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
}

function startMicrok8s(){
  echo "Starting Microk8s..."
  cd "${tmp_dir}"

  sudo usermod -a -G microk8s "$USER"
  sudo microk8s stop || true
  sudo microk8s start
  sudo microk8s status
  echo "Microk8s Started"

  configHomeMicrok8s
  kubectl get all -A
}

main() {
  installRequeriments
  cloneBevelRepositories
  startMicrok8s
}

main "$@"

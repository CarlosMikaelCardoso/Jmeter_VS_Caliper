#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
config_dir="${script_dir}/configs"

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"

if ! [[ -d "${tmp_dir}" ]]; then
  mkdir "${tmp_dir}"
fi

function installRequeriments() {   
  cd "${tmp_dir}"

  sudo snap install microk8s --classic  
  sudo snap install jq
  sudo apt install unzip -y 

  wget -N https://get.helm.sh/helm-v3.15.3-linux-amd64.tar.gz 
  tar zxvf helm-v3.15.3-linux-amd64.tar.gz 
  sudo mv linux-amd64/helm /usr/local/bin/ 
  sudo rm -r linux-amd64/

  wget https://github.com/cli/cli/releases/download/v2.49.2/gh_2.49.2_linux_amd64.deb && \
    sudo dpkg -i gh_2.49.2_linux_amd64.deb && \
    rm gh_2.49.2_linux_amd64.deb

  sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq > /dev/null 2>&1 && \
    sudo chmod +x /usr/bin/yq

  wget -N https://dl.k8s.io/v1.28.0/kubernetes-client-linux-amd64.tar.gz 
  tar zxvf kubernetes-client-linux-amd64.tar.gz 
  sudo mv kubernetes/client/bin/kubectl* /usr/local/bin/
  sudo rm -r kubernetes/
}

function cloneBevelRepositories() {
  cd "${tmp_dir}"
  
  if ! [[ -d "bevel" ]]; then 
    git clone https://github.com/hyperledger/bevel 
    cd bevel 
    git checkout tags/v1.1.0 -b v1.1.0
  else
    cd bevel 
    git checkout
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
  sudo microk8s stop
  sudo microk8s start
  sudo microk8s status 
  echo "Microk8s Started"

  configHomeMicrok8s
  kubectl get all -A
}

main() { 
  installRequeriments
  startMicrok8s
  cloneBevelRepositories
}

main "$@"

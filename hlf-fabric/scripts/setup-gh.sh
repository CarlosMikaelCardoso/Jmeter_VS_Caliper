#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode



repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)

tmp_dir="${repository_dir}/tmp"
config_dir="${repository_dir}/lab-single-node-ansible/besu/configs"

if ! [[ -d "${tmp_dir}" ]]; then
  mkdir "${tmp_dir}"
fi 


if [[ "$#" == 3 ]]; then
    GH_USER="$1"
    GH_MAIL="$2"
    GH_TOKEN="$3"
else
    echo "Use: ${0} GH_USER GH_MAIL GH_TOKEN"
    exit
fi

if [ -z "$1" ]; then
  echo "Uso: $0 <token_gh>"
  exit 1
fi

function installRequeriments() {   
  cd "${tmp_dir}"
  wget https://github.com/cli/cli/releases/download/v2.49.2/gh_2.49.2_linux_amd64.deb && sudo dpkg -i gh_2.49.2_linux_amd64.deb && rm gh_2.49.2_linux_amd64.deb
  echo "$GH_TOKEN" | gh auth login --with-token
  git config user.name "$GH_USER"
  git config user.email "$GH_MAIL"

  if gh repo view "${GH_USER}/bevel" &> /dev/null; then
    echo "Repositório ${GH_USER}/bevel já existe. Deletando..."
    gh repo delete "${GH_USER}/bevel" --yes
  fi

  # Verifica se a pasta local já existe
  if [[ -d "bevel" ]]; then
    echo "Diretório bevel já existe. Deletando..."
    rm -rf bevel
  fi

  gh repo fork https://github.com/hyperledger/bevel --clone
  cd bevel

  git remote set-url origin "https://${GH_TOKEN}@github.com/${GH_USER}/bevel.git"
}

function configRepo() {  
  git config checkout.defaultRemote origin
  git checkout develop 
  git pull 
  git checkout -b local
  git push --set-upstream origin local
  mkdir build
  sed -e "s|GitUser|$GH_USER|g" \
    -e "s|GitEmail|$GH_MAIL|g" \
    -e "s|GitToken|$GH_TOKEN|g" \
    -e "s|svc.cluster.local|vm1.iliada|g" \
    "${config_dir}/network.yaml" | tee temp_network.yaml > /dev/null && mv temp_network.yaml build/network.yaml


}


main() { 
  installRequeriments
  configRepo
}

main "$@"

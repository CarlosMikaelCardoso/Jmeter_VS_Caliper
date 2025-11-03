#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

function install_docker() {
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

function enable_service_docker(){
    sudo systemctl enable --now docker
}

function grant_permisson() {
    sudo usermod -aG docker "$USER"
    # Adicionado um echo para informar o usuário sobre a necessidade de reinicializar a sessão
    echo "As permissões do Docker foram atualizadas para o usuário '$USER'."
    echo "Por favor, saia da sua sessão e faça login novamente para que as alterações entrem em vigor."
}

main() {
  install_docker
  enable_service_docker
  grant_permisson
}

main "$@"
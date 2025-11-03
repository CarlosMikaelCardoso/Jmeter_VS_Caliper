#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

function install_docker_compose() {
    local version="v2.24.6"
    local url="https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-x86_64"

    sudo curl -L "$url" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    sudo mkdir -p /usr/libexec/docker/cli-plugins
    sudo ln -sf /usr/local/bin/docker-compose /usr/libexec/docker/cli-plugins/docker-compose
}

main() {
    install_docker_compose
}

main "$@"
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"

mkdir -p "${tmp_dir}"

function installRequeriments() {
  cd "${tmp_dir}"
  sudo apt install python3-pip ansible jq npm -y
  pip3 install ansible openshift kubernetes
  sudo npm install -g n
  sudo n stable
  exec bash   
  ansible-galaxy install -r platforms/shared/configuration/requirements.yaml
  ansible-galaxy collection install community.general:==3.2.0 --force
}


main() {
  installRequeriments
}

main "$@"

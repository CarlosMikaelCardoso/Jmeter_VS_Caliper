#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode


repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../../&& pwd -P)
tmp_dir="${repository_dir}/tmp"
chart_dir="${tmp_dir}/bevel/platforms/hyperledger-besu/charts"


function installDependencies() {
  cd "${chart_dir}" 
  helm dependency update besu-genesis
  helm dependency update besu-node
}

main() { 
  installDependencies  
}

main "$@"

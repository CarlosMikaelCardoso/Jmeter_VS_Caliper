#!/usr/bin/env bash
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
shared_chart_dir="${tmp_dir}/bevel/platforms/shared/charts"
bevel_dir="${tmp_dir}/bevel"


function fix_microk8s_provisioner_bevel_sc() {
    sed -i "s|k8s.io/minikube-hostpath|microk8s.io/hostpath|g" "${shared_chart_dir}/bevel-storageclass/templates/_helpers.tpl" 
}

function fix_storage_class() {
    sed -i "s|k8s.io/minikube-hostpath|microk8s.io/hostpath|g" "${bevel_dir}/platforms/shared/configuration/roles/create/shared_helm_component/templates/storage_class.tpl"
}
main() { 
  fix_microk8s_provisioner_bevel_sc
  fix_storage_class
}

main "$@"
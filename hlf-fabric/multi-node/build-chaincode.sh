#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

CHAINCODE_NAME=asset
CHAINCODE_VERSION="1.0"
CHAINCODE_IMAGE=${CHAINCODE_NAME}:${CHAINCODE_VERSION}
FABRIC_SAMPLE_BRANCH_VERSION="v2.4.9"
start_dir=$(pwd)


# As variáveis do usuário e IP remoto foram removidas daqui para serem passadas como argumentos na função principal.
# local remote_user="ubuntu"
# local remote_ip="seu_ip_remoto"

# function get_vm_ip() {
#   local vm_name="$1"
#   # Usa yq para extrair o IP do config.yaml
#   yq e ".vms[] | select(.name == \"${vm_name}\") | .ip" /home/iliada/cenarios-bevel/lab-multi-node/fabric-hlf-6-nodes/config.yaml
# }

function clone_repository(){
  git clone --branch $FABRIC_SAMPLE_BRANCH_VERSION https://github.com/hyperledger/fabric-samples.git
  cd fabric-samples/asset-transfer-basic/chaincode-external
}

function build_image() {
  echo "Construindo a imagem Docker do chaincode..."
  # Usa o docker padrão do sistema
  sudo docker build -t "${CHAINCODE_IMAGE}" .
  
  echo "Salvando a imagem para um arquivo .tar.gz..."
  # Salva a imagem para ser transferida
  sudo docker save "${CHAINCODE_IMAGE}" | gzip > "${CHAINCODE_NAME}".tar.gz
  mv "${CHAINCODE_NAME}".tar.gz ${start_dir}/
}

main() {
  clone_repository
  sleep 10
  build_image
}

main "$@"
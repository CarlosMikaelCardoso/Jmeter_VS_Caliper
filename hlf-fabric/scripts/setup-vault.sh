#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -x

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"
build_dir="${tmp_dir}/bevel/build"

mkdir -p "${tmp_dir}"
mkdir -p "${build_dir}"

VAULT_ADDR="http://$(hostname -I | awk '{print $1}'):8200"
export VAULT_ADDR

function clearVault(){
  sudo rm -rf /etc/vault.d
  sudo rm -rf /opt/vault
  sudo rm -f $(command -v vault)
  hash -r
}

function installRequeriments() {
  cd "${tmp_dir}"

  # Verifica se já há uma instalação do vault
  if command -v vault &> /dev/null; then
    echo "Vault já instalado. Limpando instalação anterior..."
    clearVault
  fi

  wget -q https://releases.hashicorp.com/vault/1.13.1/vault_1.13.1_linux_amd64.zip
  unzip -o vault_1.13.1_linux_amd64.zip
  sudo mv -f vault /usr/local/bin/
  rm vault_1.13.1_linux_amd64.zip
  vault version
}

function configVault() {
  cat <<EOF > "${build_dir}/config.hcl"
listener "tcp" {
  address= "0.0.0.0:8200"
  tls_disable = 1
}
disable_mlock = true
api_addr = "$VAULT_ADDR"
storage "file" {
  path = "./bevel/build/data"
}
EOF

  vault server -config="${build_dir}/config.hcl" > "${tmp_dir}/vault.log" 2>&1 &
  echo "Esperando Vault subir..."
  sleep 5

  if curl --silent "$VAULT_ADDR/v1/sys/health" | grep -q '"initialized":true'; then
    echo "Vault já inicializado. Pulando inicialização."
  else
    echo "Vault ainda não inicializado. Inicializando..."
    vault operator init -key-shares=1 -key-threshold=1 | egrep "Unseal Key 1:|Initial Root Token:" > "${tmp_dir}/init-output.txt"
  fi

  cat "${tmp_dir}/init-output.txt" | grep -E "Unseal Key 1:|Initial Root Token:"

  unseal_key=$(grep "Unseal Key 1:" "${tmp_dir}/init-output.txt" | awk '{print $NF}')
  vault operator unseal "$unseal_key"
  export VAULT_TOKEN=$(grep 'Initial Root Token:' "${tmp_dir}/init-output.txt" | awk '{print $NF}')
  vault secrets enable -version=2 -path=secretsv2 kv

  sed -e "s|VaultUrl|${VAULT_ADDR}|g" \
      -e "s|VaultToken|${VAULT_TOKEN}|g" \
      "${build_dir}/network.yaml" | tee temp_network.yaml > /dev/null && mv temp_network.yaml "${build_dir}/network.yaml"
}

main() {
  installRequeriments
  configVault
}

main "$@"

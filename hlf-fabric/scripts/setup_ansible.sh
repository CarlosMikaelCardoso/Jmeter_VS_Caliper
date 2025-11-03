#!/usr/bin/env bash
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

echo "		 ____          ______ 		"
echo "		|  _ \   /\   |  ____|		"
echo "		| |_) | /  \  | |__   		"
echo "		|  _ < / /\ \ |  __|  		"
echo "		| |_) / ____ \| |     		"
echo "		|____/_/    \_\_|     		"

start_dir=$(pwd)
config_dir="${start_dir}/configs"

#SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SERVER_IP=$(ip -o route get to 8.8.8.8 | awk '{print $7}')
BEVEL_VERSION="v1.3.0"
#BEVEL_VERSION="main"
LOCAL_BRANCH="local"
GIT_USER="git_username"
GIT_EMAIL="git@email.com"
GIT_TOKEN="git_access_token"
VAULT_ADDR="http://${SERVER_IP}:8200"
#VAULT_PORT="8200"
VAULT_TOKEN="root_token"

repository_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && cd ../ && pwd -P)
tmp_dir="${repository_dir}/tmp"


function read_inputs() {
    read -p 'Por favor, insira o usuário do Git(username): ' GIT_USER
    read -p 'Por favor, insira o e-mail do Git: ' GIT_EMAIL
    read -s -p 'Por favor, insira o token do Git: ' && GIT_TOKEN="${REPLY}" && unset REPLY
    echo "${GIT_TOKEN}"
}

function config_git {
    git config --global user.name "${GIT_USER}"
    git config --global user.email "${GIT_EMAIL}"
}

function clone_bevel_repository () {
    export GH_TOKEN=${GIT_TOKEN}
    cd "${tmp_dir}" || exit

    if [[ ! -d "./bevel" ]]; then
        export
        gh repo fork https://github.com/hyperledger/bevel --clone
        echo "Fork e Checkout do repositório bevel realizado com sucesso"
    else echo "não entrou no if"
    
    fi 

    cd bevel || exit

    git checkout ${LOCAL_BRANCH} > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        git checkout ${BEVEL_VERSION} 
        git pull 
        git checkout -b ${LOCAL_BRANCH} 
        git push --set-upstream origin ${LOCAL_BRANCH} 
    fi
        echo "Branch changed to ${LOCAL_BRANCH}"
        cd ../..
    echo "Bevel code already checked out"
}

function install_vault() {
    cd "${tmp_dir}/bevel/" || exit
    VAULT_VERSION="1.13.1"
    #VAULT_PORT="8200"

    if ! [[ -d "./build" ]]; then
        rm -rf build
    fi 
    mkdir -p build

    vault --version > /dev/null 2>&1
    if [[ ! $? == 0 ]]; then
        echo "Starting Vault to download..."
        curl https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -o ./vault.zip
        unzip vault.zip
        sudo mv vault /usr/local/bin/
        rm vault.zip
    else 
        echo "Vault already installed."
    fi
}

function config_vault(){
    cd "${tmp_dir}/bevel/" || exit
    
    cat <<EOF > build/config.hcl
ui = true
storage "file" {
    path	= "./build/iliada/data"
}
listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = 1
}
disable_mlock = true
EOF
    # Start Vault server
    vault server -config=build/config.hcl &
    sleep 2
    VAULT_ADDR="http://${SERVER_IP}:8200" 
    export VAULT_ADDR
    echo "verigivando....."
    vault operator init -key-shares=1 -key-threshold=1 | egrep "Unseal Key 1:|Initial Root Token:" > ../keys.txt
    cat ../keys.txt

    # Unseal Vault
    VAULT_TOKEN="$(grep 'Initial Root Token:' ../keys.txt | awk '{print $4}')"
    export VAULT_TOKEN
    vault operator unseal
    vault secrets enable -version=2 -path=secretsv2 kv
}

function config_network_yaml(){
    cd "${config_dir}" || exit
    cp network_template.yaml network.yaml
        
    sed -i "s|git_username|$GIT_USER|g" network.yaml 
    sed -i "s|<username>|$GIT_USER|g" network.yaml 
    sed -i "s|git@email.com|$GIT_EMAIL|g" network.yaml
    sed -i "s|git_access_token|$GIT_TOKEN|g" network.yaml
    sed -i "s|vault_addr|${VAULT_ADDR}|g" network.yaml
    sed -i "s|vault_root_token|${VAULT_TOKEN}|g" network.yaml
}

function install_ansible() {
    cd "${tmp_dir}/bevel/" || exit
    sudo apt install python3-pip ansible jq npm -y
    pip3 install ansible openshift kubernetes
    sudo npm install -g n
    sudo n stable
    ansible-galaxy install -r "${tmp_dir}/bevel/platforms/shared/configuration/requirements.yaml"
    ansible-galaxy collection install community.general:==3.2.0 --force  
}



main() { 
  read_inputs
  install_git
  config_git
  clone_bevel_repository
  install_vault
  config_vault
  config_network_yaml
  install_ansible
  echo "Installation finished."
}

main "$@"
#!/usr/bin/env bash
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes
set -x           # debug mode

PEER_IMAGE=hyperledger/fabric-peer
PEER_VERSION=2.5.13

ORDERER_IMAGE=hyperledger/fabric-orderer
ORDERER_VERSION=2.5.13

CA_IMAGE=hyperledger/fabric-ca
CA_VERSION=1.5.15

SC_NAME="microk8s-hostpath"

# function install_haproxy(){
#   helm repo add haproxytech https://haproxytech.github.io/helm-charts
#   helm repo update

#   helm upgrade --install --create-namespace --namespace "ingress-controller" \
#     haproxy haproxytech/kubernetes-ingress \
#     --version 1.44.3 --set controller.kind=DaemonSet

#   sleep 10
#   kubectl annotate service haproxy-kubernetes-ingress -n ingress-controller --overwrite "external-dns.alpha.kubernetes.io/hostname=*.vm1.fabric"
  
#   sleep 20
# }

function install_node1(){
  org_name="node1"
  ns="${org_name}-net"

  kubectl get ns ${ns} || kubectl create namespace ${ns} 
  
  # Create the certification authority
  kubectl hlf ca create --namespace=${ns} --image=$CA_IMAGE --version=$CA_VERSION --storage-class=$SC_NAME --capacity=1Gi --name=node1-ca --enroll-id=enroll --enroll-pw=enrollpw --hosts=node1-ca.node1-net.vm1.fabric --istio-port=443

  sleep 30
  kubectl wait --namespace=${ns} --for=condition=ready --timeout=100s pod -l app=hlf-ca


  # test the CA  
  sleep 10
  curl -vik https://node1-ca.node1-net.vm1.fabric:443/cainfo

  # Register user orderer
  kubectl hlf ca register --namespace=${ns} --name=node1-ca --user=orderer --secret=ordererpw --type=orderer --enroll-id enroll --enroll-secret=enrollpw --mspid=node1MSP --ca-url="https://node1-ca.node1-net.vm1.fabric:443" 

  # Deploy orderers
  sleep 20
  kubectl hlf ordnode create --namespace=${ns} --image=$ORDERER_IMAGE --version=$ORDERER_VERSION \
  --storage-class=$SC_NAME --enroll-id=orderer --mspid=node1MSP \
  --enroll-pw=ordererpw --capacity=2Gi --name=node1-ord1 --ca-name=node1-ca.node1-net \
  --hosts=node1-ord1.node1-net.vm1.fabric --admin-hosts=admin-node1-ord1.node1-net.vm1.fabric --istio-port=443

  sleep 20
  
  kubectl hlf ordnode create --namespace=${ns} --image=$ORDERER_IMAGE --version=$ORDERER_VERSION \
      --storage-class=$SC_NAME --enroll-id=orderer --mspid=node1MSP \
      --enroll-pw=ordererpw --capacity=2Gi --name=node1-ord2 --ca-name=node1-ca.node1-net \
      --hosts=node1-ord2.node1-net.vm1.fabric --admin-hosts=admin-node1-ord2.node1-net.vm1.fabric --istio-port=443
  sleep 20

  kubectl hlf ordnode create --namespace=${ns} --image=$ORDERER_IMAGE --version=$ORDERER_VERSION \
      --storage-class=$SC_NAME --enroll-id=orderer --mspid=node1MSP \
      --enroll-pw=ordererpw --capacity=2Gi --name=node1-ord3 --ca-name=node1-ca.node1-net \
      --hosts=node1-ord3.node1-net.vm1.fabric --admin-hosts=admin-node1-ord3.node1-net.vm1.fabric --istio-port=443
  sleep 20
 
  
  kubectl wait --timeout=180s --for=condition=Running fabricorderernodes.hlf.kungfusoftware.es --all -n ${ns}

  # test the orderer
  openssl s_client -connect node1-ord1.node1-net.vm1.fabric:443
  sleep 5
  openssl s_client -connect node1-ord2.node1-net.vm1.fabric:443
  sleep 5
  openssl s_client -connect node1-ord3.node1-net.vm1.fabric:443

  
  kubectl get all -A
}

function deleteAll() {
  kubectl delete fabricorderernodes.hlf.kungfusoftware.es --all-namespaces --all
  kubectl delete fabriccas.hlf.kungfusoftware.es --all-namespaces --all
  kubectl delete fabricidentities.hlf.kungfusoftware.es --all-namespaces --all
  kubectl delete networkConfig --all-namespaces --all
}

main() { 
  deleteAll
  # install_haproxy
  install_node1
}

main "$@"

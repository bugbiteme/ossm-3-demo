#!/bin/bash

#export GATEWAY=$(oc get route istio-ingressgateway -n istio-system-3 -o template --template '{{ .spec.host }}')
export GATEWAY=$(oc get gateway hello-gateway -n istio-ingress -o template --template='{{(index .status.addresses 0).value}}')

curl -s $GATEWAY/hello | jq
curl -s $GATEWAY/hello-service | jq
#curl -s $GATEWAY/web/hello | jq
#curl -s $GATEWAY/web/hello-service | jq



#curl $GATEWAY/vm/hello-service #for vm-to-vm namespace
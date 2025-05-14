#!/bin/bash

NC='\033[0m'          # Text Reset
BGreen='\033[1;32m'   # Green
BYellow='\033[1;33m'  # Yellow
#BBlack='\033[1;30m'  # Black
#BRed='\033[1;31m'    # Red
BBlue='\033[1;34m'    # Blue
#BPurple='\033[1;35m' # Purple
#BCyan='\033[1;36m'   # Cyan
#BWhite='\033[1;37m'  # White

echo "${BGreen}This script set up the whole OSSM3 demo.${NC}"

echo "${BYellow}Installing Minio for Tempo${NC}"
oc new-project tracing-system
oc apply -f ./resources/TempoOtel/minio.yaml -n tracing-system
echo "${BYellow}Waiting for Minio to become available...${NC}"
oc wait --for condition=Available deployment/minio --timeout 150s -n tracing-system

echo "${BYellow}Installing TempoCR${NC}"
oc apply -f ./resources/TempoOtel/tempo.yaml -n tracing-system
echo "${BYellow}Waiting for TempoStack to become ready...${NC}"
oc wait --for condition=Ready TempoStack/sample --timeout 150s -n tracing-system
echo "${BYellow}Waiting for Tempo deployment to become available...${NC}"
oc wait --for condition=Available deployment/tempo-sample-compactor --timeout 150s -n tracing-system

echo "${BYellow}Exposing Jaeger UI route (will be used in kiali ui)${NC}"
oc expose svc tempo-sample-query-frontend --port=jaeger-ui --name=tracing-ui -n tracing-system

echo "${BYellow}Installing OpenTelemetryCollector...${NC}"
oc new-project opentelemetrycollector
oc apply -f ./resources/TempoOtel/opentelemetrycollector.yaml -n opentelemetrycollector
echo "${BYellow}Waiting for OpenTelemetryCollector deployment to become available..."
oc wait --for condition=Available deployment/otel-collector --timeout 60s -n opentelemetrycollector

echo "${BYellow}Installing OSSM3...${NC}"
oc new-project istio-system-3
echo "${BYellow}Installing IstioCR...${NC}"
oc apply -f ./resources/OSSM3/istiocr.yaml  -n istio-system-3
echo "${BYellow}Waiting for istio to become ready...${NC}"
oc wait --for condition=Ready istio/default --timeout 60s  -n istio-system-3

echo "${BYellow}Installing Telemetry resource...${NC}"
oc apply -f ./resources/TempoOtel/istioTelemetry.yaml  -n istio-system-3
echo "${BYellow}Adding OTEL namespace as a part of the mesh${NC}"
oc label namespace opentelemetrycollector istio-discovery=enabled
oc label namespace opentelemetrycollector istio-injection=enabled

echo "${BYellow}Installing IstioCNI...${NC}"
oc new-project istio-cni
oc apply -f ./resources/OSSM3/istioCni.yaml -n istio-cni
echo "${BYellow}Waiting for istiocni to become ready...${NC}"
oc wait --for condition=Ready istiocni/default --timeout 60s -n istio-cni

echo "${BYellow}Creating ingress gateway via Gateway API...${NC}"
oc new-project istio-ingress
echo "${BYellow}Adding istio-ingress namespace as a part of the mesh${NC}"
oc label namespace istio-ingress istio-discovery=enabled
oc label namespace istio-ingress istio-injection=enabled
oc apply -k ./resources/gateway

echo "${BYellow}Creating ingress gateway via Istio Deployment...${NC}"
#oc new-project istio-ingress
#echo "Adding istio-ingress namespace as a part of the mesh"
#oc label namespace istio-ingress istio-injection=enabled
oc apply -f ./resources/OSSM3/istioIngressGateway.yaml  -n istio-ingress
echo "${BYellow}Waiting for deployment/istio-ingressgateway to become available...${NC}"
oc wait --for condition=Available deployment/istio-ingressgateway --timeout 60s -n istio-ingress
echo "${BYellow}Exposing Istio ingress route${NC}"
oc expose svc istio-ingressgateway --port=http2 --name=istio-ingressgateway -n istio-ingress

echo "${BYellow}Enabling user workload monitoring in OCP${NC}"
oc apply -f ./resources/Monitoring/ocpUserMonitoring.yaml
echo "${BYellow}Enabling service monitor in istio-system-3 namespace${NC}"
oc apply -f ./resources/Monitoring/serviceMonitor.yaml -n istio-system-3
echo "${BYellow}Enabling pod monitor in istio-system-3 namespace${NC}"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-system-3
echo "${BYellow}Enabling pod monitor in istio-ingress namespace${NC}"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-ingress

echo "${BYellow}Installing Kiali...${NC}"
oc project istio-system-3
echo "${BYellow}Creating cluster role binding for kiali to read ocp monitoring${NC}"
oc apply -f ./resources/Kiali/kialiCrb.yaml -n istio-system-3
echo "${BYellow}Installing KialiCR...${NC}"
export TRACING_INGRESS_ROUTE="http://$(oc get -n tracing-system route tracing-ui -o jsonpath='{.spec.host}')"
cat ./resources/Kiali/kialiCr.yaml | JAEGERROUTE="${TRACING_INGRESS_ROUTE}" envsubst | oc -n istio-system-3 apply -f - 
echo "${BYellow}Waiting for kiali to become ready...${NC}"
oc wait --for condition=Successful kiali/kiali --timeout 150s -n istio-system-3 
oc annotate route kiali haproxy.router.openshift.io/timeout=60s -n istio-system-3 

echo "${BYellow}Install Kiali OSSM Console plugin...${NC}"
oc apply -f ./resources/Kiali/kialiOssmcCr.yaml -n istio-system-3

echo "${BYellow}Installing Sample RestAPI...${NC}"
oc apply -k ./resources/application/kustomize/overlays/pod 

echo "${BYellow}Installing Bookinfo...${NC}"
oc new-project bookinfo
echo "${BYellow}Adding bookinfo namespace as a part of the mesh${NC}"
oc label namespace bookinfo istio.io/rev=ossm-3
oc label namespace bookinfo istio-discovery=enabled
oc label namespace bookinfo istio-injection=enabled
echo "${BYellow}Enabling pod monitor in bookinfo namespac${NC}"
oc apply -f ./resources/Monitoring/podMonitor.yaml -n bookinfo
echo "${BYellow}Installing Bookinfo${NC}"
oc apply -f ./resources/Bookinfo/bookinfo.yaml -n bookinfo
oc apply -f ./resources/Bookinfo/bookinfo-gateway.yaml -n bookinfo
echo "${BYellow}Waiting for bookinfo pods to become ready...${NC}"
oc wait --for=condition=Ready pods --all -n bookinfo --timeout 60s

echo "${BYellow}Installation finished!${NC}"
echo "${BYellow}NOTE: Kiali will show metrics of bookinfo app right after pod monitor will be ready. You can check it in OCP console Observe->Metrics${NC}"

# this env will be used in traffic generator
export INGRESSHOST=$(oc get route istio-ingressgateway -n istio-ingress -o=jsonpath='{.spec.host}')
KIALI_HOST=$(oc get route kiali -n istio-system-3 -o=jsonpath='{.spec.host}')

echo "${BYellow}[optional] Installing Bookinfo traffic generator...${NC}"
cat ./resources/Bookinfo/traffic-generator-configmap.yaml | ROUTE="http://${INGRESSHOST}/productpage" envsubst | oc -n bookinfo apply -f - 
oc apply -f ./resources/Bookinfo/traffic-generator.yaml -n bookinfo

echo "${BYellow}====================================================================================================${NC}"
echo "Ingress route for bookinfo is: \033[1;34mhttp://${INGRESSHOST}/productpage\033[0m"
echo "To test RestAPI: \033[1;34msh ./scripts/test-api.sh\033[0m"
echo "Kiali route is: \033[1;34mhttps://${KIALI_HOST}\033[0m"
echo "${BYellow}====================================================================================================${NC}"

Need to mannually enable Gateway API beforehand (this won't be necessary in future release of OCP TBD)

Enable Gateway API  (only if you did not run the `./install_operators.sh` script)
------------  
```bash
oc get crd gateways.gateway.networking.k8s.io &> /dev/null ||  { oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | oc apply -f -; }
```
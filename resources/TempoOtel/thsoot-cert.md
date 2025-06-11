There is a bug when you try to connect the Kiali with Tempo:
```
 2025-06-11T12:08:52Z INF tempo version check failed: url=[https://tempo-sample-gateway.tracing-system.svc.cluster.local:8080/api/traces/v1/north/tempo], code=[0], err=[Get "https://oauth-openshift.apps.cluster-fhr9p.fhr9p.sandbox72.opentlc.com/oauth/authorize?approval_prompt=force&client_id=system%3Aserviceaccount%3Atracing-system%3Atempo-sample-gateway&redirect_uri=https%3A%2F%2Ftempo-sample-gateway-tracing-system.apps.cluster-fhr9p.fhr9p.sandbox72.opentlc.com%2Fopenshift%2Fnorth%2Fcallback%3Froute%3D%2Fapi%2Ftraces%2Fv1%2Fnorth%2Ftempo%2Fapi%2Fstatus%2Fbuildinfo&response_type=code&scope=user%3Ainfo+user%3Acheck-access+user%3Alist-projects&state=I+love+Observatorium": tls: failed to verify certificate: x509: certificate signed by unknown authority] -->
```
This blog post helps to solve the problem: 

https://medium.com/@yakovbeder/ossm-3-kiali-and-grafana-tempo-the-epic-quest-for-custom-certificates-mutual-trust-and-06004f2ab334

This Slack thread also helps:

https://redhat-internal.slack.com/archives/C019EPZ233P/p1743600212736389

In summary, it is an SSL problem, and you need to create the `trustfile.cer` file by yourself with all the public CAs between Kiali and Tempo.

```
OAUTH_OCP_URL=oauth-openshift.apps.cluster-fhr9p.fhr9p.sandbox72.opentlc.com:443

# get the Kiali default CA
oc -n istio-system exec deploy/kiali -c kiali -- cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt > service-ca.crt

# get the istio root.ca (I'm not sure if we need this one)
oc get secret istio-ca-secret -n istio-system -o jsonpath="{.data.root-cert\.pem}" | base64 -d > root-cert.crt

# get the Openshit oauht CA
openssl s_client -connect $OAUTH_OCP_URL -servername oauth-openshift.apps.cluster-fhr9p.fhr9p.sandbox72.opentlc.com </dev/null 2>/dev/null | \
  awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' > oauth-server.crt

# I'm not sure if we need the entire OCP OAuth CA chain. If so, we can get this by using the Chrome browser or with: 
openssl s_client -showcerts -connect $OAUTH_OCP_URL </dev/null

# concatenate all the crt you grab
cat *.crt > custom-ca.crt

# Create the secret with this `trustfile`
oc create secret generic cacert \
  --from-file=ca.crt=custom-ca.crt \
  -n istio-system


# Add the following snippet to the Kiali CR
spec:
  deployment:
    ...
    custom_secrets:
      - name: cacert
        mount: "/kiali-trace-cert"
        optional: false
    ...
  external_services: 
    ...
    auth:
        ca_file: "/kiali-trace-cert/ca.crt"
        type: bearer
        use_kiali_token: true
        insecure_skip_verify: false
```


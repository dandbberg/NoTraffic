#!/bin/bash
set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${YELLOW}→ Checking NGINX NodePort exists...${NC}"

NODEPORT=$(kubectl get svc nginx-proxy -o=jsonpath='{.spec.ports[0].nodePort}')

if [[ -z "$NODEPORT" ]]; then
  echo -e "${RED}✗ NodePort not found for nginx-proxy${NC}"
  exit 1
fi

echo -e "${GREEN}✓ NodePort detected: $NODEPORT${NC}"

# Test external NodePort access (works with VirtualBox, may not work with Docker on macOS)
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "")

if [[ -n "$MINIKUBE_IP" ]]; then
  echo -e "${YELLOW}→ Testing external NodePort access (via minikube IP: ${MINIKUBE_IP})...${NC}"
  
  if curl -k --silent --fail --max-time 5 "https://${MINIKUBE_IP}:${NODEPORT}/" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ NodePort accessible externally via ${MINIKUBE_IP}:${NODEPORT}${NC}"
    
    # Test Keycloak endpoint through external NodePort
    if curl -k --silent --fail --max-time 5 \
      "https://${MINIKUBE_IP}:${NODEPORT}/realms/master/.well-known/openid-configuration" \
      >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Keycloak reachable through external NodePort${NC}"
    else
      echo -e "${YELLOW}⚠ Keycloak endpoint test via external NodePort failed (may need more time to start)${NC}"
    fi
  else
    echo -e "${YELLOW}⚠ External NodePort test failed (expected with Docker driver on macOS)${NC}"
    echo -e "${YELLOW}  NodePort is still accessible from within cluster and via 'minikube service'${NC}"
  fi
else
  echo -e "${YELLOW}→ Skipping external NodePort test (minikube IP not available)${NC}"
fi

echo -e "${YELLOW}→ Running in-cluster validation using curl pod...${NC}"

kubectl run curltester --rm -i --restart=Never \
  --image=curlimages/curl:latest \
  --command -- sh -c "
    echo 'Testing NGINX reverse proxy root endpoint...';
    curl -k --silent --fail https://nginx-proxy.default.svc.cluster.local/ || exit 1;

    echo 'Testing Keycloak OIDC metadata through proxy...';
    curl -k --silent --fail \
      https://nginx-proxy.default.svc.cluster.local/realms/master/.well-known/openid-configuration \
      >/dev/null || exit 1;
  " || {
    echo -e "${RED}✗ In-cluster validation failed${NC}"
    exit 1
  }

echo -e "${GREEN}✓ NGINX reverse proxy reachable INSIDE cluster${NC}"
echo -e "${GREEN}✓ Keycloak OIDC metadata reachable THROUGH NGINX${NC}"

echo -e "${YELLOW}→ Verifying Keycloak is NOT externally exposed...${NC}"
KC_TYPE=$(kubectl get svc keycloak -o=jsonpath='{.spec.type}')

if [[ "$KC_TYPE" != "ClusterIP" ]]; then
  echo -e "${RED}✗ Keycloak is exposed externally (expected ClusterIP only)!${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Keycloak is internal-only (ClusterIP)${NC}"

echo -e "${GREEN}===================================================="
echo -e "     🎉 Smoke Test Passed Successfully!"
echo -e "====================================================${NC}"


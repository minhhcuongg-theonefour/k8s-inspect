include env/registry.env

cluster-list:
	k3d cluster list

cluster-create:
	k3d cluster create local-dev

cluster-delete:
	k3d cluster delete local-dev

kubeflow-create:
	while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do echo "Retrying to apply resources"; sleep 20; done

# argo cd management
argocd-web:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

argocd-pw:
	kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d; echo

argocd-login:
	@argocd login localhost:8080 \
	  --username admin \
	  --password "$$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)" \
	  --insecure

kubeflow-login:
	@kubectl port-forward svc/istio-ingressgateway -n istio-system 8081:80 & \


# check harbor registry
login-registry:
	@docker login $(registry_url) -u $(registry_user) -p $(registry_password)

list-repos-harbor:
	@harbor project repos $(registry_name)

.PHONY: cluster-list cluster-create cluster-deleteg6DybbxZlRIicyGv
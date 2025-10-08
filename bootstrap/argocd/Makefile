plan-argocd:
	kubectl kustomize --enable-helm ./installation

create-argocd:
	kubectl kustomize --enable-helm ./installation | kubectl apply -f -

.PHONY: plan-argocd create-argocd
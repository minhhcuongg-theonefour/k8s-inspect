plan-argocd:
	kubectl kustomize --enable-helm ./argocd

create-argocd:
	kubectl kustomize --enable-helm ./argocd | kubectl apply -f -

apply-argocd:
	kubectl apply -f argocd-bootstrap.yaml


.PHONY: plan-argocd create-argocd apply-argocd
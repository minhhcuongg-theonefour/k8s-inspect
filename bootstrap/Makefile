plan-argocd:
	kubectl kustomize --enable-helm ./argocd

create-argocd-resources:
	kubectl kustomize --enable-helm ./argocd | kubectl apply -f -

apply-argocd:
	kubectl apply -f argocd-application.yaml

apply-argocd-bootstrap:
	kubectl apply -f argocd-bootstrap.yaml


.PHONY: plan-argocd create-argocd apply-argocd
# sentinelflow/Makefile

IMAGE_NAME=sentinelflow
REGISTRY=localhost:5001
TAG=$(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
COMPOSE=docker compose
ENV=staging

.PHONY: help dev down logs test lint build push scan health deploy-stg rollback incident kind-up kind-deploy clean

help: ## Show this help message
	@echo "SentinelFlow Automation Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

dev: ## Start local development environment
	$(COMPOSE) up -d --build

down: ## Stop all local services
	$(COMPOSE) down

logs: ## Tail application logs
	$(COMPOSE) logs -f app

test: ## Run unit tests with coverage
	$(COMPOSE) run --rm app pytest app/tests/ -v --cov=app

lint: ## Run Python linting
	flake8 app/ --max-line-length=120 || echo "Linting failed"

build: ## Build production Docker image
	docker build --build-arg APP_VERSION=$(TAG) -t $(REGISTRY)/$(IMAGE_NAME):$(TAG) app/

push: ## Push image to local registry
	docker push $(REGISTRY)/$(IMAGE_NAME):$(TAG)

scan: ## Scan image for vulnerabilities
	trivy image $(REGISTRY)/$(IMAGE_NAME):$(TAG)

health: ## Run host system health check
	bash scripts/system_health_check.sh

deploy-stg: ## Deploy to staging environment
	bash scripts/deploy.sh staging $(TAG)

rollback: ## Rollback last deployment
	bash scripts/rollback.sh $(ENV)

incident: ## Generate incident report
	bash scripts/incident_report.sh

kind-up: ## Spin up Kind Kubernetes cluster
	kind create cluster --name $(IMAGE_NAME) || echo "Cluster already exists"

kind-deploy: ## Deploy manifests to Kind
	kubectl apply -f k8s/

clean: ## Deep clean: remove all containers, volumes, and local registry data
	$(COMPOSE) down -v --rmi local
	docker system prune -f
.DEFAULT_GOAL := help

COMPOSE ?= docker compose
BACKEND_DIR ?= backend
FRONTEND_DIR ?= frontend

.PHONY: help init env check-env up down restart logs ps health deploy migrate \
	backend-test frontend-test submodule-status clean

help: ## Show available commands
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target>\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize and update frontend/backend submodules recursively
	git submodule update --init $(BACKEND_DIR) $(FRONTEND_DIR)
	git -C $(BACKEND_DIR) config url.https://github.com/.insteadOf git@github.com:
	git -C $(BACKEND_DIR) submodule update --init --recursive
	git -C $(FRONTEND_DIR) submodule update --init --recursive

env: ## Create .env from .env.example if missing
	@if [ -f .env ]; then \
		echo ".env already exists"; \
	else \
		cp .env.example .env; \
		echo "Created .env from .env.example"; \
		echo "Edit JWT_SECRET, ADMIN_JWT_SECRET, and MEDAGENT_API_KEY before deployment."; \
	fi

check-env: ## Validate required deployment environment variables
	@test -f .env || { echo "Missing .env. Run: make env"; exit 1; }
	@awk -F= ' \
		/^JWT_SECRET=/ { jwt=1; if ($$2 ~ /^change-this-/ || length($$2) < 32) bad=1 } \
		/^ADMIN_JWT_SECRET=/ { admin=1; if ($$2 ~ /^change-this-/ || length($$2) < 32) bad=1 } \
		/^MEDAGENT_API_KEY=/ { med=1; if ($$2 == "" || $$2 == "sk-replace-me") bad=1 } \
		END { \
			if (!jwt || !admin || !med || bad) { \
				print "Update JWT_SECRET, ADMIN_JWT_SECRET, and MEDAGENT_API_KEY in .env before deployment."; \
				exit 1; \
			} \
		} \
	' .env

up: init check-env ## Build and start all services
	$(COMPOSE) --env-file .env up -d --build

down: ## Stop all services
	$(COMPOSE) --env-file .env down

restart: down up ## Restart all services

logs: ## Follow service logs
	$(COMPOSE) --env-file .env logs -f

ps: ## Show compose service status
	$(COMPOSE) --env-file .env ps

health: ## Check frontend and backend health endpoints
	@FRONTEND_PORT=$$(awk -F= '/^FRONTEND_PORT=/ {print $$2}' .env 2>/dev/null || true); \
	BACKEND_PORT=$$(awk -F= '/^BACKEND_PORT=/ {print $$2}' .env 2>/dev/null || true); \
	FRONTEND_PORT=$${FRONTEND_PORT:-5173}; \
	BACKEND_PORT=$${BACKEND_PORT:-8080}; \
	curl -fsS "http://localhost:$${BACKEND_PORT}/api/health" >/dev/null; \
	curl -fsS "http://localhost:$${FRONTEND_PORT}/" >/dev/null; \
	echo "OK: frontend http://localhost:$${FRONTEND_PORT}, backend http://localhost:$${BACKEND_PORT}/api/health"

deploy: up health ## Full deployment flow: init, validate env, start, and health-check

migrate: check-env ## Run backend migrations by starting/restarting backend
	$(COMPOSE) --env-file .env up -d mysql medagent backend
	@echo "Backend applies db/migrations automatically during startup."

backend-test: init ## Run backend tests
	cd $(BACKEND_DIR) && go test ./...

frontend-test: init ## Install frontend deps and run frontend tests
	cd $(FRONTEND_DIR) && corepack enable && corepack prepare pnpm@10.24.0 --activate && pnpm install --frozen-lockfile && pnpm test

submodule-status: ## Show recursive submodule status
	git submodule status --recursive

clean: ## Remove compose services and volumes
	$(COMPOSE) --env-file .env down -v

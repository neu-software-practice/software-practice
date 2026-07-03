.DEFAULT_GOAL := help
SHELL := /bin/bash

COMPOSE ?= docker compose
BACKEND_DIR ?= backend
FRONTEND_DIR ?= frontend
ENV_FILE ?= .env

.PHONY: help init env require-env check-env config doctor env-print up down restart \
	logs ps health verify-env verify-e2e deploy migrate backend-test frontend-test \
	submodule-status clean

help: ## 查看命令列表，按新手部署顺序阅读
	@awk 'BEGIN {FS = ":.*##"; printf "\nNEUHIS 一键部署命令:\n  make <target>\n\n"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## 1. 初始化/更新 backend、frontend、backend/medAgent 子模块
	git submodule update --init $(BACKEND_DIR) $(FRONTEND_DIR)
	git -C $(BACKEND_DIR) config url.https://github.com/.insteadOf git@github.com:
	git -C $(BACKEND_DIR) submodule update --init --recursive
	git -C $(FRONTEND_DIR) submodule update --init --recursive

env: ## 2. 从 .env.example 创建 .env；已存在则不覆盖
	@if [ -f $(ENV_FILE) ]; then \
		echo "$(ENV_FILE) already exists; keep your local values."; \
	else \
		cp .env.example $(ENV_FILE); \
		echo "Created $(ENV_FILE) from .env.example"; \
		echo "Next: edit JWT_SECRET, ADMIN_JWT_SECRET, and MEDAGENT_API_KEY."; \
	fi

require-env: ## 检查 .env 是否存在
	@test -f $(ENV_FILE) || { echo "Missing $(ENV_FILE). Run: make env"; exit 1; }

check-env: require-env ## 3. 检查必填密钥是否仍是占位值
	@awk -F= ' \
		function fail(msg) { print "ERROR: " msg; bad=1 } \
		/^JWT_SECRET=/ { jwt=1; if ($$2 ~ /^change-this-/ || length($$2) < 32) fail("JWT_SECRET must be changed and at least 32 bytes") } \
		/^ADMIN_JWT_SECRET=/ { admin=1; if ($$2 ~ /^change-this-/ || length($$2) < 32) fail("ADMIN_JWT_SECRET must be changed and at least 32 bytes") } \
		/^MEDAGENT_API_KEY=/ { med=1; if ($$2 == "" || $$2 == "sk-replace-me") fail("MEDAGENT_API_KEY must be changed from the placeholder") } \
		END { \
			if (!jwt) fail("JWT_SECRET is missing"); \
			if (!admin) fail("ADMIN_JWT_SECRET is missing"); \
			if (!med) fail("MEDAGENT_API_KEY is missing"); \
			if (bad) exit 1; \
			print "OK: required secrets in $(ENV_FILE) are set."; \
		} \
	' $(ENV_FILE)

config: require-env ## 4. 展开 Docker Compose 最终配置，确认 .env 已被读取
	$(COMPOSE) --env-file $(ENV_FILE) config

doctor: check-env ## 5. 部署前体检：密钥检查 + Compose 配置可展开
	@$(COMPOSE) --env-file $(ENV_FILE) config >/dev/null
	@echo "OK: Docker Compose config can be rendered from $(ENV_FILE)."
	@echo "Next: make up, or run the full check with make verify-e2e."

env-print: require-env ## 打印宿主机访问地址和容器内部固定地址
	@set -euo pipefail; \
	env_get() { awk -v key="$$1" 'BEGIN {FS="="} $$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' $(ENV_FILE); }; \
	frontend_port=$$(env_get FRONTEND_PORT); \
	backend_port=$$(env_get BACKEND_PORT); \
	mysql_port=$$(env_get MYSQL_PORT); \
	medagent_port=$$(env_get MEDAGENT_PORT); \
	printf "\nHost access:\n"; \
	printf "  frontend: http://localhost:%s\n" "$$frontend_port"; \
	printf "  backend:  http://localhost:%s/api/health\n" "$$backend_port"; \
	printf "  mysql:    localhost:%s\n" "$$mysql_port"; \
	printf "  medAgent: http://localhost:%s\n" "$$medagent_port"; \
	printf "\nContainer network:\n"; \
	printf "  frontend nginx: :80\n"; \
	printf "  backend API:    backend:8080\n"; \
	printf "  mysql:          mysql:3306\n"; \
	printf "  medAgent:       medagent:8080\n\n"

up: init check-env ## 构建并启动所有容器；VITE_* 改动必须跑此命令重建前端
	$(COMPOSE) --env-file $(ENV_FILE) up -d --build

down: ## 停止所有容器，保留 MySQL volume
	$(COMPOSE) --env-file $(ENV_FILE) down

restart: down up ## 重启整套服务；适合端口、后端、medAgent 配置变更

logs: ## 跟随查看所有容器日志
	$(COMPOSE) --env-file $(ENV_FILE) logs -f

ps: ## 查看容器运行状态
	$(COMPOSE) --env-file $(ENV_FILE) ps

health: require-env ## 检查宿主机端口映射：后端 /api/health + 前端首页
	@set -euo pipefail; \
	env_get() { awk -v key="$$1" 'BEGIN {FS="="} $$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' $(ENV_FILE); }; \
	frontend_port=$$(env_get FRONTEND_PORT); \
	backend_port=$$(env_get BACKEND_PORT); \
	backend_body=""; \
	for attempt in $$(seq 1 30); do \
		if backend_body=$$(curl -fsS "http://localhost:$${backend_port}/api/health" 2>/dev/null); then \
			break; \
		fi; \
		sleep 2; \
	done; \
	test "$$backend_body" = '{"status":"ok"}'; \
	for attempt in $$(seq 1 30); do \
		if curl -fsS "http://localhost:$${frontend_port}/" >/dev/null 2>&1; then \
			frontend_ok=1; \
			break; \
		fi; \
		sleep 2; \
	done; \
	test "$${frontend_ok:-0}" = "1"; \
	echo "OK: backend http://localhost:$${backend_port}/api/health returned $${backend_body}"; \
	echo "OK: frontend http://localhost:$${frontend_port}/ returned HTML."

verify-env: require-env ## 实际进入容器，逐项验证 .env 配置是否生效
	@set -euo pipefail; \
	env_get() { awk -v key="$$1" 'BEGIN {FS="="} $$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' $(ENV_FILE); }; \
	mask() { case "$$1" in *SECRET*|*KEY*|*PASSWORD*) printf "<set:%s chars>" "$${#2}" ;; *) printf "%s" "$$2" ;; esac; }; \
	container_get() { \
		local service="$$1"; local key="$$2"; \
		$(COMPOSE) --env-file $(ENV_FILE) exec -T "$$service" env | awk -v key="$$key" 'BEGIN {FS="="} $$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' | tr -d '\r'; \
	}; \
	check_container_value() { \
		local service="$$1"; local key="$$2"; local expected="$$3"; local actual; \
		actual="$$(container_get "$$service" "$$key")"; \
		if [ "$$actual" != "$$expected" ]; then \
			echo "ERROR: $$service $$key mismatch; expected $$(mask "$$key" "$$expected"), got $$(mask "$$key" "$$actual")"; \
			exit 1; \
		fi; \
		echo "OK: $$service $$key=$$(mask "$$key" "$$actual")"; \
	}; \
	check_config_value() { \
		local key="$$1"; local expected="$$2"; local actual; \
		actual="$$( $(COMPOSE) --env-file $(ENV_FILE) config | awk -v key="$$key" '$$1 == key ":" {sub(/^[^:]+:[[:space:]]*/, ""); print; found=1; exit} END {if (!found) exit 1}' | tr -d '\r' )"; \
		actual="$${actual%\"}"; \
		actual="$${actual#\"}"; \
		if [ "$$actual" != "$$expected" ]; then \
			echo "ERROR: compose build arg $$key mismatch; expected $$expected, got $$actual"; \
			exit 1; \
		fi; \
		echo "OK: compose build arg $$key=$$actual"; \
	}; \
	check_config_contains() { \
		local label="$$1"; local needle="$$2"; \
		if ! $(COMPOSE) --env-file $(ENV_FILE) config | grep -F "$$needle" >/dev/null; then \
			echo "ERROR: compose config missing $$label: $$needle"; \
			exit 1; \
		fi; \
		echo "OK: compose config $$label"; \
	}; \
	mysql_password=$$(env_get MYSQL_ROOT_PASSWORD); \
	mysql_database=$$(env_get MYSQL_DATABASE); \
	backend_dsn="root:$${mysql_password}@tcp(mysql:3306)/$${mysql_database}?charset=utf8mb4&parseTime=True&loc=Local"; \
	check_config_contains COMPOSE_PROJECT_NAME "name: $$(env_get COMPOSE_PROJECT_NAME)"; \
	check_config_contains FRONTEND_PORT "published: \"$$(env_get FRONTEND_PORT)\""; \
	check_config_contains BACKEND_PORT "published: \"$$(env_get BACKEND_PORT)\""; \
	check_config_contains MYSQL_PORT "published: \"$$(env_get MYSQL_PORT)\""; \
	check_config_contains MEDAGENT_PORT "published: \"$$(env_get MEDAGENT_PORT)\""; \
	check_config_value GOPROXY "$$(env_get GOPROXY)"; \
	check_container_value backend SERVER_ADDR "$$(env_get SERVER_ADDR)"; \
	check_container_value backend SERVER_MODE "$$(env_get SERVER_MODE)"; \
	check_container_value backend DATABASE_DSN "$$backend_dsn"; \
	check_container_value backend JWT_SECRET "$$(env_get JWT_SECRET)"; \
	check_container_value backend ADMIN_JWT_SECRET "$$(env_get ADMIN_JWT_SECRET)"; \
	check_container_value backend CORS_ALLOWED_ORIGINS "$$(env_get CORS_ALLOWED_ORIGINS)"; \
	check_container_value backend LOG_LEVEL "$$(env_get LOG_LEVEL)"; \
	check_container_value backend RATE_LIMIT_RPS "$$(env_get RATE_LIMIT_RPS)"; \
	check_container_value backend RATE_LIMIT_BURST "$$(env_get RATE_LIMIT_BURST)"; \
	check_container_value backend MEDAGENT_MODE "$$(env_get MEDAGENT_MODE)"; \
	check_container_value backend MEDAGENT_BASE_URL "$$(env_get MEDAGENT_BASE_URL)"; \
	check_container_value backend MEDAGENT_API_KEY "$$(env_get MEDAGENT_API_KEY)"; \
	check_container_value backend MEDAGENT_PROVIDER "$$(env_get MEDAGENT_PROVIDER)"; \
	check_container_value backend MEDAGENT_MODEL "$$(env_get MEDAGENT_MODEL)"; \
	check_container_value mysql MYSQL_ROOT_PASSWORD "$$mysql_password"; \
	check_container_value mysql MYSQL_DATABASE "$$mysql_database"; \
	check_container_value medagent MEDAGENT_PROVIDER "$$(env_get MEDAGENT_PROVIDER)"; \
	check_container_value medagent MEDAGENT_MODEL "$$(env_get MEDAGENT_MODEL)"; \
	check_container_value medagent GOPROXY "$$(env_get GOPROXY)"; \
	check_container_value medagent DEEPSEEK_API_KEY "$$(env_get MEDAGENT_API_KEY)"; \
	check_container_value medagent DASHSCOPE_API_KEY "$$(env_get MEDAGENT_API_KEY)"; \
	check_container_value medagent OPENAI_API_KEY "$$(env_get MEDAGENT_API_KEY)"; \
	check_config_value VITE_API_MODE "$$(env_get VITE_API_MODE)"; \
	check_config_value VITE_API_BASE_URL "$$(env_get VITE_API_BASE_URL)"; \
	check_config_value VITE_MOCK_DELAY_MS "$$(env_get VITE_MOCK_DELAY_MS)"; \
	check_config_value VITE_TIMELINE_POLL_INTERVAL_MS "$$(env_get VITE_TIMELINE_POLL_INTERVAL_MS)"; \
	check_config_value VITE_CREATE_VISIT_TIMEOUT_MS "$$(env_get VITE_CREATE_VISIT_TIMEOUT_MS)"; \
	echo "OK: all runtime env vars and frontend build args match $(ENV_FILE)."

verify-e2e: doctor up ps health verify-env ## 完整端到端验证：配置、启动、健康检查、容器内变量

deploy: verify-e2e ## 推荐入口：一键初始化、构建、启动并完成端到端验证

migrate: check-env ## 启动 MySQL、medAgent、backend；后端启动时自动迁移
	$(COMPOSE) --env-file $(ENV_FILE) up -d mysql medagent backend
	@echo "Backend applies db/migrations automatically during startup."

backend-test: init ## 进入 backend 执行 go test ./...
	cd $(BACKEND_DIR) && go test ./...

frontend-test: init ## 进入 frontend 安装依赖并执行 pnpm test
	cd $(FRONTEND_DIR) && corepack enable && corepack prepare pnpm@10.24.0 --activate && pnpm install --frozen-lockfile && pnpm test

submodule-status: ## 查看递归子模块状态
	git submodule status --recursive

clean: ## 停止容器并删除 MySQL volume；MySQL 密码/库名变更后常用
	$(COMPOSE) --env-file $(ENV_FILE) down -v

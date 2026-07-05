# NEUHIS 前后端整合仓库

本仓库是 NEUHIS Agent 的统一部署入口。业务源码仍在子模块中维护：

- `backend/`: 后端服务，容器内监听 `:8080`
- `frontend/`: 患者端/管理端前端，构建后由 Nginx 在容器内监听 `:80`
- `backend/medAgent/`: AI 诊疗引擎，容器内监听 `:8080`
- `mysql`: MySQL 8.4，容器内监听 `:3306`

根目录只负责四件事：`.env.example`、`Makefile`、`compose.yaml`、Docker/Nginx 部署配置。真实密钥只写入本地 `.env`，不要提交。

## 1. 准备工具

本机需要安装：

- Git
- Docker 和 Docker Compose
- Make
- 能访问 GitHub 和容器镜像仓库

检查 Docker Compose：

```bash
docker compose version
```

预期结果：输出 Docker Compose 版本号。

## 2. 初始化仓库

```bash
make init
```

预期结果：

- `backend/` 和 `frontend/` 子模块被拉取。
- `backend/medAgent/` 递归初始化完成。
- 如果 medAgent 子模块声明了 SSH 地址，Makefile 会把 `git@github.com:` 本地替换为 `https://github.com/`，便于无 SSH key 的环境拉取。

查看子模块状态：

```bash
make submodule-status
```

预期结果：能看到 `backend`、`frontend`、`backend/medAgent` 的提交指针。

## 3. 创建并填写 `.env`

```bash
make env
```

预期结果：

- 如果 `.env` 不存在，会从 `.env.example` 复制一份。
- 如果 `.env` 已存在，不会覆盖本地配置。

打开 `.env`，至少修改这三项：

```env
JWT_SECRET=local-jwt-secret-at-least-32-bytes
ADMIN_JWT_SECRET=local-admin-secret-at-least-32-bytes
MEDAGENT_API_KEY=sk-local-test-key
```

说明：

- `JWT_SECRET` 和 `ADMIN_JWT_SECRET` 必须不少于 32 字节，且不能继续使用占位值。
- `MEDAGENT_API_KEY` 不能是 `sk-replace-me`。端到端配置验证不调用真实 LLM，测试启动时可以先填一个非空测试值；真实问诊必须换成真实 provider key。

## 4. 部署前体检

```bash
make doctor
```

预期结果：

```text
OK: required secrets in .env are set.
OK: Docker Compose config can be rendered from .env.
Next: make up, or run the full check with make verify-e2e.
```

如果失败：

- 提示 `Missing .env`：先执行 `make env`。
- 提示 `JWT_SECRET`、`ADMIN_JWT_SECRET`、`MEDAGENT_API_KEY`：编辑 `.env`，替换占位值。
- Compose 展开失败：执行 `make config` 查看具体 YAML 错误。

查看 `.env` 展开后的完整 Compose 配置：

```bash
make config
```

预期结果：输出最终 Compose YAML，其中能看到端口映射、backend 环境变量、mysql 环境变量、medagent 环境变量和 frontend build args。

## 5. 一键端到端验证

推荐直接运行：

```bash
make verify-e2e
```

它会依次执行：

1. `make doctor`
2. `make up`
3. `make ps`
4. `make health`
5. `make verify-env`

预期结果：

- 所有镜像构建成功。
- `docker compose ps` 中 `frontend`、`backend`、`mysql`、`medagent` 都处于运行状态。
- 后端健康检查返回 `{"status":"ok"}`。
- 前端首页可以通过宿主机端口访问。
- `make verify-env` 每一项都输出 `OK:`。

部署主入口也是同一套验证：

```bash
make deploy
```

## 6. 默认访问地址

```bash
make env-print
```

默认输出应对应：

- 前端：`http://localhost:5173`
- 后端健康检查：`http://localhost:8080/api/health`
- MySQL：`localhost:3306`
- medAgent：`http://localhost:8083`

容器内部固定地址：

- frontend Nginx：`:80`
- backend API：`backend:8080`
- MySQL：`mysql:3306`
- medAgent：`medagent:8080`

注意：容器之间不要使用 `localhost` 互相访问。`localhost` 在容器内只代表容器自己。

## 7. `.env` 如何传到容器

| `.env` 变量 | 进入位置 | 验证方式 | 说明 |
| --- | --- | --- | --- |
| `FRONTEND_PORT` | Compose 端口映射 | `make health` / `make env-print` | 宿主机访问前端的端口，容器内仍是 `80` |
| `BACKEND_PORT` | Compose 端口映射 | `make health` / `make env-print` | 宿主机访问后端的端口，容器内仍是 `8080` |
| `MYSQL_PORT` | Compose 端口映射 | `make env-print` | 宿主机访问 MySQL 的端口，容器内仍是 `3306` |
| `MEDAGENT_PORT` | Compose 端口映射 | `make env-print` | 宿主机访问 medAgent 的端口，容器内仍是 `8080` |
| `COMPOSE_PROJECT_NAME` | Compose 项目名 | `make config` | 影响容器、网络、volume 名称前缀 |
| `GOPROXY` | backend build arg、medagent env | `make config` / `make verify-env` | Go 依赖下载代理 |
| `SERVER_ADDR` | backend env | `make verify-env` | 后端容器内监听地址，默认 `:8080` |
| `SERVER_MODE` | backend env | `make verify-env` | 后端运行模式 |
| `JWT_SECRET` | backend env | `make verify-env` | 患者端 JWT 密钥 |
| `ADMIN_JWT_SECRET` | backend env | `make verify-env` | 管理端 JWT 密钥 |
| `CORS_ALLOWED_ORIGINS` | backend env | `make verify-env` | 允许跨域来源 |
| `LOG_LEVEL` | backend env | `make verify-env` | 后端日志级别 |
| `RATE_LIMIT_ENABLED` | backend env | `make verify-env` | 是否启用后端认证接口限流；`stress-test` 分支默认 `false` |
| `RATE_LIMIT_RPS` | backend env | `make verify-env` | 限流每秒请求数 |
| `RATE_LIMIT_BURST` | backend env | `make verify-env` | 限流突发容量 |
| `MYSQL_ROOT_PASSWORD` | mysql env、backend `DATABASE_DSN` | `make verify-env` | 改动后如果旧 volume 已存在，需 `make clean` |
| `MYSQL_DATABASE` | mysql env、backend `DATABASE_DSN` | `make verify-env` | backend 连接的数据库名 |
| `MEDAGENT_MODE` | backend env | `make verify-env` | 后端调用 medAgent 的模式 |
| `MEDAGENT_BASE_URL` | backend env | `make verify-env` | backend 访问 medAgent 容器的地址，集成部署保持 `http://medagent:8080` |
| `MEDAGENT_API_KEY` | backend env、medagent provider key env | `make verify-env` | 同步为 `DEEPSEEK_API_KEY`、`DASHSCOPE_API_KEY`、`OPENAI_API_KEY` |
| `MEDAGENT_PROVIDER` | backend env、medagent env/command | `make verify-env` | `deepseek`、`qwen` 或 `openai` |
| `MEDAGENT_MODEL` | backend env、medagent env/command | `make verify-env` | 当前模型名 |
| `MEDAGENT_LLM_BASE_URL` | medagent env/command | `make verify-env` | medAgent 调用 OpenAI 兼容大模型网关的地址，填到 `/chat/completions` 之前，通常以 `/v1` 结尾 |
| `VITE_API_MODE` | frontend build arg | `make config` / `make verify-env` | 前端构建期变量，改动后必须重建 |
| `VITE_API_BASE_URL` | frontend build arg | `make config` / `make verify-env` | 默认 `/api`，由 Nginx 代理到 backend |
| `VITE_MOCK_DELAY_MS` | frontend build arg | `make config` / `make verify-env` | Mock 延迟 |
| `VITE_TIMELINE_POLL_INTERVAL_MS` | frontend build arg | `make config` / `make verify-env` | 时间线轮询间隔 |
| `VITE_CREATE_VISIT_TIMEOUT_MS` | frontend build arg | `make config` / `make verify-env` | 创建问诊超时时间 |

backend 容器内的 `DATABASE_DSN` 不再要求用户在父仓库 `.env` 中手写。Compose 会根据 `MYSQL_ROOT_PASSWORD` 和 `MYSQL_DATABASE` 生成 `root:<password>@tcp(mysql:3306)/<database>?charset=utf8mb4&parseTime=True&loc=Local`，`make verify-env` 会进入 backend 容器检查最终值。

不要把 `MEDAGENT_BASE_URL` 改成大模型网关地址。它是 backend 访问 medAgent 容器的内部地址。OpenAI 兼容大模型网关应写入 `MEDAGENT_LLM_BASE_URL`，例如 `https://example.com/v1`。

重要：`VITE_*` 是前端构建期变量，不会保留在最终 Nginx 运行容器的环境变量里。因此 `make verify-env` 通过 Compose build args 验证它们。

## 8. 手动检查命令

检查容器状态：

```bash
make ps
```

预期结果：四个服务都在运行。

检查后端和前端：

```bash
make health
```

预期结果：

```text
OK: backend http://localhost:8080/api/health returned {"status":"ok"}
OK: frontend http://localhost:5173/ returned HTML.
```

逐项检查容器内变量：

```bash
make verify-env
```

预期结果示例：

```text
OK: backend SERVER_ADDR=:8080
OK: backend DATABASE_DSN=root:<password>@tcp(mysql:3306)/neuhis?charset=utf8mb4&parseTime=True&loc=Local
OK: mysql MYSQL_DATABASE=neuhis
OK: medagent MEDAGENT_PROVIDER=deepseek
OK: compose config FRONTEND_PORT
OK: compose build arg VITE_API_BASE_URL=/api
OK: all runtime env vars and frontend build args match .env.
```

密钥类变量会被脱敏显示为 `<set:N chars>`。

验证真实大模型推理：

```bash
make medagent-smoke
```

预期结果：输出 `provider=<当前 provider> model=<当前模型>`，并打印一段结构化 JSON 结果。该命令会真实调用 `MEDAGENT_API_KEY` 和 `MEDAGENT_LLM_BASE_URL` 指向的模型服务。

查看日志：

```bash
make logs
```

停止服务但保留数据库：

```bash
make down
```

停止服务并删除 MySQL volume：

```bash
make clean
```

## 9. 修改 `.env` 后如何生效

| 修改内容 | 推荐命令 | 原因 |
| --- | --- | --- |
| `FRONTEND_PORT`、`BACKEND_PORT`、`MYSQL_PORT`、`MEDAGENT_PORT` | `make restart` | 端口映射由 Compose 重建容器生效 |
| backend 运行变量，如 `SERVER_MODE`、`CORS_ALLOWED_ORIGINS`、`LOG_LEVEL`、`RATE_LIMIT_ENABLED` | `make restart` | 运行时环境变量需要重建容器 |
| `MYSQL_ROOT_PASSWORD`、`MYSQL_DATABASE` | `make clean && make deploy` | MySQL 初始化值写入 volume，旧 volume 不会自动改密码/库名 |
| `MEDAGENT_PROVIDER`、`MEDAGENT_MODEL`、`MEDAGENT_API_KEY`、`MEDAGENT_LLM_BASE_URL` | `make restart` | medAgent 和 backend 都要拿到新环境变量 |
| 任意 `VITE_*` | `make up` 或 `make deploy` | 前端构建期变量必须重新 build |

## 10. 常见断点

### `make doctor` 提示密钥错误

编辑 `.env`，替换：

```env
JWT_SECRET=local-jwt-secret-at-least-32-bytes
ADMIN_JWT_SECRET=local-admin-secret-at-least-32-bytes
MEDAGENT_API_KEY=sk-local-test-key
```

再运行：

```bash
make doctor
```

### 压测需要关闭后端认证限流

`stress-test` 分支默认：

```env
RATE_LIMIT_ENABLED=false
```

修改后重启整合环境：

```bash
make restart
make verify-env
```

该开关只影响后端认证接口的 `RateLimitMiddleware`，不会改变问诊轮次、地址数量等业务规则限制。

### 端口已被占用

修改 `.env`：

```env
FRONTEND_PORT=15173
BACKEND_PORT=18080
MYSQL_PORT=13306
MEDAGENT_PORT=18083
```

然后：

```bash
make restart
make health
```

### MySQL 密码或库名改了但后端连不上

MySQL 官方镜像只在首次创建 volume 时初始化密码和库名。修改 `MYSQL_ROOT_PASSWORD` 或 `MYSQL_DATABASE` 后，如果旧 volume 还在，需要：

```bash
make clean
make deploy
```

### 前端还是旧 API 地址或旧超时时间

`VITE_*` 是构建期变量。修改后必须重新构建：

```bash
make up
make verify-env
```

### medAgent 启动失败

检查 provider 和 key：

```bash
make logs
make verify-env
```

`MEDAGENT_PROVIDER=deepseek` 时 medAgent 需要 `DEEPSEEK_API_KEY`。Compose 会把 `MEDAGENT_API_KEY` 同步到 `DEEPSEEK_API_KEY`、`DASHSCOPE_API_KEY`、`OPENAI_API_KEY`，所以通常只需要检查 `.env` 中的 `MEDAGENT_API_KEY` 是否非空。

如果接 OpenAI 兼容网关：

```env
MEDAGENT_PROVIDER=openai
MEDAGENT_MODEL=your-model-name
MEDAGENT_BASE_URL=http://medagent:8080
MEDAGENT_LLM_BASE_URL=https://your-gateway.example/v1
```

然后：

```bash
make restart
make medagent-smoke
```

### CORS 报错

默认本地整合部署：

```env
CORS_ALLOWED_ORIGINS=http://localhost:5173
```

如果改了 `FRONTEND_PORT`，同时改 CORS：

```env
FRONTEND_PORT=15173
CORS_ALLOWED_ORIGINS=http://localhost:15173
```

然后：

```bash
make restart
```

## 11. 子模块维护

更新到父仓库记录的版本：

```bash
make init
```

查看当前锁定版本：

```bash
make submodule-status
```

更新 `backend/` 和 `frontend/` 到各自当前分支的远端最新提交：

```bash
make submodule-update-latest
```

预期结果：

- 如果子模块工作区干净且位于分支上，会按当前分支的 upstream 执行快进更新。
- 如果子模块有本地改动或处于 detached HEAD，会报错并要求先处理，避免覆盖本地工作。
- 更新后父仓库会显示对应子模块指针变更，验证后需要在父仓库提交新的子模块指针。

如果需要推进某个子模块版本，应先在对应子模块中切到目标提交或分支并验证，再回到父仓库提交子模块指针变更。

## 12. 测试入口

后端测试：

```bash
make backend-test
```

前端测试：

```bash
make frontend-test
```

如果后端覆盖率或集成测试遇到 testcontainers/Ryuk 问题，可在后端仓库内按其测试约定使用：

```bash
TESTCONTAINERS_RYUK_DISABLED=true go test -cover ./...
```

## Agent 使用说明

根目录 `CLAUDE.md` 和 `AGENTS.md` 都应指向本文件。任何 agent 在当前仓库工作时，都应把根目录 `README.md` 视为仓库级说明源。

处理任务时请遵守：

- 父仓库优先维护整合、部署、环境变量和文档。
- 修改业务逻辑前，先确认变更应落在 `backend` 还是 `frontend` 子模块。
- 不要把 `.env`、密钥、构建缓存或本地日志提交到仓库。
- 修改子模块代码后，需要同时提交子模块仓库内变更和父仓库中的子模块指针变更。

# NEUHIS 前后端整合仓库

本仓库是 NEUHIS Agent 项目的整合、部署和交付入口。它不直接承载前端或后端业务源码的日常开发，而是通过 Git submodule 固定前后端项目版本，并在仓库根目录提供统一的环境变量入口、Makefile 命令入口和 Docker Compose 部署方案。

## 仓库使命

NEUHIS Agent 由多个独立项目组成：患者端/管理端前端、业务后端、MySQL 数据库和 medAgent AI 诊疗引擎。单独维护这些项目时，开发和部署人员需要分别理解多个仓库的启动方式、环境变量和服务依赖。本仓库的目标是把这些分散入口收敛为一个可复制、可验证、可交付的父仓库。

本仓库负责：

- 以子模块方式引入前端和后端，保持业务源码边界清晰。
- 提供根目录 `.env.example`，作为整套系统的环境变量部署入口。
- 提供根目录 `Makefile`，作为初始化、部署、日志、健康检查和测试的统一命令入口。
- 提供根目录 `compose.yaml`，一键编排前端静态站点、后端服务、MySQL 和 medAgent。
- 为人类维护者和 AI coding agent 提供同一份仓库级说明文档。

本仓库不负责：

- 在父仓库中直接修改前端或后端业务逻辑。
- 替代前端、后端各自仓库内的 README、测试策略和开发规范。
- 管理生产密钥。真实密钥只应写入本地或部署环境的 `.env`，不要提交。

## 项目组成

```text
software-practice/
├── backend/                  # 后端子模块：software-practice-backend，dev 分支
│   └── medAgent/             # 后端内部子模块：AI 诊疗引擎
├── frontend/                 # 前端子模块：neuhis-agent-front，main 分支
├── docker/
│   ├── frontend.Dockerfile   # 前端静态资源构建和 Nginx 镜像
│   └── nginx/default.conf    # 前端路由回退和 /api 反向代理
├── compose.yaml              # 整套系统 Docker Compose 编排
├── Makefile                  # 统一操作入口
├── .env.example              # 部署环境变量模板
├── README.md                 # 当前文档
├── CLAUDE.md -> README.md    # Claude 读取入口
└── AGENTS.md -> README.md    # Codex/agent 读取入口
```

子模块来源：

- `backend`: `https://github.com/neu-software-practice/software-practice-backend.git`，跟踪 `dev` 分支。
- `frontend`: `https://github.com/neu-software-practice/neuhis-agent-front.git`，跟踪 `main` 分支。
- `backend/medAgent`: 由后端仓库自身的 `.gitmodules` 管理。

## 运行架构

默认部署拓扑如下：

```text
Browser
  |
  | http://localhost:${FRONTEND_PORT}
  v
frontend container (Nginx + Vite static files)
  |
  | /api/*
  v
backend container (Gin REST/SSE API)
  |                     |
  | DATABASE_DSN        | MEDAGENT_BASE_URL
  v                     v
mysql container      medagent container
```

前端构建时默认使用真实后端模式：

- `VITE_API_MODE=http`
- `VITE_API_BASE_URL=/api`

Nginx 负责把浏览器访问的 `/api/` 反向代理到后端容器的 `http://backend:8080/api/`。后端启动时会自动执行 `backend/db/migrations` 下的数据库迁移。

## 快速开始

前置条件：

- Git
- Docker 和 Docker Compose
- Make
- 可访问 GitHub 和容器镜像仓库

克隆并初始化：

```bash
git clone https://github.com/neu-software-practice/software-practice.git
cd software-practice
make init
make env
```

编辑 `.env`，至少替换以下值：

```env
JWT_SECRET=change-to-a-random-string-at-least-32-bytes
ADMIN_JWT_SECRET=change-to-another-random-string-at-least-32-bytes
MEDAGENT_API_KEY=sk-your-real-provider-key
```

启动整套系统：

```bash
make deploy
```

默认访问地址：

- 前端：`http://localhost:5173`
- 后端健康检查：`http://localhost:8080/api/health`
- medAgent：`http://localhost:8083`
- MySQL：`localhost:3306`

## 环境变量入口

根目录 `.env.example` 是整合部署的唯一模板。运行 `make env` 会在 `.env` 不存在时复制该模板；如果 `.env` 已存在，不会覆盖。

关键变量：

| 变量 | 说明 |
| --- | --- |
| `FRONTEND_PORT` | 前端 Nginx 暴露到宿主机的端口，默认 `5173` |
| `BACKEND_PORT` | 后端 API 暴露到宿主机的端口，默认 `8080` |
| `MYSQL_PORT` | MySQL 暴露到宿主机的端口，默认 `3306` |
| `MEDAGENT_PORT` | medAgent 暴露到宿主机的端口，默认 `8083` |
| `JWT_SECRET` | 患者端 JWT 密钥，必须至少 32 字节 |
| `ADMIN_JWT_SECRET` | 管理端 JWT 密钥，必须至少 32 字节 |
| `MEDAGENT_API_KEY` | DeepSeek、Qwen 或 OpenAI 兼容服务的 API Key |
| `MEDAGENT_PROVIDER` | medAgent Provider，默认 `deepseek` |
| `MEDAGENT_MODEL` | medAgent 模型名，默认 `deepseek-chat` |
| `VITE_API_MODE` | 前端 API 模式，整合部署默认 `http` |
| `VITE_API_BASE_URL` | 前端 API 基础路径，整合部署默认 `/api` |

`make check-env` 会阻止使用默认占位密钥部署。`.env` 已被 `.gitignore` 忽略，不应提交。

## Makefile 使用方式

常用命令：

```bash
make help              # 查看全部命令
make init              # 初始化/更新 backend、frontend 和 backend/medAgent 子模块
make env               # 从 .env.example 创建 .env，已存在则不覆盖
make check-env         # 检查关键密钥是否仍为占位值
make deploy            # 初始化、校验、构建、启动并执行健康检查
make up                # 构建并启动所有服务
make health            # 检查前端首页和后端 /api/health
make logs              # 跟随查看所有服务日志
make ps                # 查看 Compose 服务状态
make restart           # 重启整套服务
make down              # 停止服务，保留 volume
make clean             # 停止服务并删除 volume
make migrate           # 启动 MySQL、medAgent、后端；后端启动时自动迁移
make submodule-status  # 查看递归子模块状态
make backend-test      # 进入 backend 执行 go test ./...
make frontend-test     # 进入 frontend 安装依赖并执行 pnpm test
```

部署主路径推荐使用：

```bash
make init
make env
# 编辑 .env
make deploy
```

## 子模块维护

查看当前锁定版本：

```bash
git submodule status --recursive
```

更新子模块到父仓库记录的版本：

```bash
make init
```

如果需要推进某个子模块版本，应在对应子模块中切到目标提交或分支并验证，再回到父仓库提交子模块指针变更。例如：

```bash
cd backend
git fetch origin dev
git checkout dev
git pull --ff-only
cd ..
git status
```

后端内部的 `medAgent` 使用 SSH URL 声明。`make init` 会在后端子模块本地设置 `git@github.com:` 到 `https://github.com/` 的替换，便于无 SSH key 的部署环境递归初始化。

## 部署验证

部署后执行：

```bash
make ps
make health
```

也可以直接检查：

```bash
curl http://localhost:8080/api/health
curl http://localhost:5173/
```

后端健康检查应返回：

```json
{"status":"ok"}
```

## 常见问题

### `make check-env` 提示需要更新密钥

这是预期保护。编辑 `.env`，替换 `JWT_SECRET`、`ADMIN_JWT_SECRET` 和 `MEDAGENT_API_KEY` 后重试。

### 端口已被占用

修改 `.env` 中的端口变量，例如：

```env
FRONTEND_PORT=15173
BACKEND_PORT=18080
MYSQL_PORT=13306
MEDAGENT_PORT=18083
```

然后重新执行：

```bash
make deploy
```

### 前端 Docker 构建没有执行 `pnpm build`

当前部署镜像使用 `pnpm exec vite build` 生成静态资源。前端子模块当前存在 TypeScript 严格构建错误，直接执行 `pnpm build` 会被 `tsc -b` 阻断；整合部署不在父仓库中修改前端业务源码，因此镜像构建只执行 Vite 产物构建。前端类型问题应在 `frontend` 子模块中单独修复。

### 后端测试遇到 testcontainers 或 Ryuk 问题

父仓库的 `make backend-test` 运行 `go test ./...`。如果执行覆盖率或集成测试时遇到 Ryuk 连接问题，可在后端仓库内按其测试约定使用：

```bash
TESTCONTAINERS_RYUK_DISABLED=true go test -cover ./...
```

## Agent 使用说明

根目录 `CLAUDE.md` 和 `AGENTS.md` 都应指向本文件。任何 agent 在当前仓库工作时，都应把根目录 `README.md` 视为仓库级说明源。

处理任务时请遵守以下边界：

- 父仓库优先维护整合、部署、环境变量和文档。
- 修改业务逻辑前，先确认变更应落在 `backend` 还是 `frontend` 子模块。
- 不要把 `.env`、密钥、构建缓存或本地日志提交到仓库。
- 修改子模块代码后，需要同时提交子模块仓库内变更和父仓库中的子模块指针变更。


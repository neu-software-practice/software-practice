# NEUHIS Agent 测试说明

本文档说明当前项目的测试方案，重点覆盖不依赖真实 LLM 的 mock Agent 接口测试、可视化报告输出、运行命令、测试指标和常见问题。

## 1. 测试目标

本项目包含普通 Web 后端接口，也包含大模型 Agent 对话与决策流程。为了避免真实 API Key 成本、限流和不可控延迟影响测试结果，当前推荐使用 mock Agent 模式进行接口与流程测试。

测试目标：

- 验证后端接口能在不调用真实 LLM 的情况下完整运行。
- 验证患者问诊、消息发送、SSE 回复、流程卡、检验决策、支付、标题生成、快照读取等核心链路。
- 验证 mock Agent 与后端 `medAgent` HTTP 协议兼容。
- 输出 HTML/JSON 可视化报告，用于展示接口耗时、成功率、步骤明细和失败原因。
- 为后续低并发容量测试或 CI 自动化测试提供基础。

## 2. 测试模式

当前推荐测试模式为：

```text
测试脚本
  -> Gin 后端 API
    -> workbench service
      -> medAgent HTTP client
        -> mock medAgent
```

该模式下：

- 后端接口真实运行。
- MySQL 真实读写。
- 认证、JWT、会话、时间线、流程卡、支付模拟等后端逻辑真实执行。
- `medAgent` 服务被替换为协议兼容的 mock 服务。
- 标题生成、复诊摘要等 LLM 调用使用 mock LLM client。
- 不访问 DeepSeek、Qwen、OpenAI 或任何真实模型网关。

## 3. 相关文件

根目录：

| 文件 | 说明 |
| --- | --- |
| `compose.yaml` | 默认整合部署配置 |
| `compose.mock.yaml` | mock 测试模式覆盖配置 |
| `testReadme.md` | 当前测试说明文档 |

后端 mock 能力：

| 文件 | 说明 |
| --- | --- |
| `backend/cmd/mock-medagent/main.go` | mock medAgent 启动入口 |
| `backend/internal/mockmedagent/server.go` | mock medAgent HTTP 服务实现 |
| `backend/internal/mockmedagent/server_test.go` | mock medAgent 协议测试 |
| `backend/internal/llm/mock.go` | mock LLM client |
| `backend/internal/llm/mock_test.go` | mock LLM 测试 |
| `backend/cmd/server/main.go` | 当 `MEDAGENT_PROVIDER=mock` 时启用 mock LLM |

测试脚本：

| 文件 | 说明 |
| --- | --- |
| `backend/tests/perf/mock-agent-flow.mjs` | mock Agent 核心流程测试脚本 |
| `backend/tests/perf/ramp-agent-load.mjs` | 阶梯加压测试脚本，逐步提高并发直到出现错误或达到最高档位 |
| `backend/tests/perf/perf-lib.mjs` | SSE 解析、统计、HTML 报告生成工具 |
| `backend/tests/perf/perf-lib.test.mjs` | 测试脚本工具库单元测试 |
| `backend/tests/perf/README.md` | 测试脚本简要说明 |
| `backend/tests/perf/reports/mock-agent-report.html` | 项目目录下生成的 HTML 报告 |
| `backend/tests/perf/reports/mock-agent-report.json` | 项目目录下生成的 JSON 报告 |
| `backend/tests/perf/reports/mock-agent-ramp-report.html` | 阶梯加压 HTML 分析报告 |
| `backend/tests/perf/reports/mock-agent-ramp-report.json` | 阶梯加压 JSON 原始数据 |

## 4. 启动 mock 测试环境

在项目根目录执行：

```bash
docker compose -f compose.yaml -f compose.mock.yaml up -d --build
```

该命令会启动：

- `frontend`
- `backend`
- `mysql`
- `medagent`

其中 `medagent` 实际运行：

```bash
go run ./cmd/mock-medagent -addr :8080
```

mock 模式关键环境变量：

```env
MEDAGENT_BASE_URL=http://medagent:8080
MEDAGENT_API_KEY=mock-key
MEDAGENT_PROVIDER=mock
MEDAGENT_MODEL=mock-model
RATE_LIMIT_RPS=100
RATE_LIMIT_BURST=200
```

## 5. 健康检查

检查后端：

```bash
curl -sS http://127.0.0.1:8080/api/health
```

预期输出：

```json
{"status":"ok"}
```

检查 mock medAgent：

```bash
curl -sS http://127.0.0.1:8083/health
```

预期输出：

```json
{"status":"ok"}
```

查看容器状态：

```bash
docker compose -f compose.yaml -f compose.mock.yaml ps
```

## 6. 运行测试脚本

默认运行：

```bash
node backend/tests/perf/mock-agent-flow.mjs
```

默认测试地址：

```text
http://localhost:8080/api
```

默认输出：

```text
backend/tests/perf/reports/mock-agent-report.html
backend/tests/perf/reports/mock-agent-report.json
```

成功时输出类似：

```text
Report HTML: /path/to/mock-agent-report.html
Report JSON: /path/to/mock-agent-report.json
Scenarios: 4, success: 4, failed: 0, p95: 312ms
```

## 7. 默认测试场景

默认覆盖 4 个 Agent 场景：

| 场景 | 说明 |
| --- | --- |
| `mock:ask` | 模拟 AI 继续追问 |
| `mock:lab` | 模拟 AI 建议检验，触发检验卡、检验决策和支付 |
| `mock:advice` | 模拟 AI 完成诊断并给出仅医嘱方案 |
| `mock:emergency` | 模拟急症打断 |

每个场景默认执行：

1. 注册用户并获取 JWT。
2. 创建问诊会话。
3. 发送患者消息。
4. 调用 `/assistant-stream` 拉取 SSE。
5. 根据场景处理流程卡。
6. 生成 mock 标题。
7. 读取会话快照。

`mock:lab` 额外执行：

1. 提交检验决策。
2. 支付检验费用。
3. mock medAgent 接收检验结果后返回诊断。

## 8. 可配置参数

测试脚本支持通过环境变量调整：

```bash
PERF_BASE_URL=http://localhost:8080/api
PERF_VUS=1
PERF_ITERATIONS=1
PERF_SCENARIOS=mock:ask,mock:lab,mock:advice,mock:emergency
PERF_TIMEOUT_MS=30000
PERF_HTML_REPORT=backend/tests/perf/reports/mock-agent-report.html
PERF_JSON_REPORT=backend/tests/perf/reports/mock-agent-report.json
```

示例：2 个虚拟用户，每个场景跑 3 次：

```bash
PERF_VUS=2 PERF_ITERATIONS=3 node backend/tests/perf/mock-agent-flow.mjs
```

示例：只跑检验链路：

```bash
PERF_SCENARIOS=mock:lab node backend/tests/perf/mock-agent-flow.mjs
```

## 9. 阶梯加压测试

当需要观察系统在并发逐步升高时从哪里开始出错，可以运行阶梯加压脚本：

```bash
node backend/tests/perf/ramp-agent-load.mjs
```

默认加压档位：

```bash
PERF_RAMP_VUS=1,2,4,8,16,32
PERF_ITERATIONS=1
PERF_RAMP_STOP_ON_ERROR=1
```

含义：

- `PERF_RAMP_VUS`：并发虚拟用户档位，脚本会按从小到大的顺序逐档运行。
- `PERF_ITERATIONS`：每个虚拟用户在每个场景上执行多少轮。
- `PERF_RAMP_STOP_ON_ERROR=1`：某一档出现接口错误、超时或场景失败时立即停止继续加压。
- `PERF_RAMP_STOP_ON_ERROR=0`：即使出现错误也继续跑完所有配置档位。

默认输出：

```text
backend/tests/perf/reports/mock-agent-ramp-report.html
backend/tests/perf/reports/mock-agent-ramp-report.json
backend/tests/perf/reports/ramp-stages/vus-*.html
backend/tests/perf/reports/ramp-stages/vus-*.json
```

示例：从 1 VU 加到 64 VU，首次出错即停止：

```bash
PERF_RAMP_VUS=1,2,4,8,16,32,64 node backend/tests/perf/ramp-agent-load.mjs
```

示例：每档每个场景执行 2 轮：

```bash
PERF_RAMP_VUS=1,2,4,8 PERF_ITERATIONS=2 node backend/tests/perf/ramp-agent-load.mjs
```

阶梯加压报告会额外说明：

- 本次测试目标和 mock 边界。
- 每个并发档位的成功率、失败数、平均耗时、P95、最大耗时。
- 首次错误档位。
- 最高无错误档位。
- 主要错误信息和出现次数。
- 每档独立原始报告路径。

需要注意：本脚本仍然不测试真实 LLM，也不代表公网真实用户压测；它用于在个人 API Key 零成本、模型延迟隔离的前提下，寻找当前后端链路的本地容量边界。

## 10. 生成 demo 报告

如果后端服务没有启动，可以生成一份 demo 可视化报告：

```bash
node backend/tests/perf/mock-agent-flow.mjs --demo
```

demo 模式不会访问后端接口，只用于检查 HTML 报告样式和输出路径。

## 11. 报告内容

单轮 HTML 报告包含：

- 总场景数
- 成功率
- 平均耗时
- P95 耗时
- 场景耗时柱状图
- 场景汇总表
- 步骤明细表
- 失败错误信息

阶梯加压 HTML 报告包含：

- 测试目标
- mock 边界
- 本次结论
- 最高无错误档位
- 首次错误档位
- 加压曲线
- 加压明细
- 错误归因
- 测试流程

JSON 报告包含：

- `generatedAt`
- `baseUrl`
- `config`
- `summary`
- `scenarios`
- 每个场景的步骤耗时、成功状态、错误信息、SSE 事件类型

## 12. 当前验证结果

最近一次已验证结果：

```text
Scenarios: 4
success: 4
failed: 0
p95: 312ms
```

已验证命令：

```bash
node --test backend/tests/perf/perf-lib.test.mjs
node --check backend/tests/perf/mock-agent-flow.mjs
node --check backend/tests/perf/ramp-agent-load.mjs
go test ./internal/mockmedagent ./internal/llm ./internal/service/medagent
docker compose -f compose.yaml -f compose.mock.yaml up -d --build
node backend/tests/perf/mock-agent-flow.mjs
```

## 13. 单元测试

测试脚本工具库：

```bash
node --test backend/tests/perf/perf-lib.test.mjs
```

后端 mock 相关测试：

```bash
cd backend
go test ./internal/mockmedagent ./internal/llm ./internal/service/medagent
```

## 14. 注意事项

### 14.1 必须使用 mock compose 覆盖文件

如果只运行：

```bash
docker compose -f compose.yaml up -d
```

后端会连接真实 medAgent，可能继续调用真实 LLM。

正确命令：

```bash
docker compose -f compose.yaml -f compose.mock.yaml up -d --build
```

### 14.2 mock medAgent session id 长度

后端数据库字段 `visits.medagent_session_id` 对长度有限制。mock medAgent 返回纯 UUID，长度为 36，避免写入数据库时报：

```text
Data too long for column 'medagent_session_id'
```

### 14.3 clientMessageId 长度

`POST /visits/:sessionId/messages` 中的 `clientMessageId` 会被用作 timeline item id。测试脚本使用 36 位 UUID，避免写入数据库时报：

```text
Data too long for column 'id'
```

### 14.4 响应格式差异

当前后端部分接口直接返回业务数据，并不总是返回：

```json
{"success": true, "data": {}}
```

测试脚本的 `unwrapApiResponse` 已兼容：

- 统一 envelope 响应
- 直接业务对象响应

### 14.5 SSE 解析

`/assistant-stream` 返回标准 SSE：

```text
data: {"type":"delta",...}

data: {"type":"done",...}
```

测试脚本会解析 `data:` 行，并要求至少出现一个 `done` 事件。

## 15. 常见问题

### 问题 1：报告中出现 `upstream LLM call failed`

原因：当前服务没有切到 mock 模式，仍连接真实 medAgent 或真实 LLM。

处理：

```bash
docker compose -f compose.yaml -f compose.mock.yaml up -d --build
docker compose -f compose.yaml -f compose.mock.yaml restart medagent backend
```

### 问题 2：`assistant stream did not emit done event`

可能原因：

- mock medAgent 没有启动。
- backend 仍连接真实 medAgent。
- SSE 中返回了 error 事件。

处理：

```bash
curl -sS http://127.0.0.1:8083/health
docker compose -f compose.yaml -f compose.mock.yaml logs medagent backend
```

### 问题 3：注册失败，提示手机号格式错误

测试脚本会自动生成 `13xxxxxxxxx` 格式手机号。如果手动构造请求，请确保手机号为 11 位中国大陆手机号格式。

### 问题 4：接口返回 429

说明触发限流。mock compose 已设置：

```env
RATE_LIMIT_RPS=100
RATE_LIMIT_BURST=200
```

如果仍然触发，请降低：

```bash
PERF_VUS
PERF_ITERATIONS
```

或继续调大限流配置。

## 16. 建议测试流程

日常本地测试：

```bash
docker compose -f compose.yaml -f compose.mock.yaml up -d --build
curl -sS http://127.0.0.1:8080/api/health
curl -sS http://127.0.0.1:8083/health
node backend/tests/perf/mock-agent-flow.mjs
```

脚本自身验证：

```bash
node --test backend/tests/perf/perf-lib.test.mjs
node --check backend/tests/perf/mock-agent-flow.mjs
node --check backend/tests/perf/ramp-agent-load.mjs
```

后端 mock 能力验证：

```bash
cd backend
go test ./internal/mockmedagent ./internal/llm ./internal/service/medagent
```

## 17. 后续可扩展方向

- 增加 `mock:drug` 用药和取药链路测试。
- 增加 `mock:referral` 转诊链路测试。
- 增加 `mock:veto` 暂不决定后继续对话测试。
- 增加 CI 中的 mock Agent smoke test。
- 将报告产物上传到 CI artifacts。
- 固化测试阈值，例如成功率必须为 100%、P95 必须小于指定阈值。

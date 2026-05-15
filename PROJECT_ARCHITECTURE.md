# serve-d 项目架构与依赖关系分析

## 概述

serve-d 是一个 D 语言的 Microsoft Language Server Protocol (LSP) 实现，采用模块化架构设计。主项目通过 Dub 的 subPackages 机制管理 6 个子模块，各模块职责明确、层次清晰。

## 项目结构总览

```
serve-d (根项目)
├── http          - HTTP 文件下载模块
├── protocol      - LSP 协议定义模块
├── lsp           - LSP 核心实现模块
├── serverbase    - LSP 服务器基础框架
├── dcd           - DCD (D Completion Daemon) 客户端
└── workspace-d   - D 语言工作空间核心功能
```

## 详细依赖关系

### 1. 根项目 (serve-d)

**dub.json 配置:**
- **名称**: serve-d
- **描述**: Microsoft Language Server Protocol library and D Server
- **类型**: executable (可执行文件)

**外部依赖:**
- libddoc: 0.8.0 - D 语言文档生成库
- rm-rf: ~>0.1.0 - 文件删除工具
- diet-complete: ~>0.0.3 - Vibe.d diet 模板补全
- emsi_containers: 0.9.0 - EMSI 容器库
- fuzzymatch: ~>1.0.0 - 模糊匹配库
- sdlfmt: ~>0.1.1 - SDL 格式化工具

**内部子包依赖:**
- serve-d:http: *
- serve-d:lsp: *
- serve-d:serverbase: *
- serve-d:workspace-d: *

**子包列表 (subPackages):**
- http
- protocol
- lsp
- serverbase
- dcd
- workspace-d

---

### 2. HTTP 模块 (http)

**位置:** `http/dub.sdl`

**职责:** 
- 提供 HTTP 文件下载功能，支持进度显示
- Windows 平台使用 WinHTTP，其他平台使用 dub requests 库
- 用于下载 DCD、DScanner 等工具的二进制文件

**依赖关系:**
```
requests (~>2.1)  ← http 模块
```

**主要功能:**
- `downloadFileManual()`: 手动下载文件并显示进度
- `humanSize()`: 人类可读的文件大小格式化
- 支持光纤 (Fiber) 协作式多任务，避免阻塞 RPC 通信

**被依赖情况:**
- 被根项目 serve-d 直接引用
- 主要用于下载工具和二进制文件

---

### 3. Protocol 模块 (protocol)

**位置:** `protocol/dub.sdl`

**职责:**
- LSP 协议类型定义
- JSON-RPC 消息格式定义
- URI 处理工具

**依赖关系:**
```
mir-algorithm (~>3.20)  ← protocol 模块
mir-ion (~>2.1)         ← protocol 模块
```

**主要功能:**
- 定义 LSP 标准类型 (Position, Range, TextDocumentIdentifier 等)
- JSON-RPC 消息解析和序列化
- URI 与文件路径转换

**被依赖情况:**
- **lsp 模块** 直接依赖 protocol 模块
- 是整个 LSP 实现的基础协议层

---

### 4. LSP 模块 (lsp)

**位置:** `lsp/dub.sdl`

**职责:**
- LSP 协议核心实现
- 文本管理器
- 文件读取器
- JSON-RPC 通信

**依赖关系:**
```
serve-d:protocol        ← lsp 模块 (内部依赖)
mir-algorithm (~>3.20)  ← lsp 模块
mir-ion (~>2.1)         ← lsp 模块
```

**主要文件:**
- `filereader.d`: 异步文件读取
- `jsonrpc.d`: JSON-RPC 通信协议
- `textdocumentmanager.d`: 文本文档管理

**被依赖情况:**
- **serverbase 模块** 依赖 lsp 模块
- 为上层提供完整的 LSP 协议支持

---

### 5. Serverbase 模块 (serverbase)

**位置:** `serverbase/dub.sdl`

**职责:**
- LSP 服务器基础框架
- 快速构建 LSP 服务器的工具集
- stdin/stdout RPC 通道管理

**依赖关系:**
```
serve-d:lsp  ← serverbase 模块 (内部依赖)
```

**主要功能:**
- `LanguageServerConfig`: 服务器配置结构
- `runLSPServer()`: 运行 LSP 服务器的通用入口
- 自动重定向 stdin/stdout，避免污染 RPC 通道
- GC 管理和性能追踪
- Fiber 调度器管理

**被依赖情况:**
- **根项目 serve-d** 使用 serverbase 搭建主服务器
- **null_server** 测试项目依赖此模块
- 提供通用的 LSP 服务器骨架

---

### 6. DCD 模块 (dcd)

**位置:** `dcd/dub.sdl`

**职责:**
- DCD (D Completion Daemon) 客户端实现
- 代码补全和符号查询
- 直接 socket 通信（非进程调用）

**依赖关系:**
```
dcd:common (~>0.16.0-beta.1)  ← dcd 模块
```

**主要特点:**
- 直接通过 socket 与 DCD 服务器通信
- 低延迟设计，避免进程创建开销
- 提供 D 语言符号补全和导航功能

**被依赖情况:**
- **workspace-d 模块** 依赖 dcd 模块
- 为 D 语言代码补全提供底层支持

---

### 7. Workspace-d 模块 (workspace-d)

**位置:** `workspace-d/dub.sdl`

**职责:**
- D 语言工作空间核心功能
- 统一管理 DCD、DScanner、Dfmt 工具
- Dub 项目管理
- 代码分析和处理

**依赖关系:**
```
dfmt (~>0.15.0)              ← workspace-d 模块
inifiled (1.3.3)             ← workspace-d 模块
serve-d:dcd                  ← workspace-d 模块 (内部依赖)
dub (~>1.40.0)               ← workspace-d 模块
emsi_containers (0.9.0)      ← workspace-d 模块
dscanner (~>0.16.0-beta.5)   ← workspace-d 模块
libdparse (~>0.25.0)         ← workspace-d 模块
standardpaths (0.8.2)        ← workspace-d 模块
mir-algorithm (~>3.20)       ← workspace-d 模块
```

**主要功能:**
- **Dub 项目管理**: 解析 dub.sdl/dub.json，管理依赖
- **代码格式化**: 集成 dfmt
- **代码静态分析**: 集成 D-Scanner
- **代码补全**: 通过 DCD 提供补全建议
- **AST 解析**: 使用 libdparse 解析 D 源代码
- **导入路径管理**: 自动配置编译器导入路径
- **配置管理**: 统一的配置文件接口

**被依赖情况:**
- **根项目 serve-d** 直接使用 workspace-d
- **多个测试用例** 依赖 workspace-d:
  - test/tc_dub
  - test/tc_integrated_dfmt
  - test/tc_fsworkspace
  - test/tc_dub_dependencies
  - test/tc_implement_interface

---

## 依赖层次图

```
第 0 层 (最底层):
┌─────────────┐     ┌──────────────┐
│   protocol  │     │     http     │
│ mir-algo    │     │   requests   │
│ mir-ion     │     │              │
└──────┬──────┘     └──────────────┘
       
第 1 层:
┌─────────────┐     ┌──────────────┐
│     lsp     │     │     dcd      │
│  →protocol  │     │  dcd:common  │
└──────┬──────┘     └──────┬───────┘
       
第 2 层:
┌─────────────┐
│  serverbase │
│   →lsp      │
└──────┬──────┘
       
第 3 层:
┌──────────────────────┐
│    workspace-d       │
│ →dcd, dfmt, dscanner │
│ →libdparse, dub      │
└──────────┬───────────┘
       
第 4 层 (顶层):
┌────────────────────────┐
│   serve-d (executable) │
│ →http, lsp, serverbase │
│ →workspace-d           │
│ + 外部依赖库           │
└────────────────────────┘
```

---

## 数据流与调用关系

### LSP 请求处理流程

```
编辑器/客户端
    ↓ (JSON-RPC over stdin/stdout)
serve-d 主程序 (source/app.d)
    ↓
serverbase (路由和分发)
    ↓
extension.d (具体命令处理)
    ↓
workspace-d (D 语言功能实现)
    ├→ DCD (代码补全)
    ├→ DScanner (静态分析)
    ├→ Dfmt (格式化)
    └→ libdparse (AST 解析)
    ↓
返回结果给客户端
```

### 配置管理流程

```
编辑器配置请求
    ↓
served.extension.changedConfig()
    ↓
workspaced.api.Configuration
    ↓
更新 workspace-d 组件配置
    ├→ DCD 配置
    ├→ DScanner 配置
    ├→ Dfmt 配置
    └→ Dub 项目配置
```

---

## 测试项目依赖

### 测试用例结构

```
test/
├── tc_as_a_exe/          → 依赖 workspace-d
├── tc_dub/               → 依赖 workspace-d
├── tc_dub_dependencies/  → 依赖 workspace-d
├── tc_dub_empty/         → 依赖 workspace-d
├── tc_fsworkspace/       → 依赖 workspace-d
├── tc_implement_interface/ → 依赖 workspace-d
├── tc_integrated_dfmt/   → 依赖 workspace-d
└── tc_integrated_dscanner/ → 依赖 workspace-d
```

### Null Server 测试

```
null_server/
└── 依赖 serverbase 模块
    └→ 用于测试 LSP 服务器基础框架
```

---

## 关键设计特点

### 1. 模块化分离

- **protocol**: 纯协议定义，无业务逻辑
- **lsp**: LSP 协议实现，独立于具体语言
- **serverbase**: 通用 LSP 服务器框架
- **workspace-d**: D 语言特定功能
- **http**: 独立的网络下载功能
- **dcd**: 专门的补全服务客户端

### 2. 分层架构

- **底层**: protocol (协议定义)
- **中层**: lsp, serverbase (框架层)
- **高层**: workspace-d (语言特性层)
- **顶层**: serve-d (应用层)

### 3. 依赖注入

workspace-d 使用组件工厂模式:
- `ComponentFactory`: 组件创建工厂
- `WorkspaceD.Instance`: 工作空间实例
- 支持动态绑定和解绑组件

### 4. 异步处理

- 使用 Fiber 进行协作式多任务
- 异步文件读取 (filereader.d)
- 非阻塞 RPC 通信

### 5. 配置系统

- 多层配置支持 (用户/工作空间/项目)
- 热重载配置变更
- 统一的配置接口

---

## 外部工具集成

### DCD (D Completion Daemon)
- 版本：~>0.16.0-beta.1
- 用途：代码补全和符号查询
- 集成方式：socket 直接通信

### DScanner
- 版本：~>0.16.0-beta.5
- 用途：静态代码分析
- 功能：代码检查、提示、诊断

### Dfmt
- 版本：~>0.15.0
- 用途：代码格式化
- 功能：自动格式化 D 代码

### Libdparse
- 版本：~>0.25.0
- 用途：D 语言 AST 解析
- 功能：语法分析、符号提取

### Dub
- 版本：~>1.40.0
- 用途：D 语言包管理器
- 功能：项目管理、依赖解析

---

## 总结

serve-d 项目展现了一个高度模块化的 LSP 服务器架构：

1. **清晰的职责划分**: 每个子模块都有明确的单一职责
2. **层次分明的依赖**: 底层模块不依赖高层模块，便于维护和测试
3. **可复用的组件**: serverbase 可用于构建其他语言的 LSP 服务器
4. **灵活的扩展性**: 通过组件工厂模式支持功能扩展
5. **完善的测试体系**: 多个测试用例覆盖不同功能模块

这种架构设计使得 serve-d 不仅能作为 D 语言的 LSP 服务器，其核心组件（如 serverbase、lsp、protocol）还可以独立复用，为其他语言的 LSP 实现提供参考框架。

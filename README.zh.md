![GitHub License](https://img.shields.io/github/license/MFSGA/OpenChimera?style=for-the-badge&logo=github) ![GitHub Tag](https://img.shields.io/github/v/release/MFSGA/OpenChimera?style=for-the-badge&logo=github)

中文 | [English](README.md)

# OpenChimera

OpenChimera 是一个 OpenWrt 集成项目，将 [Chimera_Client](https://github.com/MFSGA/Chimera_Client)（clash-rs，一个基于 Rust 的代理核心）打包为 OpenWrt 包，并提供包含 UCI 配置、procd 初始化服务和运行时工具的管理层。

## 软件包

OpenChimera 提供两个 OpenWrt 软件包：

| 软件包 | 角色 | 功能 |
|---|---|---|
| `chimera-core` | 预编译二进制核心 | 下载上游 `clash_chimera` 二进制文件，安装到 `/usr/libexec/chimera`，并通过 OpenWrt alternatives 暴露 `/usr/bin/mihomo`。 |
| `openchimera` | 管理层 | 提供 UCI 配置、procd 初始化脚本、配置生成、验证、日志记录和系统升级（sysupgrade）持久化。依赖于 `chimera-core` 提供的 `mihomo` 虚拟提供者。 |

## 里程碑 1 范围

里程碑 1 专注于最小化、可构建、可测试的 x86_64 OpenWrt 集成。

### 包含的功能

- `chimera-core` 作为 x86_64 的预编译二进制包（SDK 内无需 Rust 源码编译）
- `openchimera` 管理包，包含最小 UCI 架构和 procd 生命周期
- 通过 `kmod-tun` 提供基础 TUN 支持
- 混合端口、SOCKS 端口和 HTTP 端口代理模式
- 启动前进行配置验证
- 基于重启的重载（不支持 SIGHUP）
- 本地 SDK 构建工作流

### 延后的功能

以下功能**不**属于里程碑 1，计划在后续里程碑中实现：

| 功能 | 原因 |
|---|---|
| **aarch64 支持** | 上游 CI 未发布 `aarch64-unknown-linux-musl` 产物。aarch64 仅存在 gnu 链接的二进制文件，与 OpenWrt 的 musl libc 不兼容。待验证的 musl 产物可用后启用。 |
| **Rust 源码编译** | 里程碑 1 使用预编译二进制，避免在 OpenWrt 构建系统中引入 Rust 工具链依赖。如果上游 CI 流程变化或需要自托管交叉构建以支持缺失架构，可能会在后续里程碑中添加源码编译。 |
| **LuCI 网页界面** | LuCI 应用已规划但尚未实现。里程碑 1 仅支持命令行操作。 |
| **TProxy / Redirect** | 透明代理模式（除基础 TUN 外）已延后。它们需要额外的内核模块（`kmod-nft-tproxy`、`kmod-nft-socket`）、nftables 集成和仔细的路由设计。 |
| **订阅 / 配置文件调度器** | 自动订阅更新和基于 cron 的配置文件刷新不包含在里程碑 1 中。 |
| **发布源 / CI/CD** | 托管的 opkg 源和 CI 发布工作流是未来的工作。里程碑 1 仅使用本地 SDK 构建方式。 |

### 架构支持

| 架构 | 里程碑 1 | 说明 |
|---|---|---|
| `x86_64` (musl) | ✅ 支持 | 主要目标。上游提供 `x86_64-unknown-linux-musl` 产物。 |
| `aarch64` (musl) | ⏳ 延后 | 等待上游发布 `aarch64-unknown-linux-musl` 产物。 |
| `x86_64` (gnu) | ❌ 排除 | glibc 链接的二进制无法在 OpenWrt musl 上运行。 |
| `aarch64` (gnu) | ❌ 排除 | glibc 链接的二进制无法在 OpenWrt musl 上运行。 |

### 版本锁定

每个 `chimera-core` 发布版本都引用一个特定的上游标签（例如 `v0.20.2`）。从不使用变动的 `latest` 标签。这确保了可重现的构建和清晰的升级路径。

## 环境要求

- x86_64 OpenWrt SDK（推荐 OpenWrt 24.10 或更高版本）
- 带有标准构建工具（gcc、make 等）的 Linux 主机

## SDK 构建

使用 OpenWrt SDK 构建两个软件包：

```shell
# 添加 OpenChimera 源
echo "src-git openchimera https://github.com/MFSGA/OpenChimera.git;main" >> "feeds.conf.default"

# 更新并安装源
./scripts/feeds update -a
./scripts/feeds install -a

# 编译软件包
make package/chimera-core/compile V=s
make package/openchimera/compile V=s
```

编译后的 `.ipk` 文件可以在 `bin/packages/x86_64/openchimera/` 中找到。

### 构建说明

- `chimera-core` 在构建过程中下载预编译的上游二进制文件，无需 Rust 工具链。
- 构建需要网络访问以获取上游发布产物。
- 里程碑 1 仅支持 x86_64 OpenWrt SDK 目标。

## 安装

将编译好的 `.ipk` 文件复制到 OpenWrt 设备并安装：

```shell
opkg install chimera-core_*.ipk openchimera_*.ipk
```

## 快速开始

安装完成后：

1. 启用服务：
   ```shell
   uci set openchimera.main.enabled=1
   uci commit openchimera
   ```

2. 配置代理端口（可选，默认为 `mixed-port: 7890`）：
   ```shell
   uci set openchimera.main.mixed_port=7890
   uci commit openchimera
   ```

3. 启动服务：
   ```shell
   /etc/init.d/openchimera start
   ```

4. 验证代理正在运行：
   ```shell
   curl -x http://127.0.0.1:7890 http://example.com -I --max-time 10
   ```

5. 查看日志：
   ```shell
   cat /var/log/openchimera/core.log
   ```

## 配置

UCI 配置存储在 `/etc/config/openchimera`。架构包括：

- `enabled` - 启用或禁用服务
- `config_path` - 核心 YAML 配置文件路径
- `work_dir` - 核心进程的工作目录
- `mixed_port`、`port`、`socks_port` - 代理监听端口
- `external_controller`、`secret` - API 绑定和认证
- `tun_enabled`、`tun_device`、`tun_route_table` - 基础 TUN 设置
- `log_path` - 日志文件路径

## 文档

| 文档 | 说明 |
|------|------|
| **[docs/sdk-build.md](docs/sdk-build.md)** | 完整的 SDK 构建指南，包含环境要求、故障排除和构建说明 |
| **[docs/arch-matrix.md](docs/arch-matrix.md)** | 架构支持矩阵（x86_64、aarch64）和产物版本锁定策略 |
| **[docs/qa-checklist.md](docs/qa-checklist.md)** | QA 环境检查清单和验证流程 |
| **[docs/integration-verification.md](docs/integration-verification.md)** | chimera-core 与 openchimera 集成验证报告 |
| **[docs/migration-guide.md](docs/migration-guide.md)** | 从 Nikki / mihomo-meta 迁移到 OpenChimera 的指南 |
| **[docs/aarch64-enablement.md](docs/aarch64-enablement.md)** | 启用 aarch64 支持的规划和前提条件 |
| **[docs/luci-app-design.md](docs/luci-app-design.md)** | LuCI 网页界面设计文档（已规划，尚未实现） |
| **[docs/cicd-release-feed.md](docs/cicd-release-feed.md)** | CI/CD 发布源设计文档（已规划，尚未实现） |
| **[docs/tproxy-redirect-plan.md](docs/tproxy-redirect-plan.md)** | TProxy / Redirect 透明代理扩展计划（已规划，尚未实现） |

## 兼容性

OpenChimera 集成了 `clash-rs` / Chimera_Client 核心，该核心实现了 Clash 兼容的 API 和配置格式。但请注意：

- **不**声称或保证与 Mihomo 完全功能对等。
- 某些 Nikki / Mihomo 特有的配置字段（如 `auto-redirect`、`auto-detect-interface`、`disable-icmp-forwarding`）不受 Chimera 支持，会导致验证错误。
- 不支持基于 SIGHUP 的热重载。配置变更需要完全重启。
- 里程碑 1 未实现 TProxy 和 Redirect 模式。

## 路线图

### 里程碑 1（当前）

- [x] 架构 / 产物矩阵
- [x] `chimera-core` 预编译包
- [x] `openchimera` UCI 架构和运行时
- [ ] SDK 编译质量验证
- [ ] 运行时生命周期质量验证
- [ ] 混合端口和 TUN 运行时质量验证

### 后续里程碑

- [ ] aarch64 musl 支持（等待上游产物）
- [ ] LuCI 网页界面
- [ ] TProxy / Redirect 透明代理模式
- [ ] 订阅 / 配置文件调度器
- [ ] 发布源和 CI/CD 工作流
- [ ] SDK 内 Rust 源码编译（可选）

## 依赖

### chimera-core

- 运行时无依赖（自包含二进制）

### openchimera

- `chimera-core`（或任何提供 `mihomo` 虚拟提供者的软件包）
- `ca-bundle`
- `curl`
- `yq`
- `kmod-tun`

## 许可证

[Apache 2.0](LICENSE)

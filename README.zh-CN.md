[English](README.md) | 简体中文

# VPS Agent

VPS 网络延迟监测探针，用于向主控端上报网络延迟数据。

## 快速开始

使用部署脚本一键完成安装和配置：

```bash
bash <(curl -sL vps-agent.sh)
```

## 部署脚本功能

部署脚本提供交互式菜单，支持以下功能：

- **部署服务**：环境检查、版本选择、配置文件下载、环境变量配置、systemd 服务安装
- **更新服务**：完整更新、仅更新二进制文件、仅更新配置文件、修改环境变量配置
- **服务管理**：查看状态、启动、停止、重启
- **查看日志**：查看历史日志、实时跟踪日志
- **卸载**：停止服务、删除文件、清理 systemd 配置

## 部署目录结构

```
/opt/agent/
├── vps-agent              # 二进制文件
├── .env                   # 环境变量配置
├── .env.example           # 环境变量模板
├── config/
│   ├── probe-targets.yaml # 监测目标配置
│   ├── region-codes.json  # 行政区划代码
│   └── isp-codes.json     # 网络服务商代码
└── logs/                  # 日志目录（自动创建）
```

## 手动操作

```bash
# 查看版本
/opt/agent/vps-agent --version

# 手动启停服务
systemctl start vps-agent
systemctl stop vps-agent
systemctl restart vps-agent

# 查看服务状态
systemctl status vps-agent

# 查看实时日志
journalctl -u vps-agent -f
```

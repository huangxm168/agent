# VPS Agent

VPS 网络延迟监测探针，用于向主控端上报网络延迟数据。

## 下载

```bash
curl -L https://github.com/huangxm168/agent/releases/latest/download/vps-agent -o vps-agent
chmod +x vps-agent
```

## 配置

运行前需要配置环境变量。

## 运行

```bash
# 查看版本
./vps-agent --version

# 前台运行
./vps-agent

# 后台运行（推荐使用 systemd 管理）
```

## 部署目录结构

```
/opt/agent/
├── vps-agent          # 二进制文件
├── .env               # 环境变量配置
├── config/
│   └── probe-targets.yaml  # 监测目标配置
└── logs/              # 日志目录（自动创建）
```

## 更新

```bash
# 下载最新版本
curl -L https://github.com/huangxm168/agent/releases/latest/download/vps-agent -o /opt/agent/vps-agent

# 重启服务
systemctl restart vps-agent
```

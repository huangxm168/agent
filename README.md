[简体中文](README.zh-CN.md) | English

# VPS Agent

A VPS network latency monitoring probe for reporting network latency data to the control server.

## Quick Start

Use the deployment script for one-click installation and configuration:

```bash
bash <(curl -sL vps-agent.sh)
```

## Deployment Script Features

The deployment script provides an interactive menu with the following features:

- **Deploy Service**: Environment check, version selection, configuration file download, environment variable configuration, systemd service installation
- **Update Service**: Full update, binary-only update, configuration-only update, modify environment variable configuration
- **Service Management**: View status, start, stop, restart
- **View Logs**: View historical logs, real-time log tracking
- **Uninstall**: Stop service, delete files, clean up systemd configuration

## Deployment Directory Structure

```
/opt/agent/
├── vps-agent              # Binary file
├── .env                   # Environment variable configuration
├── .env.example           # Environment variable template
├── config/
│   ├── probe-targets.yaml # Monitoring target configuration
│   ├── region-codes.json  # Administrative region codes
│   └── isp-codes.json     # Network service provider codes
└── logs/                  # Log directory (auto-created)
```

## Manual Operations

```bash
# View version
/opt/agent/vps-agent --version

# Manually start/stop service
systemctl start vps-agent
systemctl stop vps-agent
systemctl restart vps-agent

# View service status
systemctl status vps-agent

# View real-time logs
journalctl -u vps-agent -f
```

# Podman Monitoring Stack — Setup Reference

**Host:**  (Arch Linux)  
 **Date:** March 2026

---

## Overview

A full monitoring stack for a Podman system running both rootful and rootless containers, with Grafana dashboards and Telegram alerts.

### Stack Components

**damacas (Arch Linux)**

| Component                  | Type              | Port |
|----------------------------|-------------------|------|
| Podman Exporter (rootless) | Quadlet container | 9882 |
| Podman Exporter (rootful)  | Quadlet container | 9883 |
| Prometheus                 | Native (pacman)   | 9090 |
| Grafana                    | Native (pacman)   | 3030 |
| Node Exporter (damacas)    | Native (pacman)   | 9100 |

**raspberrypi (Debian/OMV)**

| Component        | Type             | Port |
|------------------|------------------|------|
| Node Exporter    | Native (apt)     | 9100 |
| AdGuard Exporter | Docker container | 9618 |

**AdGuard Home (macvlan, 192.168.0.135)**

| Component            | Port |
|----------------------|------|
| AdGuard Home web/API | 80   |
| DNS                  | 53   |

---

## Podman Exporters

### Rootless Exporter

**File:** `~/.config/containers/systemd/podman-exporter.container`

```ini
[Unit]
Description=Podman Prometheus Exporter

[Container]
Image=quay.io/navidys/prometheus-podman-exporter:v1.11.0
ContainerName=podman-exporter
UserNS=keep-id
Volume=/run/user/1000/podman/podman.sock:/run/podman/podman.sock
Environment=CONTAINER_HOST=unix:///run/podman/podman.sock
Network=host
PodmanArgs=--security-opt label=disable
Exec=--web.listen-address=:9882 --collector.enable-all

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

### Rootful Exporter

**File:** `/etc/containers/systemd/podman-exporter-rootful.container`

```ini
[Unit]
Description=Podman Prometheus Exporter (Rootful)

[Container]
Image=quay.io/navidys/prometheus-podman-exporter:v1.11.0
ContainerName=podman-exporter-rootful
Volume=/run/podman/podman.sock:/run/podman/podman.sock
Environment=CONTAINER_HOST=unix:///run/podman/podman.sock
Network=host
PodmanArgs=--security-opt label=disable
Exec=--web.listen-address=:9883 --collector.enable-all

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Managing Exporters

```bash
# Rootless
systemctl --user daemon-reload
systemctl --user start podman-exporter
systemctl --user status podman-exporter

# Rootful
sudo systemctl daemon-reload
sudo systemctl start podman-exporter-rootful
sudo systemctl status podman-exporter-rootful

# Note: quadlets cannot be 'enabled' with systemctl enable — they are auto-started by the generator
```

### Verify Metrics

```bash
curl -s http://localhost:9882/metrics | grep "^# HELP podman_"   # rootless
curl -s http://localhost:9883/metrics | grep "^# HELP podman_"   # rootful
```

---

## Prometheus

### Installation

```bash
sudo pacman -S prometheus
sudo systemctl enable --now prometheus
```

### Config File

**File:** `/etc/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:

rule_files:

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "podman-rootless"
    static_configs:
      - targets: ["localhost:9882"]
        labels:
          host: "damacas"
          context: "rootless"

  - job_name: "podman-rootful"
    static_configs:
      - targets: ["localhost:9883"]
        labels:
          host: "damacas"
          context: "rootful"

  - job_name: "node"
    static_configs:
      - targets: ["localhost:9100"]
        labels:
          host: "damacas"

  - job_name: "rpi-node"
    static_configs:
      - targets: ["IPAddress:9100"]
        labels:
          host: "raspberrypi"

  - job_name: "adguard"
    static_configs:
      - targets: ["IPAddress:9618"]
        labels:
          host: "raspberrypi"
```

### Useful Commands

```bash
# Validate config
sudo promtool check config /etc/prometheus/prometheus.yml

# Check all scrape targets
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"job"|"health"'

# Restart
sudo systemctl restart prometheus
```

---

## Node Exporter

### Installation

```bash
sudo pacman -S prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

### Enable systemd collector

**File:** `/etc/conf.d/prometheus-node-exporter`

```
NODE_EXPORTER_ARGS="--collector.systemd"
```

```bash
sudo systemctl restart prometheus-node-exporter
```

---

## Raspberry Pi (OMV)

### Node Exporter Installation

```bash
sudo apt install prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

Verify from Arch Server:

```bash
curl -s http://IPAddress[RPi]:9100/metrics | head -5
```

---

## AdGuard Home Exporter

AdGuard runs in Docker on a macvlan adapter at `192.168.0.135`. The exporter runs on the Pi and scrapes AdGuard's API.

### Verify AdGuard API is accessible

```bash
curl -s http://"IPAddress-Adguard"/control/status -u "admin:yourpassword" | python3 -m json.tool
```

### Run the exporter (on the Pi)

```bash
sudo docker run -d \
  --name adguard-exporter \
  --restart unless-stopped \
  -e 'ADGUARD_SERVERS=http://IPAddress-Adguard' \
  -e 'ADGUARD_USERNAMES="username"' \
  -e 'ADGUARD_PASSWORDS="password"' \
  -e 'INTERVAL=15s' \
  -p 9618:9618 \
  ghcr.io/henrywhitaker3/adguard-exporter:latest
```

Verify metrics:

```bash
curl -s http://localhost:9618/metrics | grep "^# HELP adguard_"
```

---

## Grafana

### Installation

```bash
sudo pacman -S grafana
```

### Config

**File:** `/etc/grafana.ini`

Key settings changed from defaults:

```ini
[server]
http_port = 3030

[server]
domain = grafana.yourdomain.com
root_url = https://grafana.yourdomain.com
```

```bash
sudo systemctl enable --now grafana
```

### Access

- Local: `http://localhost:3030`
- Network: `http://'IPAddress-Server':3030`
- Via reverse proxy: `https://grafana.yourdomain.com`

### Dashboards Imported

| Dashboard                 | ID    | Purpose                            |
|---------------------------|-------|------------------------------------|
| Podman Exporter Dashboard | 20162 | Container metrics                  |
| Node Exporter Full        | 1860  | Host system metrics (damacas + Pi) |
| AdGuard Home              | 20799 | DNS metrics and query stats        |

Note: The Node Exporter Full dashboard covers both damacas and the Raspberry Pi. Use the **Job** and **Nodename** dropdowns at the top to switch between hosts. Type `rpi-node` in the Job field to see the Pi.

### Data Source Setup

1. Connections → Data Sources → Add data source
2. Select Prometheus
3. URL: `http://localhost:9090`
4. Save & Test

---

## Telegram Alerts

### Setup

1. Message @BotFather in Telegram → `/newbot`
2. Get bot token
3. Clear any existing webhook: `curl -s "https://api.telegram.org/bot<token>/deleteWebhook"`
4. Message your bot, then get chat ID:

```bash
curl -s "https://api.telegram.org/bot<token>/getUpdates" | python3 -m json.tool
```

1. In Grafana: Alerting → Contact Points → Add → Telegram → enter token + chat ID → Test

### Alert Rules Configured

All rules live in folder **Podman**, group **Container Alerts**, with **2m pending period** and **Telegram** contact point. "No data" and "Error" states are set to **Normal** to avoid false positives.

#### Container Down

```
podman_container_state == 5
* on(id) group_left(name)
podman_container_info
```

Fires when any container (rootless or rootful) is in exited state (state 5).

#### High Memory Usage

```
(podman_container_mem_usage_bytes / podman_container_mem_limit_bytes) * 100 > 80
```

Fires when a container exceeds 80% of its memory limit. Requires containers to have memory limits set.

#### Low Disk Space

```
(node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint!="/boot"} / node_filesystem_size_bytes{fstype!="tmpfs",mountpoint!="/boot"}) * 100 < 20
```

Fires when any real filesystem drops below 20% free space. `/boot` is excluded as it is intentionally small on the Raspberry Pi.

#### High CPU Load

```
node_load15 > 12
```

Fires when 15-minute load average exceeds 12 (75% of 16 cores).

#### High Disk I/O

```
rate(node_disk_io_time_seconds_total[5m]) > 0.9
```

Fires when disk is busy more than 90% of the time.

#### Low System Memory

```
(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
```

Fires when available host memory drops below 10%.

#### High Swap Usage

```
(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100 > 50
```

Fires when swap usage exceeds 50%.

#### AdGuard Down

```
adguard_running == 0
```

Fires when AdGuard Home stops running.

#### AdGuard Protection Disabled

```
adguard_protection_enabled == 0
```

Fires when DNS filtering is turned off.

#### AdGuard Slow Upstream

```
adguard_avg_processing_time_seconds > 0.5
```

Fires when average DNS query processing time exceeds 500ms.

#### AdGuard Scrape Errors

```
rate(adguard_scrape_errors_total[5m]) > 0
```

Fires when the exporter cannot reach AdGuard's API.

---

## Homepage Widget

**File:** `~/.config/homepage/services.yaml` (or equivalent)

```yaml
- Grafana:
    icon: grafana.png
    href: https://grafana.yourdomain.com
    description: Metrics & Dashboards
    widget:
      type: grafana
      url: http://host.containers.internal:3030
      username: admin
      password: yourpassword
```

Note: Use `host.containers.internal` as the hostname to reach the host from inside a Podman container.

---

## Reverse Proxy (NPM)

In Nginx Proxy Manager:

- **Forward host:** `localhost` or `IPAddress-NPM`
- **Forward port:** `3030`
- **Enable Websocket Support** (required for Grafana)
- **SSL:** enabled with Force SSL

In AdGuard DNS rewrites:

- Domain: `grafana.yourdomain.com` → `IPAdress-NPM`

---

## Troubleshooting

### Prometheus won't start

```bash
sudo promtool check config /etc/prometheus/prometheus.yml
sudo journalctl -u prometheus -n 20
```

YAML indentation is strict — use the `tee` heredoc method to rewrite the config cleanly if it gets mangled by repeated edits.

### Grafana port conflict

```bash
sudo ss -tlnp | grep LISTEN
```

Change port in `/etc/grafana.ini` → `http_port = 3030`

### Quadlet won't generate service file

```bash
sudo journalctl -xe | grep -i quadlet
/usr/lib/podman/quadlet --dryrun 2>&1
```

Note: quadlets cannot use `systemctl enable` — they are transient/generated units. Use `systemctl start` instead.

### DatasourceNoData alerts firing falsely

Edit the alert rule → Section 4 → "Configure no data and error handling" → set "Alert state if no data" to **Normal**.


## Key Ports Reference

**Server**

| Service                    | Port |
|----------------------------|------|
| Prometheus                 | 9090 |
| Grafana                    | 3030 |
| Podman Exporter (rootless) | 9882 |
| Podman Exporter (rootful)  | 9883 |
| Node Exporter              | 9100 |

**raspberrypi**

| Service          | Port |
|------------------|------|
| Node Exporter    | 9100 |
| AdGuard Exporter | 9618 |

**AdGuard Home**

| Service      | Port |
|--------------|------|
| Web UI / API | 80   |
| DNS          | 53   |

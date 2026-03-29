# Monitoring Stack

A Prometheus/Grafana monitoring stack for a home server running Podman (rootful and rootless), with additional coverage for a Raspberry Pi running OMV and AdGuard Home.

---

## Architecture

```
Arch_Server (192.168.x.x)
├── Prometheus            — scrapes all targets, stores metrics
├── Grafana               — dashboards and alerts
├── Node Exporter         — host metrics (CPU, memory, disk, network)
├── Podman Exporter (rootless) — rootless container metrics  :9882
└── Podman Exporter (rootful)  — rootful container metrics   :9883

Raspberry Pi (192.168.x.x)
├── Node Exporter         — Pi host metrics                  :9100
└── AdGuard Exporter      — DNS query metrics                :9618

AdGuard Home (macvlan IP)
└── DNS filtering + query stats                              :80
```

---

## Stack Components

| Component | Host | Type | Port |
|-----------|------|------|------|
| Prometheus | Arch_Server | Native (pacman) | 9090 |
| Grafana | Arch_Server | Native (pacman) | 3030 |
| Node Exporter | Arch_Server | Native (pacman) | 9100 |
| Podman Exporter (rootless) | Arch_Server | Quadlet container | 9882 |
| Podman Exporter (rootful) | Arch_Server | Quadlet container | 9883 |
| Node Exporter | Raspberry Pi | Native (apt) | 9100 |
| AdGuard Exporter | Raspberry Pi | Docker container | 9618 |

---

## Prerequisites

**Arch_Server:**
```bash
sudo pacman -S prometheus grafana prometheus-node-exporter
```

**Raspberry Pi:**
```bash
sudo apt install prometheus-node-exporter
```

---

## Installation

### 1. Podman Exporters (Arch_Server)

**Rootless** — copy to `~/.config/containers/systemd/`:
```bash
cp Arch_Server/containers/podman-exporter.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start podman-exporter
```

**Rootful** — copy to `/etc/containers/systemd/`:
```bash
sudo cp Arch_Server/containers/podman-exporter-rootful.container /etc/containers/systemd/
sudo systemctl daemon-reload
sudo systemctl start podman-exporter-rootful
```

Note: Quadlets are auto-started by the systemd generator — do not use `systemctl enable`.

Verify:
```bash
curl -s http://localhost:9882/metrics | head -5   # rootless
curl -s http://localhost:9883/metrics | head -5   # rootful
```

### 2. Prometheus (Arch_Server)

Copy config and replace placeholders:
```bash
sudo cp Arch_Server/config/prometheus.yml /etc/prometheus/prometheus.yml
# Edit <raspberrypi-ip> with your actual Pi IP
sudo nano /etc/prometheus/prometheus.yml
sudo promtool check config /etc/prometheus/prometheus.yml
sudo systemctl enable --now prometheus
```

### 3. Node Exporter — systemd collector (Arch_Server)

```bash
sudo cp Arch_Server/config/node-exporter.conf /etc/conf.d/prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

### 4. Grafana (Arch_Server)

```bash
sudo cp Arch_Server/config/grafana.ini.example /etc/grafana.ini
# Edit domain and port as needed
sudo nano /etc/grafana.ini
sudo systemctl enable --now grafana
```

Then open Grafana in a browser and:
- Add Prometheus as a data source: `http://localhost:9090`
- Import dashboards (see below)

### 5. Node Exporter (Raspberry Pi)

```bash
sudo apt install prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

### 6. AdGuard Exporter (Raspberry Pi)

```bash
# Edit placeholders first
nano raspberrypi/docker/adguard-exporter-run.sh
bash raspberrypi/docker/adguard-exporter-run.sh
```

Verify:
```bash
curl -s http://localhost:9618/metrics | head -5
```

---

## Grafana Dashboards

| Dashboard | ID | Purpose |
|-----------|----|---------|
| Podman Exporter | 20162 | Container metrics |
| Node Exporter Full | 1860 | Host metrics (Arch_Server + Pi) |
| AdGuard Home | 20799 | DNS query stats |

Import via: Dashboards → New → Import → enter ID → Load → select Prometheus data source.

For the Node Exporter Full dashboard, type `rpi-node` in the Job dropdown to switch to the Raspberry Pi view.

---

## Alerts

All alert rules are configured in Grafana under folder **Podman**, group **Container Alerts**, with Telegram as the contact point.

| Alert | Query | Threshold |
|-------|-------|-----------|
| Container Down | `podman_container_state == 5 * on(id) group_left(name) podman_container_info` | Any exited container |
| High Memory | `(podman_container_mem_usage_bytes / podman_container_mem_limit_bytes) * 100` | > 80%, pending 8m |
| Low Disk Space | `(node_filesystem_avail_bytes{fstype!="tmpfs",mountpoint!="/boot"} / node_filesystem_size_bytes{fstype!="tmpfs",mountpoint!="/boot"}) * 100` | < 20% |
| High CPU Load | `node_load15` | > 12 (75% of 16 cores) |
| High Disk I/O | `rate(node_disk_io_time_seconds_total[5m])` | > 0.9 |
| Low System Memory | `(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | < 10% |
| High Swap Usage | `(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100` | > 50% |
| AdGuard Down | `adguard_running` | == 0 |
| AdGuard Protection Disabled | `adguard_protection_enabled` | == 0 |
| AdGuard Slow Upstream | `adguard_avg_processing_time_seconds` | > 0.5 |
| AdGuard Scrape Errors | `rate(adguard_scrape_errors_total[5m])` | > 0 |

All rules: No data = Normal, Error = Normal, Pending period = 2m (except High Memory = 8m).

---

## Known Issues

- **High Memory false positives on startup:** Containers like qBittorrent spike memory briefly after a reboot. The High Memory alert uses an 8m pending period to avoid this.
- **Container ID changes:** Every time a container is recreated it gets a new ID. Historical Prometheus queries must use `name` not `id`.
- **Raspberry Pi /boot partition:** Always nearly full by design — excluded from Low Disk Space alert with `mountpoint!="/boot"`.

---

## Verifying All Targets

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"job"|"health"'
```

Expected output: all 6 jobs showing `"health": "up"` — prometheus, podman-rootless, podman-rootful, node, rpi-node, adguard.

#!/bin/bash
# Run the AdGuard Home Prometheus exporter on the Raspberry Pi
# AdGuard is expected to be running on a macvlan adapter with its own IP
# Replace placeholders before running

docker run -d \
  --name adguard-exporter \
  --restart unless-stopped \
  -e 'ADGUARD_SERVERS=http://<adguard-ip>' \
  -e 'ADGUARD_USERNAMES=<adguard-username>' \
  -e 'ADGUARD_PASSWORDS=<adguard-password>' \
  -e 'INTERVAL=15s' \
  -p 9618:9618 \
  ghcr.io/henrywhitaker3/adguard-exporter:latest

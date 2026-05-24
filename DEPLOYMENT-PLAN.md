# Deployment Plan: Local First to VPS

This project is designed to start as a local automation stack and move to a VPS later with minimal changes.

## Current Target: Local Development

Use this mode while building flows, testing MQTT telemetry, connecting n8n credentials, and designing dashboards.

Local services:

| Service | Local access | Role |
| --- | --- | --- |
| Node-RED | `http://localhost:1880` | Flow editor and MQTT/OPC automation |
| n8n | `http://localhost:5678` | Workflow automation |
| Mosquitto | `localhost:1883`, `localhost:9001` | MQTT broker |
| InfluxDB | `http://localhost:8086` | Time-series telemetry database |
| Grafana | `http://localhost:3000` | Dashboards |
| PostgreSQL | Docker internal `postgres:5432` | Operational DB for n8n and Grafana |
| ngrok | `http://localhost:4040` | Public HTTPS tunnel for n8n webhooks/OAuth |

Local rules:

- Keep `.env` out of Git.
- Use Docker service names inside containers: `mosquitto`, `influxdb`, `postgres`, `n8n`, `nodered`.
- Use `localhost` only from the host machine.
- Keep PostgreSQL and InfluxDB ports private in practice. They are exposed now for local development convenience.
- Use ngrok only for local webhook/OAuth testing.

## Future Target: VPS

Recommended VPS shape:

- Ubuntu LTS
- Docker Engine + Docker Compose plugin
- 2 vCPU minimum, 4 vCPU preferred
- 4 GB RAM minimum, 8 GB preferred
- 40 GB SSD minimum, more if telemetry retention is long
- Domain name, for example:
  - `n8n.example.com`
  - `grafana.example.com`
  - `node-red.example.com`
  - optional: `influxdb.example.com` only if explicitly needed

## VPS Architecture

On VPS, replace ngrok with a reverse proxy and real HTTPS.

Recommended production-facing services:

| Public endpoint | Internal target | Notes |
| --- | --- | --- |
| `https://n8n.example.com` | `n8n:5678` | Required for webhooks and OAuth callbacks |
| `https://grafana.example.com` | `grafana:3000` | Dashboard access |
| `https://node-red.example.com` | `nodered:1880` | Only if secured with auth |

Keep these internal only unless there is a specific need:

- PostgreSQL: `postgres:5432`
- InfluxDB: `influxdb:8086`
- Mosquitto: `mosquitto:1883`

## Compose Strategy

Keep the current `docker-compose.yml` as the base stack.

Recommended future files:

- `docker-compose.override.yml` for local-only settings.
- `docker-compose.vps.yml` for VPS-specific settings.
- `.env.local` for local secrets.
- `.env.vps` for VPS secrets.

Suggested VPS changes:

- Disable or profile-gate `ngrok`.
- Add `caddy` or `traefik` as reverse proxy.
- Remove public port mappings for databases.
- Enable Node-RED admin authentication.
- Add Mosquitto username/password if MQTT is exposed outside the VPS.
- Set n8n URLs to the real domain:
  - `NGROK_URL` should eventually be replaced by a neutral public URL variable such as `N8N_PUBLIC_URL`.
  - `WEBHOOK_URL=https://n8n.example.com/`
  - `N8N_EDITOR_BASE_URL=https://n8n.example.com/`

## Security Plan

Before VPS deployment:

- Turn on Node-RED `adminAuth`.
- Change all default passwords and tokens.
- Use separate passwords for:
  - PostgreSQL superuser
  - n8n PostgreSQL user
  - Grafana PostgreSQL user
  - Grafana admin
  - InfluxDB admin/token
- Do not expose PostgreSQL publicly.
- Do not expose InfluxDB publicly unless protected by network rules and strong auth.
- Restrict SSH with key-based login.
- Enable firewall rules:
  - allow `22/tcp` for SSH
  - allow `80/tcp` and `443/tcp` for reverse proxy
  - optionally allow MQTT only from known IPs
- Back up `.env.vps` securely outside the VPS.

## Backup Plan

Back up these volumes/data regularly:

- PostgreSQL: n8n and Grafana operational data
- InfluxDB: telemetry history
- Node-RED: flows and installed nodes
- Grafana provisioning and dashboards
- Mosquitto persistence if retained MQTT messages matter

Minimum practical backup:

```bash
docker compose exec postgres pg_dumpall -U postgres > backup-postgres.sql
docker compose exec influxdb influx backup /tmp/influxdb-backup
docker cp influxdb:/tmp/influxdb-backup ./backup-influxdb
```

For production, automate backups daily and test restore at least once.

## Migration Path

1. Finish local stack and flows.
2. Freeze `.env.example` as template and create `.env.vps` privately.
3. Add reverse proxy compose file.
4. Replace ngrok public URLs with real VPS domain URLs.
5. Enable Node-RED authentication.
6. Start VPS stack.
7. Import n8n workflows and Node-RED flows.
8. Verify:
   - n8n webhook URL
   - Google OAuth callback URL
   - Grafana InfluxDB datasource
   - Node-RED to InfluxDB write path
   - MQTT ingress path
9. Configure backups.
10. Only then point real devices/production data to the VPS.

## Recommended Next Implementation Step

Add `N8N_PUBLIC_URL` as a neutral variable and keep `NGROK_URL` as a local-only alias during transition. This will make the compose file read naturally in both local and VPS modes.

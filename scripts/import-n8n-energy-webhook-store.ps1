$ErrorActionPreference = 'Stop'

# Personal project ID from existing workflows in this n8n instance
$projectId = 'W2c0RfXLXsYRtHuM'

# Import workflow
& docker exec n8n n8n import:workflow --input=/tmp/n8n-energy-webhook-store.json --projectId=$projectId | Out-Host

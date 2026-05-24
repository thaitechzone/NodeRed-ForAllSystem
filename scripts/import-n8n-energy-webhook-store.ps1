$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repoRoot 'flows\n8n-workflow1-collector.json'
$containerPath = '/tmp/n8n-workflow1-collector.json'

& docker cp $workflowPath "n8n:$containerPath" | Out-Host

$dockerArgs = @('exec', 'n8n', 'n8n', 'import:workflow', "--input=$containerPath")
if ($env:N8N_PROJECT_ID) {
    $dockerArgs += "--projectId=$env:N8N_PROJECT_ID"
}

& docker @dockerArgs | Out-Host

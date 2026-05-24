$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:1880'
$repoRoot = Split-Path -Parent $PSScriptRoot
$newFlowPath = Join-Path $repoRoot 'flows\NodeRED flowsEnergy Test N8N.json'

$current = Invoke-RestMethod -Method Get -Uri "$baseUrl/flows"
$newNodes = Get-Content -Raw -Path $newFlowPath | ConvertFrom-Json

$tabId = 'tab_energy_test'
$existing = @($current)
$withoutSimulator = $existing | Where-Object { $_.id -ne $tabId -and $_.z -ne $tabId }
$merged = @($withoutSimulator + $newNodes)

$body = $merged | ConvertTo-Json -Depth 100
Invoke-RestMethod -Method Post -Uri "$baseUrl/flows" -ContentType 'application/json' -Body $body | Out-Null
Write-Output 'Imported Energy Test to N8N flow successfully.'

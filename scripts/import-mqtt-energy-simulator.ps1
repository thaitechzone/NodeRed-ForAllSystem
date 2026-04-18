$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:1880'
$newFlowPath = 'D:\NodeRed\flows\mqtt-energy-machine-simulator.json'

$current = Invoke-RestMethod -Method Get -Uri "$baseUrl/flows"
$newNodes = Get-Content -Raw -Path $newFlowPath | ConvertFrom-Json

$tabId = 'c2d7a83f5e764101'
$existing = @($current)
$withoutSimulator = $existing | Where-Object { $_.id -ne $tabId -and $_.z -ne $tabId }
$merged = @($withoutSimulator + $newNodes)

$body = $merged | ConvertTo-Json -Depth 100
Invoke-RestMethod -Method Post -Uri "$baseUrl/flows" -ContentType 'application/json' -Body $body | Out-Null
Write-Output 'Imported MQTT Energy Machine Simulator flow successfully.'

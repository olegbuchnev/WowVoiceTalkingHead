# Copy this file to build.env.local.ps1 (ignored by Git) and set your AddOns path.
# Loaded automatically by Deploy/DeployAddon in the build process only.
# Values here override inherited environment variables; no system settings change.
$env:WOWVOICE_FOREVER_BETA_ADDONS = 'D:\ExampleWoW\_classic_beta_\Interface\AddOns'
# Set to '1' to keep the /tt test harness in every local Deploy/DeployAddon.
# Release packages never include the harness. -QueueLab:$false disables it once.
$env:WOWVOICE_QUEUE_LAB = '0'

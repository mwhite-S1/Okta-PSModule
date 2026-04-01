#Requires -Modules Pester
<#
.SYNOPSIS
    End-to-end write tests for Group Push Mapping functions against the 'prev' preview org.
.DESCRIPTION
    Creates a disposable Okta group, creates a push mapping to an app that has provisioning
    enabled, exercises all operations, then cleans up.

    Prerequisites:
      1. okta_org.ps1 must exist in the project root with a 'prev' entry.
      2. The 'prev' API token must be active with App and Group write permissions.
      3. TestConfig.psd1 must have a PushEnabledAppId value pointing to an app
         that has provisioning (Group Push) enabled.  If that key is absent or blank
         the entire suite is skipped gracefully.

    Run with:
      Invoke-Pester .\tests\GroupPush.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $projectRoot = Split-Path $PSScriptRoot -Parent

    $orgConfig = Join-Path $projectRoot 'okta_org.ps1'
    if (-not (Test-Path $orgConfig)) {
        throw "okta_org.ps1 not found at $orgConfig - cannot run integration tests."
    }
    . $orgConfig

    $Global:oktaOrgs    = $oktaOrgs
    $Global:oktaDefOrg  = $oktaDefOrg
    $Global:oktaVerbose = $false

    $cfg = & ([scriptblock]::Create((Get-Content (Join-Path $PSScriptRoot 'TestConfig.psd1') -Raw)))
    $Script:org   = $cfg.OrgAlias
    $Script:aid   = $cfg.PushEnabledAppId   # may be $null if not configured

    $Global:oktaOrgs[$Script:org]['enablePagination'] = $false

    $modulePath = Join-Path $projectRoot 'Okta.psm1'
    Import-Module $modulePath -Force

    # Skip everything if no push-enabled app is configured
    if (-not $Script:aid) {
        Write-Warning 'PushEnabledAppId not set in TestConfig.psd1 - all GroupPush tests will be skipped.'
        $Script:skipAll = $true
        return
    }
    $Script:skipAll = $false

    # Create a disposable source group for the push mapping
    $groupName = 'Pester-PushGroup-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $Script:testGroup = oktaCreateGroup -oOrg $Script:org -name $groupName `
                                        -description 'Temporary group created by Pester GroupPush tests'
    if (-not $Script:testGroup -or -not $Script:testGroup.id) {
        throw "BeforeAll: failed to create test group '$groupName'."
    }
    $Script:testGroupId = $Script:testGroup.id

    # Create the push mapping  -  let Okta create the target group by name
    $targetName = 'Pester-PushTarget-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $Script:testMapping = oktaCreateGroupPushMapping -oOrg $Script:org `
                                                     -appId $Script:aid `
                                                     -sourceGroupId $Script:testGroupId `
                                                     -targetGroupName $targetName `
                                                     -status ACTIVE
    if (-not $Script:testMapping -or -not $Script:testMapping.id) {
        oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:testGroupId -ErrorAction SilentlyContinue
        throw "BeforeAll: failed to create push mapping."
    }
    $Script:testMappingId = $Script:testMapping.id
    $Script:targetGroupId = $Script:testMapping.targetGroupId  # auto-created by Okta; cleaned up in AfterAll
}

# ---------------------------------------------------------------------------
# Validate input guards on oktaCreateGroupPushMapping
# ---------------------------------------------------------------------------
Describe 'oktaCreateGroupPushMapping  -  parameter validation' {

    It 'Throws when both targetGroupId and targetGroupName are supplied' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        {
            oktaCreateGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                -sourceGroupId $Script:testGroupId `
                -targetGroupId 'dummy' -targetGroupName 'dummy'
        } | Should -Throw
    }

    It 'Throws when neither targetGroupId nor targetGroupName is supplied' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        {
            oktaCreateGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                -sourceGroupId $Script:testGroupId
        } | Should -Throw
    }
}

# ---------------------------------------------------------------------------
# Get mapping by ID
# ---------------------------------------------------------------------------
Describe 'oktaGetGroupPushMapping  -  fetch the newly created mapping' {

    It 'Returns the correct mapping object' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaGetGroupPushMapping -oOrg $Script:org -appId $Script:aid -mappingId $Script:testMappingId
        $result            | Should -Not -BeNullOrEmpty
        $result.id  | Should -Be $Script:testMappingId
    }

    It 'Mapping status is ACTIVE' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaGetGroupPushMapping -oOrg $Script:org -appId $Script:aid -mappingId $Script:testMappingId
        $result.status | Should -Be 'ACTIVE'
    }
}

# ---------------------------------------------------------------------------
# List mappings  -  verify ours appears
# ---------------------------------------------------------------------------
Describe 'oktaListGroupPushMappings  -  new mapping appears in list' {

    It 'Returns at least one mapping' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaListGroupPushMappings -oOrg $Script:org -appId $Script:aid -limit 200
        $result | Should -Not -BeNullOrEmpty
    }

    It 'Test mapping ID appears in the list' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaListGroupPushMappings -oOrg $Script:org -appId $Script:aid -limit 200
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Contain $Script:testMappingId
    }
}

# ---------------------------------------------------------------------------
# Update mapping status
# ---------------------------------------------------------------------------
Describe 'oktaUpdateGroupPushMapping  -  deactivate then reactivate' {

    It 'Deactivates the mapping without error' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        { $null = oktaUpdateGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                      -mappingId $Script:testMappingId -status INACTIVE } | Should -Not -Throw
    }

    It 'Mapping status is INACTIVE after update' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaGetGroupPushMapping -oOrg $Script:org -appId $Script:aid -mappingId $Script:testMappingId
        $result.status | Should -Be 'INACTIVE'
    }

    It 'Reactivates the mapping without error' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        { $null = oktaUpdateGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                      -mappingId $Script:testMappingId -status ACTIVE } | Should -Not -Throw
    }

    It 'Mapping status is ACTIVE after reactivation' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaGetGroupPushMapping -oOrg $Script:org -appId $Script:aid -mappingId $Script:testMappingId
        $result.status | Should -Be 'ACTIVE'
    }
}

# ---------------------------------------------------------------------------
# Internal trigger endpoint
# ---------------------------------------------------------------------------
Describe 'oktaTriggerGroupPush  -  internal trigger (undocumented endpoint)' {

    It 'Does not throw when triggering an ACTIVE push' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        { $null = oktaTriggerGroupPush -oOrg $Script:org -appId $Script:aid `
                      -mappingId $Script:testMappingId -status ACTIVE } | Should -Not -Throw
    }
}

# ---------------------------------------------------------------------------
# Delete mapping  -  must be INACTIVE first
# ---------------------------------------------------------------------------
Describe 'oktaDeleteGroupPushMapping  -  deactivate then remove the mapping' {

    It 'Deactivates the mapping before deletion' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        { $null = oktaUpdateGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                      -mappingId $Script:testMappingId -status INACTIVE } | Should -Not -Throw
    }

    It 'Deletes without error' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        { $null = oktaDeleteGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                      -mappingId $Script:testMappingId } | Should -Not -Throw
        $Script:testMappingId = $null   # mark cleaned up
    }

    It 'Mapping no longer appears in list after deletion' {
        if ($Script:skipAll) { Set-ItResult -Skipped -Because 'PushEnabledAppId not configured' }
        $result = oktaListGroupPushMappings -oOrg $Script:org -appId $Script:aid -limit 200
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Not -Contain $Script:testMappingId
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
AfterAll {
    if ($Script:testMappingId) {
        try   { oktaDeleteGroupPushMapping -oOrg $Script:org -appId $Script:aid `
                    -mappingId $Script:testMappingId | Out-Null }
        catch { Write-Warning "AfterAll: could not delete push mapping $($Script:testMappingId): $_" }
    }
    if ($Script:testGroupId) {
        try   { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:testGroupId | Out-Null }
        catch { Write-Warning "AfterAll: could not delete test group $($Script:testGroupId): $_" }
    }
    if ($Script:targetGroupId) {
        try   { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:targetGroupId | Out-Null }
        catch { Write-Warning "AfterAll: could not delete auto-created target group $($Script:targetGroupId): $_" }
    }
    Remove-Module Okta -ErrorAction SilentlyContinue
}

#Requires -Modules Pester
<#
.SYNOPSIS
    End-to-end write tests for Group Rule functions against the 'prev' preview org.
.DESCRIPTION
    Creates a disposable group and group rule, exercises all CRUD and lifecycle
    operations, then cleans up both resources.

    Operation order:
      1. BeforeAll  - create group, create rule (INACTIVE)
      2. Get rule by ID
      3. List rules (verify ours appears)
      4. Update rule name  (must be INACTIVE)
      5. Activate rule
      6. Deactivate rule   (must be INACTIVE again before delete)
      7. AfterAll   - delete rule, delete group

    Prerequisites:
      1. okta_org.ps1 must exist in the project root with a 'prev' entry.
      2. The 'prev' API token must be active with Group and GroupRule write permissions.
      3. TestConfig.psd1 must have valid fixture values.

    Run with:
      Invoke-Pester .\tests\GroupRule.Tests.ps1 -Output Detailed
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
    $Script:org    = $cfg.OrgAlias
    $Script:ulogin = $cfg.KnownUserLogin
    $Script:gid    = $cfg.KnownGroupId   # existing group used as the assignment target

    $Global:oktaOrgs[$Script:org]['enablePagination'] = $false

    $modulePath = Join-Path $projectRoot 'Okta.psm1'
    Import-Module $modulePath -Force

    # --- Create disposable test group ---
    $groupName = 'Pester-GroupRule-Test-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $Script:testGroup = oktaCreateGroup -oOrg $Script:org -name $groupName -description 'Temporary group created by Pester GroupRule tests'
    if (-not $Script:testGroup -or -not $Script:testGroup.id) {
        throw "BeforeAll: failed to create test group '$groupName'."
    }
    $Script:testGroupId = $Script:testGroup.id

    # --- Create disposable test rule targeting the new group ---
    # Expression: match the known fixture user by login so the rule is valid but low-blast-radius
    $ruleName = 'Pester-Rule-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $expr     = 'user.login == "' + $Script:ulogin + '"'
    $Script:testRule = oktaCreateGroupRule -oOrg $Script:org `
                                           -name $ruleName `
                                           -expression $expr `
                                           -groupIds @($Script:testGroupId)
    if (-not $Script:testRule -or -not $Script:testRule.id) {
        # Clean up the group before failing
        oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:testGroupId -ErrorAction SilentlyContinue
        throw "BeforeAll: failed to create test group rule '$ruleName'."
    }
    $Script:testRuleId   = $Script:testRule.id
    $Script:testRuleName = $ruleName
}

# ---------------------------------------------------------------------------
# Get rule by ID
# ---------------------------------------------------------------------------
Describe 'oktaGetGroupRuleById  -  fetch the newly created rule' {

    It 'Returns the correct rule object' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result                | Should -Not -BeNullOrEmpty
        $result.id             | Should -Be $Script:testRuleId
        $result.name           | Should -Be $Script:testRuleName
    }

    It 'Rule is created in INACTIVE status' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.status | Should -Be 'INACTIVE'
    }

    It 'Rule conditions contain the expected expression' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.conditions.expression.value | Should -BeLike ('*' + $Script:ulogin + '*')
    }

    It 'Rule actions target the test group' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.actions.assignUserToGroups.groupIds | Should -Contain $Script:testGroupId
    }
}

# ---------------------------------------------------------------------------
# List rules - verify ours appears
# ---------------------------------------------------------------------------
Describe 'oktaListGroupRules  -  new rule appears in list' {

    It 'Returns at least one rule' {
        $result = oktaListGroupRules -oOrg $Script:org -limit 200
        $result | Should -Not -BeNullOrEmpty
    }

    It 'The test rule ID appears in the list' {
        $result = oktaListGroupRules -oOrg $Script:org -limit 200
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Contain $Script:testRuleId
    }
}

# ---------------------------------------------------------------------------
# Update rule name (rule must be INACTIVE)
# ---------------------------------------------------------------------------
Describe 'oktaUpdateGroupRule  -  rename the rule while INACTIVE' {

    It 'Does not throw' {
        $newName = $Script:testRuleName + '-updated'
        { $Script:updatedRule = oktaUpdateGroupRule -oOrg $Script:org -ruleId $Script:testRuleId -name $newName } |
            Should -Not -Throw
    }

    It 'Returned rule reflects the new name' {
        $newName = $Script:testRuleName + '-updated'
        $result  = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.name | Should -Be $newName
    }
}

# ---------------------------------------------------------------------------
# Activate rule
# ---------------------------------------------------------------------------
Describe 'oktaActivateGroupRule  -  activate the rule' {

    It 'Does not throw' {
        { $null = oktaActivateGroupRule -oOrg $Script:org -ruleId $Script:testRuleId } |
            Should -Not -Throw
    }

    It 'Rule status is ACTIVE after activation' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.status | Should -Be 'ACTIVE'
    }
}

# ---------------------------------------------------------------------------
# Deactivate rule (required before delete)
# ---------------------------------------------------------------------------
Describe 'oktaDeactivateGroupRule  -  deactivate the rule' {

    It 'Does not throw' {
        { $null = oktaDeactivateGroupRule -oOrg $Script:org -ruleId $Script:testRuleId } |
            Should -Not -Throw
    }

    It 'Rule status is INACTIVE after deactivation' {
        $result = oktaGetGroupRuleById -oOrg $Script:org -ruleId $Script:testRuleId
        $result.status | Should -Be 'INACTIVE'
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
AfterAll {
    # Delete the test rule first (must be INACTIVE - deactivated above)
    if ($Script:testRuleId) {
        try   { oktaDeleteGroupRule  -oOrg $Script:org -ruleId $Script:testRuleId  | Out-Null }
        catch { Write-Warning "AfterAll: could not delete test rule $($Script:testRuleId): $_" }
    }

    # Delete the test group
    if ($Script:testGroupId) {
        try   { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:testGroupId | Out-Null }
        catch { Write-Warning "AfterAll: could not delete test group $($Script:testGroupId): $_" }
    }

    Remove-Module Okta -ErrorAction SilentlyContinue
}

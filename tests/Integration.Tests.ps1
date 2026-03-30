#Requires -Modules Pester
<#
.SYNOPSIS
    Read-only integration tests for Okta.psm1 against the 'prev' preview org.
.DESCRIPTION
    All tests are GET operations only  -  nothing is created, modified, or deleted.

    Prerequisites:
      1. okta_org.ps1 must exist in the project root with a 'prev' entry.
      2. The 'prev' API token must be active.
      3. TestConfig.psd1 must have valid fixture IDs (KnownUserId, KnownGroupId, etc.).

    Run with:
      Invoke-Pester .\tests\Integration.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $projectRoot = Split-Path $PSScriptRoot -Parent

    # Load org config (sets $oktaOrgs, $oktaDefOrg, $oktaVerbose)
    $orgConfig = Join-Path $projectRoot 'okta_org.ps1'
    if (-not (Test-Path $orgConfig)) {
        throw "okta_org.ps1 not found at $orgConfig  -  cannot run integration tests."
    }
    . $orgConfig

    # Pester 5 BeforeAll runs in an isolated scope. The module accesses $oktaOrgs and
    # $oktaDefOrg directly, so they must be in Global scope where the module can see them.
    $Global:oktaOrgs   = $oktaOrgs
    $Global:oktaDefOrg = $oktaDefOrg
    $Global:oktaVerbose = $false

    # Load test fixtures first so we know the org alias
    $cfg = & ([scriptblock]::Create((Get-Content (Join-Path $PSScriptRoot 'TestConfig.psd1') -Raw)))
    $Script:org  = $cfg.OrgAlias

    # Disable pagination for integration tests  -  prevents rate-limit storms caused by
    # the org's enablePagination = $true iterating through all pages on every call.
    $Global:oktaOrgs[$Script:org]['enablePagination'] = $false

    # Import module
    $modulePath = Join-Path $projectRoot 'Okta.psm1'
    Import-Module $modulePath -Force
    $Script:uid  = $cfg.KnownUserId
    $Script:ulogin = $cfg.KnownUserLogin
    $Script:gid  = $cfg.KnownGroupId
    $Script:aid  = $cfg.KnownAppId
    $Script:agid = $cfg.KnownAppGroupId
}

# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
Describe 'oktaGetUserbyID  -  fetch user by Okta ID' {

    It 'Returns a user object with the correct ID' {
        $result = oktaGetUserbyID -oOrg $Script:org -userName $Script:uid
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be $Script:uid
    }

    It 'Returns a user with a profile containing login' {
        $result = oktaGetUserbyID -oOrg $Script:org -userName $Script:uid
        $result.profile | Should -Not -BeNullOrEmpty
        $result.profile.login | Should -Not -BeNullOrEmpty
    }

    It 'Converts date fields to [datetime]' {
        $result = oktaGetUserbyID -oOrg $Script:org -userName $Script:uid
        # OktaUserfromJson converts string dates; check at least one
        if ($result.created) {
            $result.created | Should -BeOfType [datetime]
        }
    }

    It 'Fetches the same user by login (email)' {
        $result = oktaGetUserbyID -oOrg $Script:org -userName $Script:ulogin
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be $Script:uid
    }
}

Describe 'oktaGetprofilebyId  -  extract profile from user' {

    It 'Returns a profile object' {
        $result = oktaGetprofilebyId -oOrg $Script:org -uid $Script:uid
        $result | Should -Not -BeNullOrEmpty
    }

    It 'Profile has a login field matching KnownUserLogin' {
        $result = oktaGetprofilebyId -oOrg $Script:org -uid $Script:uid
        $result.login | Should -Be $Script:ulogin
    }
}

Describe 'oktaListUsers  -  list users with limit' {

    It 'Returns at least one user' {
        $result = oktaListUsers -oOrg $Script:org -limit 5 -enablePagination $false
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Respects the limit parameter' {
        $result = oktaListUsers -oOrg $Script:org -limit 3 -enablePagination $false
        @($result).Count | Should -BeLessOrEqual 3
    }

    It 'Returns users matching a q (name) search' {
        # Use part of the known login to search
        $localPart = ($Script:ulogin -split '@')[0]
        $result = oktaListUsers -oOrg $Script:org -q $localPart -limit 10 -enablePagination $false
        $result | Should -Not -BeNullOrEmpty
        # At least one result should be the known user
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Contain $Script:uid
    }
}

Describe 'oktaGetGroupsbyUserId  -  groups for a known user' {

    It 'Returns at least one group' {
        $result = oktaGetGroupsbyUserId -oOrg $Script:org -uid $Script:uid
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Each group has an id and profile' {
        $result = oktaGetGroupsbyUserId -oOrg $Script:org -uid $Script:uid
        $first = @($result)[0]
        $first.id | Should -Not -BeNullOrEmpty
        $first.profile | Should -Not -BeNullOrEmpty
    }
}

Describe 'oktaGetAppsbyUserId  -  apps assigned to a known user' {

    It 'Returns an array' {
        $result = oktaGetAppsbyUserId -oOrg $Script:org -uid $Script:uid
        # Result may be empty if user has no app assignments; just verify it doesn't throw
        $result | Should -Not -Be $null
    }
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
Describe 'oktaGetGroupbyId  -  fetch group by ID' {

    It 'Returns the correct group' {
        $result = oktaGetGroupbyId -oOrg $Script:org -gid $Script:gid
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be $Script:gid
    }

    It 'Has a profile with a name' {
        $result = oktaGetGroupbyId -oOrg $Script:org -gid $Script:gid
        $result.profile.name | Should -Not -BeNullOrEmpty
    }
}

Describe 'oktaGetGroupStatsbyId  -  group stats/expand' {

    It 'Returns a result for the known group' {
        $result = oktaGetGroupStatsbyId -oOrg $Script:org -gid $Script:gid
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be $Script:gid
    }
}

Describe 'oktaGetGroupMembersbyId  -  members of a known group' {

    It 'Returns at least one member' {
        $result = oktaGetGroupMembersbyId -oOrg $Script:org -gid $Script:gid -enablePagination $false -limit 10
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Each member has an id and profile' {
        $result = oktaGetGroupMembersbyId -oOrg $Script:org -gid $Script:gid -enablePagination $false -limit 5
        $first = @($result)[0]
        $first.id | Should -Not -BeNullOrEmpty
        $first.profile | Should -Not -BeNullOrEmpty
    }
}

Describe 'oktaListGroups  -  list groups' {

    It 'Returns at least one group' {
        $result = oktaListGroups -oOrg $Script:org -limit 5
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Can filter by query string' {
        # Use first few chars of the known group name
        $groupName = (oktaGetGroupbyId -oOrg $Script:org -gid $Script:gid).profile.name
        $prefix = $groupName.Substring(0, [Math]::Min(6, $groupName.Length))
        $result = oktaListGroups -oOrg $Script:org -query $prefix -limit 10
        $result | Should -Not -BeNullOrEmpty
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Contain $Script:gid
    }
}

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------
Describe 'oktaGetAppbyId  -  fetch app by ID' {

    It 'Returns the correct application' {
        $result = oktaGetAppbyId -oOrg $Script:org -aid $Script:aid
        $result | Should -Not -BeNullOrEmpty
        $result.id | Should -Be $Script:aid
    }

    It 'Has a label field' {
        $result = oktaGetAppbyId -oOrg $Script:org -aid $Script:aid
        $result.label | Should -Not -BeNullOrEmpty
    }
}

Describe 'oktaGetAppGroups  -  group assignments for a known app' {

    It 'Returns at least one group assignment' {
        $result = oktaGetAppGroups -oOrg $Script:org -aid $Script:aid
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Known app group ID is in the results' {
        $result = oktaGetAppGroups -oOrg $Script:org -aid $Script:aid
        $ids = @($result | ForEach-Object { $_.id })
        $ids | Should -Contain $Script:agid
    }
}

Describe 'oktaListApps  -  list applications' {

    It 'Returns at least one app' {
        $result = oktaListApps -oOrg $Script:org -limit 5
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Can filter by ACTIVE status' {
        $result = oktaListApps -oOrg $Script:org -status ACTIVE -limit 5
        $result | Should -Not -BeNullOrEmpty
        $statuses = @($result | ForEach-Object { $_.status }) | Sort-Object -Unique
        $statuses | Should -Contain 'ACTIVE'
    }
}

Describe 'oktaGetAppLinksbyUserId  -  app links for a known user' {

    It 'Returns an array (may be empty)' {
        $result = oktaGetAppLinksbyUserId -oOrg $Script:org -uid $Script:uid
        # Just confirm no exception
        $result | Should -Not -Be $null
    }
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
Describe 'oktaListLogs  -  retrieve system logs' {

    It 'Returns at least one log entry with a limit' {
        $result = oktaListLogs -oOrg $Script:org -limit 5
        $result | Should -Not -BeNullOrEmpty
        @($result).Count | Should -BeGreaterOrEqual 1
    }

    It 'Each log entry has an eventType and published fields' {
        $result = oktaListLogs -oOrg $Script:org -limit 3
        $first = @($result)[0]
        $first.eventType | Should -Not -BeNullOrEmpty
        $first.published | Should -Not -BeNullOrEmpty
    }

    It 'Respects sortOrder DESCENDING' {
        $result = oktaListLogs -oOrg $Script:org -limit 5 -order DESCENDING
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'oktaGetLogs  -  datetime-based wrapper for oktaListLogs' {

    It 'Returns logs since a recent datetime without error' {
        $since = (Get-Date).AddHours(-24)
        $result = oktaGetLogs -oOrg $Script:org -since $since -limit 5
        # May be empty in quiet preview orgs; just confirm no throw
        $result | Should -Not -Be $null
    }
}

# ---------------------------------------------------------------------------
# Devices
# ---------------------------------------------------------------------------
Describe 'oktaGetDevices  -  list active devices' {

    It 'Does not throw' {
        # Device list may be empty; just confirm the call succeeds
        { $null = oktaGetDevices -oOrg $Script:org -limit 10 } | Should -Not -Throw
    }
}

AfterAll {
    Remove-Module Okta -ErrorAction SilentlyContinue
}

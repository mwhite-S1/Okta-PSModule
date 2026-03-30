#Requires -Modules Pester
<#
.SYNOPSIS
    Write (mutating) integration tests for Okta.psm1 against the 'prev' preview org.
.DESCRIPTION
    Tests create, update, and delete operations. Lifecycle:
      1. BeforeAll   -  creates a STAGED test user and two test groups
      2. Tests       -  exercise lifecycle, profile, group membership, and status functions
      3. AfterAll    -  deactivates and deletes the test user; deletes the test groups

    Prerequisites: same as Integration.Tests.ps1 (okta_org.ps1, TestConfig.psd1, active prev token).

    Run with:
      Invoke-Pester .\tests\Write-Integration.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $projectRoot = Split-Path $PSScriptRoot -Parent

    $orgConfig = Join-Path $projectRoot 'okta_org.ps1'
    if (-not (Test-Path $orgConfig)) { throw "okta_org.ps1 not found." }
    . $orgConfig

    $Global:oktaOrgs   = $oktaOrgs
    $Global:oktaDefOrg = $oktaDefOrg
    $Global:oktaVerbose = $false
    $cfg = & ([scriptblock]::Create((Get-Content (Join-Path $PSScriptRoot 'TestConfig.psd1') -Raw)))
    $Script:org = $cfg.OrgAlias
    $Global:oktaOrgs[$Script:org]['enablePagination'] = $false

    Import-Module (Join-Path $projectRoot 'Okta.psm1') -Force

    # ── unique suffix so nothing collides with existing data ──────────────
    $Script:suffix    = (Get-Random -Maximum 99999).ToString('D5')
    $Script:userLogin = "pester.write.$($Script:suffix)@test.sentinelone.dev"
    $Script:groupNameA = "Pester-Write-A-$($Script:suffix)"
    $Script:groupNameB = "Pester-Write-B-$($Script:suffix)"

    # Guard: abort if names already exist (extremely unlikely but safe)
    $existing = oktaListGroups -oOrg $Script:org -query "Pester-Write-$($Script:suffix)" -limit 5
    if (@($existing).Count -gt 0) {
        throw "Test group name collision  -  re-run to get a new random suffix."
    }

    # ── create the STAGED test user ───────────────────────────────────────
    $Script:testUser = oktaNewUser2 `
        -oOrg      $Script:org `
        -login     $Script:userLogin `
        -firstName 'PesterWrite' `
        -lastName  'TestUser' `
        -mobilePhone '+15550001234'
    $Script:testUserId = $Script:testUser.id

    # ── create two test groups ────────────────────────────────────────────
    $Script:groupA = oktaCreateGroup -oOrg $Script:org -name $Script:groupNameA -description 'Pester test group A'
    $Script:groupAId = $Script:groupA.id

    $Script:groupB = oktaCreateGroup -oOrg $Script:org -name $Script:groupNameB -description 'Pester test group B'
    $Script:groupBId = $Script:groupB.id
}

# ────────────────────────────────────────────────────────────────────────────
# User creation (oktaNewUser2)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaNewUser2  -  create a STAGED user' {

    It 'Returns a user object with an id' {
        $Script:testUser | Should -Not -BeNullOrEmpty
        $Script:testUserId | Should -Not -BeNullOrEmpty
        $Script:testUserId.Length | Should -Be 20
    }

    It 'User starts in STAGED status' {
        $Script:testUser.status | Should -Be 'STAGED'
    }

    It 'User profile has correct login' {
        $Script:testUser.profile.login | Should -Be $Script:userLogin
    }

    It 'User profile has correct firstName and lastName' {
        $Script:testUser.profile.firstName | Should -Be 'PesterWrite'
        $Script:testUser.profile.lastName  | Should -Be 'TestUser'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# User activation
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaActivateUserbyId  -  activate a STAGED user' {

    BeforeAll {
        oktaActivateUserbyId -oOrg $Script:org -uid $Script:testUserId
        Start-Sleep -Seconds 1   # brief wait for Okta to propagate
        $Script:testUser = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
    }

    It 'User status is PROVISIONED after activation with sendEmail=false' {
        # Okta lifecycle: STAGED → PROVISIONED when activated with sendEmail=false.
        # The user becomes ACTIVE only after completing the activation flow (clicking the link).
        $Script:testUser.status | Should -Be 'PROVISIONED'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# oktaNewUser  -  create an already-ACTIVE user
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaNewUser  -  create an ACTIVE user with credentials' {

    BeforeAll {
        $Script:activeLogin  = "pester.active.$($Script:suffix)@test.sentinelone.dev"
        $Script:activePwd    = oktaNewPassword -Length 16
        $Script:activeUser   = oktaNewUser `
            -oOrg      $Script:org `
            -login     $Script:activeLogin `
            -email     $Script:activeLogin `
            -firstName 'PesterActive' `
            -lastName  'TestUser' `
            -password  $Script:activePwd
        $Script:activeUserId = $Script:activeUser.id
    }

    It 'Returns a user with an id' {
        $Script:activeUserId | Should -Not -BeNullOrEmpty
        $Script:activeUserId.Length | Should -Be 20
    }

    It 'User is ACTIVE immediately' {
        $Script:activeUser.status | Should -Be 'ACTIVE'
    }

    # Deactivate and delete this second user immediately  -  it is only needed
    # to test the oktaNewUser path; the rest of the write tests use $Script:testUser.
    AfterAll {
        try { oktaDeactivateUserbyID -oOrg $Script:org -uid $Script:activeUserId } catch {}
        try { oktaDeleteUserbyID     -oOrg $Script:org -uid $Script:activeUserId } catch {}
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Status-filtered user listings (read, but untested until now)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaListUsersbyStatus  -  filter by lifecycle status' {

    It 'Returns ACTIVE users' {
        $result = oktaListUsersbyStatus -oOrg $Script:org -status ACTIVE -limit 5 -enablePagination $false
        $result | Should -Not -BeNullOrEmpty
        @($result)[0].status | Should -Be 'ACTIVE'
    }

    It 'Returns STAGED users (our new user is STAGED before activation, but here we just confirm the call works)' {
        # Call may return empty if no other staged users; just confirm no throw
        { oktaListUsersbyStatus -oOrg $Script:org -status STAGED -limit 5 -enablePagination $false } | Should -Not -Throw
    }
}

Describe 'oktaListActiveUsers  -  wrapper for ACTIVE filter' {

    It 'Returns active users without error' {
        $result = oktaListActiveUsers -oOrg $Script:org -limit 5 -enablePagination $false
        $result | Should -Not -BeNullOrEmpty
        @($result)[0].status | Should -Be 'ACTIVE'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Password reset (user must be ACTIVE)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaResetPasswordbyID  -  trigger password reset without email' {

    It 'Returns a resetPasswordUrl' {
        $result = oktaResetPasswordbyID -oOrg $Script:org -uid $Script:testUserId -sendEmail $false
        $result | Should -Not -BeNullOrEmpty
        $result.resetPasswordUrl | Should -Not -BeNullOrEmpty
        $result.resetPasswordUrl | Should -Match '^https://'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Profile updates
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaPutProfileupdate  -  partial profile update' {

    BeforeAll {
        # Add a department field; include all required fields to avoid clearing them
        $updates = @{
            firstName   = 'PesterWrite'
            lastName    = 'TestUser'
            email       = $Script:userLogin
            login       = $Script:userLogin
            mobilePhone = '+15550001234'
            department  = 'PesterDept'
        }
        $Script:updatedUser = oktaPutProfileupdate -oOrg $Script:org -uid $Script:testUserId -updates $updates
    }

    It 'Returns a user object' {
        $Script:updatedUser | Should -Not -BeNullOrEmpty
    }

    It 'Department field is updated' {
        $fetched = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        $fetched.profile.department | Should -Be 'PesterDept'
    }
}

Describe 'oktaChangeProfilebyID  -  full profile body replace' {

    BeforeAll {
        # oktaChangeProfilebyID sends the passed hashtable as-is  -  must include profile wrapper
        $newProfile = @{
            profile = @{
                firstName   = 'PesterChanged'
                lastName    = 'TestUser'
                email       = $Script:userLogin
                login       = $Script:userLogin
                mobilePhone = '+15550001234'
                department  = 'ChangedDept'
            }
        }
        $Script:changedUser = oktaChangeProfilebyID -oOrg $Script:org -uid $Script:testUserId -newprofile $newProfile
    }

    It 'Returns a user object' {
        $Script:changedUser | Should -Not -BeNullOrEmpty
    }

    It 'firstName reflects the new value' {
        $fetched = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        $fetched.profile.firstName | Should -Be 'PesterChanged'
        $fetched.profile.department | Should -Be 'ChangedDept'
    }

    # Restore original firstName for subsequent tests
    AfterAll {
        $restore = @{
            profile = @{
                firstName   = 'PesterWrite'
                lastName    = 'TestUser'
                email       = $Script:userLogin
                login       = $Script:userLogin
                mobilePhone = '+15550001234'
            }
        }
        oktaChangeProfilebyID -oOrg $Script:org -uid $Script:testUserId -newprofile $restore | Out-Null
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Suspend / Unsuspend lifecycle
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaSuspendUserbyID  -  suspend an ACTIVE user' {

    BeforeAll {
        oktaSuspendUserbyID -oOrg $Script:org -uid $Script:testUserId
        Start-Sleep -Seconds 1
    }

    It 'User status is SUSPENDED' {
        $user = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        $user.status | Should -Be 'SUSPENDED'
    }
}

Describe 'oktaUnSuspendUserbyID  -  restore a SUSPENDED user' {

    BeforeAll {
        oktaUnSuspendUserbyID -oOrg $Script:org -uid $Script:testUserId
        Start-Sleep -Seconds 1
    }

    It 'User status returns to PROVISIONED (pre-suspend state) after unsuspend' {
        $user = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        # User was PROVISIONED before suspend; unsuspend restores to PROVISIONED, not ACTIVE.
        $user.status | Should -Be 'PROVISIONED'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Group creation
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaCreateGroup  -  create new groups' {

    It 'Group A was created with the correct name' {
        $Script:groupA | Should -Not -BeNullOrEmpty
        $Script:groupA.profile.name | Should -Be $Script:groupNameA
        $Script:groupAId.Length | Should -Be 20
    }

    It 'Group A is retrievable by ID' {
        $fetched = oktaGetGroupbyId -oOrg $Script:org -gid $Script:groupAId
        $fetched.id | Should -Be $Script:groupAId
    }

    It 'Group B was created with the correct name' {
        $Script:groupB.profile.name | Should -Be $Script:groupNameB
        $Script:groupBId.Length | Should -Be 20
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Group membership
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaAddUseridtoGroupid  -  add user to group' {

    BeforeAll {
        oktaAddUseridtoGroupid -oOrg $Script:org -uid $Script:testUserId -gid $Script:groupAId
        Start-Sleep -Seconds 3   # allow Okta to propagate group membership
    }

    It 'User appears in group A member list' {
        $members = oktaGetGroupMembersbyId -oOrg $Script:org -gid $Script:groupAId -enablePagination $false -limit 200
        $ids = @($members | ForEach-Object { $_.id })
        $Script:testUserId | Should -BeIn $ids
    }

    It 'Group A appears in user group list' {
        $groups = oktaGetGroupsbyUserId -oOrg $Script:org -uid $Script:testUserId
        $gids = @($groups | ForEach-Object { $_.id })
        $Script:groupAId | Should -BeIn $gids
    }
}

Describe 'oktaDelUseridfromGroupid  -  remove user from group' {

    BeforeAll {
        oktaDelUseridfromGroupid -oOrg $Script:org -uid $Script:testUserId -gid $Script:groupAId
        Start-Sleep -Seconds 3   # allow Okta to propagate group membership removal
    }

    It 'User no longer appears in group A member list' {
        $members = oktaGetGroupMembersbyId -oOrg $Script:org -gid $Script:groupAId -enablePagination $false -limit 200
        $ids = @($members | ForEach-Object { $_.id })
        $Script:testUserId | Should -Not -BeIn $ids
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Group rules (read, untested until now)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaListGroupRules  -  retrieve group rules' {

    It 'Does not throw' {
        { $null = oktaListGroupRules -oOrg $Script:org -limit 10 } | Should -Not -Throw
    }

    It 'Returns an array (may be empty in preview)' {
        $result = oktaListGroupRules -oOrg $Script:org -limit 10
        $result | Should -Not -Be $null
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Administrators listing (internal API  -  may not be available in all orgs)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaListAdministrators  -  internal administrators API' {

    It 'Does not throw for a basic call' {
        { $null = oktaListAdministrators -oOrg $Script:org -limit 5 -enablePagination $false } | Should -Not -Throw
    }

    It 'Returns results or a gracefully handled empty response' {
        $result = oktaListAdministrators -oOrg $Script:org -limit 5 -enablePagination $false
        # Result may be null/empty if the internal API is unavailable; just confirm no exception
        $result | Should -Not -Be $null
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Deactivation (required before delete)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaDeactivateUserbyID  -  move user to DEPROVISIONED' {

    BeforeAll {
        oktaDeactivateUserbyID -oOrg $Script:org -uid $Script:testUserId
        Start-Sleep -Seconds 1
    }

    It 'User status is DEPROVISIONED' {
        $user = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        $user.status | Should -Be 'DEPROVISIONED'
    }
}

Describe 'oktaListDeprovisionedUsers  -  filter for deprovisioned users' {

    It 'Returns deprovisioned users' {
        $result = oktaListDeprovisionedUsers -oOrg $Script:org -limit 5 -enablePagination $false
        $result | Should -Not -BeNullOrEmpty
        @($result)[0].status | Should -Be 'DEPROVISIONED'
    }

    It 'Test user is individually confirmed DEPROVISIONED via direct lookup' {
        # The deprovisioned list may have many users; confirm our specific user is DEPROVISIONED
        # via a direct fetch rather than scanning a paginated list.
        $user = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        $user.status | Should -Be 'DEPROVISIONED'
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Delete user (must be DEPROVISIONED first)
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaDeleteUserbyID  -  permanently delete a DEPROVISIONED user' {

    It 'Deletes the user without error' {
        { oktaDeleteUserbyID -oOrg $Script:org -uid $Script:testUserId } | Should -Not -Throw
    }

    It 'User lookup returns null/empty after deletion' {
        # _oktaNewCall swallows 404 and returns an empty result rather than throwing.
        $result = oktaGetUserbyID -oOrg $Script:org -userName $Script:testUserId
        @($result).Count | Should -Be 0
    }

    AfterAll {
        # Mark user as cleaned up so AfterAll doesn't retry
        $Script:testUserDeleted = $true
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Delete test groups
# ────────────────────────────────────────────────────────────────────────────
Describe 'oktaDeleteGroupbyId  -  delete test groups' {

    It 'Deletes group A without error' {
        { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:groupAId } | Should -Not -Throw
    }

    It 'Group A lookup returns null/empty after deletion' {
        # _oktaNewCall swallows 404 and returns an empty result rather than throwing.
        $result = oktaGetGroupbyId -oOrg $Script:org -gid $Script:groupAId
        @($result).Count | Should -Be 0
    }

    It 'Deletes group B without error' {
        { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:groupBId } | Should -Not -Throw
    }

    AfterAll {
        $Script:groupsDeleted = $true
    }
}

# ────────────────────────────────────────────────────────────────────────────
# Cleanup  -  runs even if tests fail mid-way
# ────────────────────────────────────────────────────────────────────────────
AfterAll {
    if (-not $Script:testUserDeleted -and $Script:testUserId) {
        try { oktaDeactivateUserbyID -oOrg $Script:org -uid $Script:testUserId } catch {}
        try { oktaDeleteUserbyID     -oOrg $Script:org -uid $Script:testUserId } catch {}
    }
    if (-not $Script:groupsDeleted) {
        if ($Script:groupAId) { try { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:groupAId } catch {} }
        if ($Script:groupBId) { try { oktaDeleteGroupbyId -oOrg $Script:org -gid $Script:groupBId } catch {} }
    }
    Remove-Module Okta -ErrorAction SilentlyContinue
}

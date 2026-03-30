#Requires -Modules Pester
<#
.SYNOPSIS
    Pure unit tests for Okta.psm1 helper functions. No API calls are made.
.DESCRIPTION
    Tests helper/utility functions that have no external dependencies.
    Run with: Invoke-Pester .\tests\Unit.Tests.ps1 -Output Detailed
#>

BeforeAll {
    # Import module from project root relative to this file
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Okta.psm1'
    Import-Module $modulePath -Force

    # Suppress module-level verbose output during tests
    $Global:oktaVerbose = $false
}

Describe 'oktaNewPassword' {

    It 'Returns a string' {
        $result = oktaNewPassword
        $result | Should -BeOfType [string]
    }

    It 'Returns the default length of 15' {
        $result = oktaNewPassword
        $result.Length | Should -BeGreaterOrEqual 15
    }

    It 'Returns a custom length when specified' {
        $result = oktaNewPassword -Length 20
        $result.Length | Should -BeGreaterOrEqual 20
    }

    It 'Contains at least one uppercase letter' {
        $result = oktaNewPassword
        $result | Should -Match '[A-Z]'
    }

    It 'Contains at least one lowercase letter' {
        $result = oktaNewPassword
        $result | Should -Match '[a-z]'
    }

    It 'Contains at least one digit' {
        $result = oktaNewPassword
        $result | Should -Match '[0-9]'
    }

    It 'Does not contain the letter x from a broken charset (regression)' {
        # Regression: charset previously had "abcdefghijklmnopqrstuvwzyz" (missing x).
        # One long password via a single Random instance avoids WPS 5.1 seed-collision
        # issues (rapid New-Object Random calls can share the same millisecond seed).
        # With Length=500, ~125 lowercase chars: P(no x) < 0.01%.
        $result = oktaNewPassword -Length 500
        ($result -cmatch 'x') | Should -BeTrue
    }
}

Describe 'oktaRandLower' {

    It 'Returns a string' {
        $result = oktaRandLower
        $result | Should -BeOfType [string]
    }

    It 'Returns the default length of 18' {
        $result = oktaRandLower
        $result.Length | Should -BeGreaterOrEqual 18
    }

    It 'Returns only lowercase letters' {
        $result = oktaRandLower -Length 40
        $result | Should -Match '^[a-z]+$'
    }

    It 'Does not contain uppercase letters' {
        $result = oktaRandLower -Length 40
        # -Match is case-insensitive in PowerShell; use -cmatch for case-sensitive check
        ($result -cmatch '[A-Z]') | Should -BeFalse
    }

    It 'Does not contain digits or special chars' {
        $result = oktaRandLower -Length 40
        $result | Should -Not -Match '[^a-z]'
    }

    It 'Does not contain the letter x from a broken charset (regression)' {
        $hasX = $false
        for ($i = 0; $i -lt 50; $i++) {
            if ((oktaRandLower -Length 40) -match 'x') { $hasX = $true; break }
        }
        $hasX | Should -BeTrue
    }
}

Describe 'oktaExternalIdtoGUID' {

    It 'Converts a valid base64 external ID to a GUID' {
        # 16 random bytes → base64 → should round-trip to a valid GUID
        $bytes = [byte[]](0x01,0x23,0x45,0x67,0x89,0xAB,0xCD,0xEF,
                          0xFE,0xDC,0xBA,0x98,0x76,0x54,0x32,0x10)
        $b64 = [Convert]::ToBase64String($bytes)
        $result = oktaExternalIdtoGUID -externalId $b64
        $result | Should -BeOfType [System.Guid]
    }

    It 'Throws on invalid base64 input' {
        { oktaExternalIdtoGUID -externalId 'not-valid-base64!!!' } | Should -Throw
    }
}

Describe 'oktaProcessHeaderLink' {

    It 'Parses a single self link' {
        $header = '<https://example.okta.com/api/v1/users?limit=200>; rel="self"'
        $result = oktaProcessHeaderLink -linkHeader $header
        $result | Should -BeOfType [hashtable]
        $result['self'] | Should -Be 'https://example.okta.com/api/v1/users?limit=200'
    }

    It 'Parses next and self links from a comma-separated header' {
        $header = '<https://example.okta.com/api/v1/users?after=abc>; rel="next", <https://example.okta.com/api/v1/users?limit=200>; rel="self"'
        $result = oktaProcessHeaderLink -linkHeader $header
        $result['next'] | Should -Be 'https://example.okta.com/api/v1/users?after=abc'
        $result['self'] | Should -Be 'https://example.okta.com/api/v1/users?limit=200'
    }

    It 'Handles a string array of link headers' {
        # Cast to [string[]]  -  the function checks for [System.String[]] specifically
        $headers = [string[]]@(
            '<https://example.okta.com/api/v1/users?after=abc>; rel="next"',
            '<https://example.okta.com/api/v1/users?limit=200>; rel="self"'
        )
        $result = oktaProcessHeaderLink -linkHeader $headers
        $result['next'] | Should -Be 'https://example.okta.com/api/v1/users?after=abc'
        $result['self'] | Should -Be 'https://example.okta.com/api/v1/users?limit=200'
    }

    It 'Returns an empty hashtable for a header with no valid links' {
        $header = 'garbage; nonsense'
        $result = oktaProcessHeaderLink -linkHeader $header
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
}

Describe 'oktaBuildURIQuery' {

    It 'Adds a single query parameter' {
        $uri = [System.UriBuilder]::new('https', 'example.okta.com', 443, '/api/v1/users')
        $result = oktaBuildURIQuery -uri $uri -addParams @{ limit = 200 }
        $result.Query | Should -Match 'limit=200'
    }

    It 'Appends a second parameter with &' {
        $uri = [System.UriBuilder]::new('https', 'example.okta.com', 443, '/api/v1/users')
        $uri = oktaBuildURIQuery -uri $uri -addParams @{ limit = 200 }
        $uri = oktaBuildURIQuery -uri $uri -addParams @{ after = 'cursor123' }
        $uri.Query | Should -Match 'limit=200'
        $uri.Query | Should -Match 'after=cursor123'
    }

    It 'Returns a UriBuilder' {
        $uri = [System.UriBuilder]::new('https', 'example.okta.com', 443, '/api/v1/users')
        $result = oktaBuildURIQuery -uri $uri -addParams @{ foo = 'bar' }
        $result | Should -BeOfType [System.UriBuilder]
    }
}

Describe 'oktaBuildURI' {

    It 'Returns a string (resource path)' {
        $result = oktaBuildURI -resource '/api/v1/users' -params @{ limit = 10 }
        $result | Should -BeOfType [string]
    }

    It 'Includes the resource path' {
        $result = oktaBuildURI -resource '/api/v1/users' -params @{ limit = 10 }
        $result | Should -Match '/api/v1/users'
    }

    It 'Appends a single query parameter' {
        $result = oktaBuildURI -resource '/api/v1/users' -params @{ limit = 10 }
        $result | Should -Match 'limit=10'
    }

    It 'Appends multiple query parameters' {
        $result = oktaBuildURI -resource '/api/v1/users' -params @{ limit = 5; q = 'smith' }
        $result | Should -Match 'limit=5'
        $result | Should -Match 'q=smith'
    }

    It 'Preserves query string values as-is (UrlPathEncode only touches the path)' {
        # oktaBuildURI uses UrlPathEncode which encodes the path segment only;
        # query string values are not transformed.
        $result = oktaBuildURI -resource '/api/v1/users' -params @{ filter = 'status eq "ACTIVE"' }
        $result | Should -Match 'filter='
        $result | Should -Match 'ACTIVE'
    }
}

Describe 'OktaUserfromJson  -  convert date strings to [datetime]' {

    It 'Converts a created string to [datetime]' {
        $user = [PSCustomObject]@{
            created        = '2024-01-15T10:30:00.000Z'
            activated      = $null
            statusChanged  = $null
            lastLogin      = $null
            lastUpdated    = $null
            passwordChanged = $null
        }
        $result = OktaUserfromJson -user $user
        $result.created | Should -BeOfType [datetime]
    }

    It 'Leaves null date fields as null' {
        $user = [PSCustomObject]@{
            created        = '2024-01-15T10:30:00.000Z'
            activated      = $null
            statusChanged  = $null
            lastLogin      = $null
            lastUpdated    = $null
            passwordChanged = $null
        }
        $result = OktaUserfromJson -user $user
        $result.lastLogin | Should -BeNullOrEmpty
    }

    It 'Converts all populated date fields' {
        $user = [PSCustomObject]@{
            created         = '2024-01-01T00:00:00.000Z'
            activated       = '2024-01-02T00:00:00.000Z'
            statusChanged   = '2024-01-03T00:00:00.000Z'
            lastLogin       = '2024-01-04T00:00:00.000Z'
            lastUpdated     = '2024-01-05T00:00:00.000Z'
            passwordChanged = '2024-01-06T00:00:00.000Z'
        }
        $result = OktaUserfromJson -user $user
        $result.created         | Should -BeOfType [datetime]
        $result.activated       | Should -BeOfType [datetime]
        $result.statusChanged   | Should -BeOfType [datetime]
        $result.lastLogin       | Should -BeOfType [datetime]
        $result.lastUpdated     | Should -BeOfType [datetime]
        $result.passwordChanged | Should -BeOfType [datetime]
    }
}

Describe 'OktaAppfromJson  -  convert app date strings to [datetime]' {

    It 'Converts created and lastUpdated to [datetime]' {
        $app = [PSCustomObject]@{
            created     = '2024-03-01T12:00:00.000Z'
            lastUpdated = '2024-03-15T08:00:00.000Z'
        }
        $result = OktaAppfromJson -app $app
        $result.created     | Should -BeOfType [datetime]
        $result.lastUpdated | Should -BeOfType [datetime]
    }

    It 'Leaves null dates as null' {
        $app = [PSCustomObject]@{
            created     = $null
            lastUpdated = '2024-03-15T08:00:00.000Z'
        }
        $result = OktaAppfromJson -app $app
        $result.created | Should -BeNullOrEmpty
    }
}

AfterAll {
    Remove-Module Okta -ErrorAction SilentlyContinue
}

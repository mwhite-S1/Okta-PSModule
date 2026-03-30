@{
    # The org alias to use for integration tests. Must match a key in $oktaOrgs (okta_org.ps1).
    OrgAlias = "prev"

    # A valid, active user's Okta ID (20 chars). Used by user-centric tests.
    KnownUserId = "00u1fcu6ofGaouXrO1d7"

    # The login (email) of the same user above. Used to test lookup-by-login.
    KnownUserLogin = "darlene.smith@test.sentinelone.dev"

    # A valid group ID (20 chars) that has at least one member.
    KnownGroupId = "00g2xhsyqcxSNqvQ91d7"

    # A valid application ID (20 chars).
    KnownAppId = "0oa1e0scxcfZCJlXB1d7"

    # A group ID that is assigned to the KnownAppId above.
    KnownAppGroupId = "00ghddtvit6Dcn3YB1d7"
}

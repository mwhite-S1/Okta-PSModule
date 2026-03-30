# Findings — Okta-PSModule Review

## Module Overview
- File: `Okta.psm1`
- Language: PowerShell
- Purpose: Wrapper module for the Okta REST API
- Covers: Users, Groups, Apps, Factors, Logs, Events, IdPs, Zones, Policies, GroupRules, CSRs

---

## Round 1 Findings (Fixed)

| # | Location | Issue | Status |
|---|----------|-------|--------|
| 1 | Line 3370 & 3485 | Duplicate `oktaActivateFactorByUser` — second definition silently overwrote first | Fixed: merged |
| 2 | Line 2432 | `$org` instead of `$oOrg` in `oktaUpdateAppOverrides` | Fixed |
| 3 | Line 5095 | `if ($pid)` (PS auto-var) instead of `if ($grid)` in `oktaListGroupRules` | Fixed |
| 4 | Line 5105 | `$rules` referenced but not a parameter in `oktaListGroupRules` | Fixed: added `[switch]$rules` |
| 5 | Line 4216 | Missing `=` in `?startDate` URL in `oktaListEvents` | Fixed |
| 6 | Line 4850 | `if (!$newName -eq ...)` wrong precedence in `oktaUpdateZone` | Fixed: `$newName -ne ...` |
| 7 | Line 1033 | `Add-Member NoteProperty` on a Hashtable in `oktaPutProfileupdate` | Fixed: `@{ profile = $updates }` |
| 8 | Line 344 | `$role[$df]` (hashtable) vs `$role.$df` (object) mixed in `OktaRolefromJson` | Fixed: unified to dot-notation |
| 9 | Line 1935 | `$bodyMap.Keys -gt 0` — collection vs integer compare in `oktaAppAssignGroup` | Fixed: `.Keys.Count -gt 0` |
| 10 | Line 44, 79 | `"abcdefghijklmnopqrstuvwzyz"` missing `x` in both password generators | Fixed |
| 11 | Line 498, 500 | `X-Okta-Requst-Id` header name typo in `_oktaMakeCall` | Fixed |
| 12 | Line 4400, 4404 | `$userNameTempalate` / `$maxClockSwew` param typos in `oktaNewProviderPolicyObject` | Fixed |
| 13 | Line 792 | `[datetime]$after` in `oktaGetLogs` — Okta `after` is a cursor, not datetime | No change — user confirmed intentional |
| 14 | Line 3143 | `-enablePagination:$true` hardcoded, ignores param in `oktaGetGroupMembersbyId` | Fixed |
| 15 | Line 710 | Dead `$file` branch in `_oktaNewCall` — variable never defined | Removed |

---

## Round 2 Findings (Pending)

### Bugs

| # | Function | Line(s) | Issue |
|---|----------|---------|-------|
| A | `oktaNewUser`, `oktaNewUser2`, `oktaActivateUserbyId`, `oktaResetPasswordbyID` | 920, 967, 2353, 2251 | Boolean casing: `True`/`False` in URLs — Okta API expects lowercase `true`/`false`. Dynamic case (`$sendEmail` concat) will always produce wrong casing at runtime |
| B | `oktaAdminExpirePasswordbyID` | 1144, 1147 | `$tempPassword` is generated and put in the body, but the URL is hardcoded `?tempPassword=false`. Okta's `tempPassword` query param controls whether the API *returns* a temp password — it's not caller-supplied. The body value does nothing |
| C | `oktaListAdministrators` | 2042–2047 | `$uid` branch is unreachable: `elseif ($limit)` always matches since `$limit` defaults to `$OktaOrgs[$oOrg].pageSize`. Need to reorder conditions or check `$uid` first |
| D | `oktaCreateZone` | 4670–4671 | Hardcoded CIDR `132.190.0.0/16` and RANGE `132.190.192.10` baked into every created zone. No parameters for gateways/proxies. Function appears unfinished |
| E | `oktaUpdateUserbyID`, `oktaForgotPasswordbyId` | 1076, 1248 | `$r_answer.ToLower().Replace()` called without null guard — throws `NullReferenceException` if `$r_answer` not provided (not Mandatory) |
| F | `oktaGetDevices` | 1439 | Search URL contains unencoded spaces and bare double-quote chars: `search=status eq ""ACTIVE"""` — should be URL-encoded |
| G | `_oktaMakeCall` | 535–538 | `429` case in error switch only writes a warning, does not throw or retry. The request is silently dropped on rate-limit errors |

### Design / Minor Issues

| # | Function | Issue |
|---|----------|-------|
| H | `_oktaMakeCall` | `MethodNotAllowed` case writes a warning but doesn't throw — caller never knows the call failed |
| I | `oktaCheckCreds` | `Get-Variable -ne ""` check for `$options`/`$context` hashtables: empty `@{}` passes the check and gets added to the request body unnecessarily. Should check `$null` |
| J | `oktaGetLogs` vs `oktaListLogs` | Two overlapping functions for `/api/v1/logs` with different implementations and inconsistent parameter names (`$order` vs `$sortOrder`). Creates confusion and drift risk |

---

## Notes / Observations

- `$rateLimt` (missing second 't') is used consistently throughout — not a bug but a persistent naming issue
- Many filter/query values are built into URLs without URL-encoding (commented-out `UrlPathEncode` calls are visible throughout). Breaks if values contain spaces or special chars
- `oktaBuildURI` uses `UrlPathEncode` for query parameters — should use `Uri.EscapeDataString` for query values
- `oktaGetUserbyID` has commented-out URL encoding (line 1470) — usernames with `+`, `@`, spaces won't encode correctly
- `oktaNewUser` sends plaintext password in the API body — this is how the Okta API works, but worth noting
- `oktaCheckCredsOld` is presumably dead code / superseded by `oktaCheckCreds`
- `oktaPushGroupToApp` is marked `#not working` in a comment

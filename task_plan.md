# Task Plan — Okta-PSModule Code Review & Fixes

## Goal
Review `Okta.psm1` for bugs, logic errors, typos, and incomplete implementations. Fix all confirmed issues and document remaining findings for future work.

## Status: Phase 2 In Progress

---

## Phase 1 — Initial Review & Bug Inventory
**Status: complete**

Full read-through of `Okta.psm1`. Identified 15 bugs across:
- Duplicate function definitions
- Wrong variable names
- Dead code
- Logic errors
- Typos in character sets and header names
- Incorrect comparisons

All findings logged in `findings.md`.

---

## Phase 2 — Fix Confirmed Bugs (Round 1)
**Status: complete**

All 15 tasks from initial review addressed. See findings.md for full list.
One task (#13 - `$after` as `[datetime]`) confirmed as intentional by user — no change made.

### Files Modified
- `Okta.psm1`

### Changes Made
| Task | Description | Result |
|------|-------------|--------|
| 1 | Merged duplicate `oktaActivateFactorByUser` | Fixed |
| 2 | `$org` → `$oOrg` in `oktaUpdateAppOverrides` | Fixed |
| 3 | `$pid` → `$grid` in `oktaListGroupRules` | Fixed |
| 4 | Added `[switch]$rules` param to `oktaListGroupRules` | Fixed |
| 5 | Missing `=` in `oktaListEvents` URL | Fixed |
| 6 | Boolean logic in `oktaUpdateZone` | Fixed |
| 7 | `Add-Member` on Hashtable in `oktaPutProfileupdate` | Fixed |
| 8 | Mixed `$role[$df]`/`$role.$df` in `OktaRolefromJson` | Fixed |
| 9 | `.Keys -gt 0` → `.Keys.Count -gt 0` in `oktaAppAssignGroup` | Fixed |
| 10 | Missing `x` in character sets in password generators | Fixed |
| 11 | `X-Okta-Requst-Id` header typo | Fixed |
| 12 | `$userNameTempalate` / `$maxClockSwew` typos | Fixed |
| 13 | `$after` as `[datetime]` in `oktaGetLogs` | No change — intentional |
| 14 | `$enablePagination` hardcoded in `oktaGetGroupMembersbyId` | Fixed |
| 15 | Dead `$file` branch in `_oktaNewCall` | Removed |

---

## Phase 3 — Second Review & Remaining Issues
**Status: in_progress**

Second pass identified 10 additional issues. Awaiting user direction on which to fix.
See findings.md — "Round 2 Findings" section.

---

## Phase 4 — Fix Round 2 Issues
**Status: complete**

| Task | Description | Result |
|------|-------------|--------|
| A | Boolean casing `True`/`False` in URLs | Fixed all 4 occurrences |
| B | `oktaAdminExpirePasswordbyID` tempPassword logic | Fixed: `[switch]$returnTempPassword`, removed meaningless body |
| C | `$uid` branch unreachable in `oktaListAdministrators` | Fixed: reordered `$uid` before `$limit` |
| D | Hardcoded CIDR/IP in `oktaCreateZone` | Fixed: added `[array]$gateways` and `[array]$proxies` params |
| E | Null dereference on `$r_answer.ToLower()` | Fixed: cast to `[string]` in both functions |
| F | Unencoded search in `oktaGetDevices` | Fixed: `Uri.EscapeDataString` |
| G | 429 case doesn't throw in `_oktaMakeCall` | Fixed: added throw |
| H | MethodNotAllowed case doesn't throw | Fixed: added throw |
| I | Empty hashtable in `oktaCheckCreds` request body | Fixed: proper null + empty hashtable guard |
| J | `oktaGetLogs`/`oktaListLogs` overlap | Fixed: added `$q`, `$after`, `[alias("sortOrder")]` to `oktaListLogs`; `oktaGetLogs` now delegates |

---

---

## Phase 5 — Group Rules API Support
**Status: complete**

Add full CRUD + lifecycle functions for the Okta Group Rules API (`/api/v1/groups/rules`).

| Task | Function | Description |
|------|----------|-------------|
| K | `oktaGetGroupRuleById` | GET a single rule by ID |
| L | `oktaCreateGroupRule` | POST — create a new rule |
| M | `oktaUpdateGroupRule` | PUT — update an existing rule |
| N | `oktaDeleteGroupRule` | DELETE a rule |
| O | `oktaActivateGroupRule` | POST to `.../lifecycle/activate` |
| P | `oktaDeactivateGroupRule` | POST to `.../lifecycle/deactivate` |

Read-only tests (list, get) added to `tests/Integration.Tests.ps1`.
Full write/lifecycle tests in `tests/GroupRule.Tests.ps1`:
- BeforeAll: creates disposable group + rule
- Covers: GetById, List, Update, Activate, Deactivate
- AfterAll: deletes rule then group

---

---

## Phase 6 - Group Push Mappings Support
**Status: complete**

### Goal
Replace the broken `oktaPushGroupToApp` with a complete, correct implementation using the official Group Push Mappings API plus the internal trigger endpoint.

### Background
The existing `oktaPushGroupToApp` called `POST /api/internal/instance/{appId}/grouppush` (no mappingId) with a partially-formed body. This endpoint does not exist in that form — the function has never worked. The correct public API was released in 2025 and the internal trigger requires a mappingId from the mapping API.

### Functions to implement

| Task | Function | Method | Endpoint |
|------|----------|--------|----------|
| 6-A | Remove `oktaPushGroupToApp` | - | Replaced entirely |
| 6-B | `oktaListGroupPushMappings` | GET | `/api/v1/apps/{appId}/group-push/mappings` |
| 6-C | `oktaGetGroupPushMapping` | GET | `/api/v1/apps/{appId}/group-push/mappings/{mappingId}` |
| 6-D | `oktaCreateGroupPushMapping` | POST | `/api/v1/apps/{appId}/group-push/mappings` |
| 6-E | `oktaUpdateGroupPushMapping` | PUT | `/api/v1/apps/{appId}/group-push/mappings/{mappingId}` |
| 6-F | `oktaDeleteGroupPushMapping` | DELETE | `/api/v1/apps/{appId}/group-push/mappings/{mappingId}` |
| 6-G | `oktaTriggerGroupPush` | PUT | `/api/internal/instance/{appId}/grouppush/{mappingId}` |

### Key API notes
- `oktaCreateGroupPushMapping`: requires `$sourceGroupId`; requires exactly one of `$targetGroupId` (link existing) or `$targetGroupName` (create new). Validated in function.
- `oktaUpdateGroupPushMapping`: accepts partial updates — `$status` (ACTIVE/INACTIVE/ERROR), `$sourceGroupId`, `$targetGroupName`.
- `oktaTriggerGroupPush`: internal endpoint, not covered by Okta SLA. Sends `{ status: ACTIVE|INACTIVE }` to force a push or suspend. Marked with a warning comment in code.
- Provisioning must be enabled on the target app for push mappings to work.

### Test plan
- Read-only: `oktaListGroupPushMappings`, `oktaGetGroupPushMapping` added to `Integration.Tests.ps1` (skip gracefully if no mappings exist on `prev` org).
- Write tests: new `GroupPush.Tests.ps1` — create mapping, get, update status, trigger push, delete. Requires an app with provisioning enabled in `prev` org; tests skip if no suitable app found.

---

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| Task #13 edit rejected by user | 1 | User confirmed `[datetime]` is intentional for `$after` |

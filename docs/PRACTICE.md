# NotesApp practice guide

A small .NET Framework 4.8 Web Forms app with the **full enterprise release process** around it.
Do the setup once, then the exercises in order. Each exercise practises one idea from the two decks
(“From Manual to Reliable Releases” and “Our Branching and Release Model”).

| In the decks | In this practice repo |
|---|---|
| Nexus (release repository) | **GitHub Packages**, package `NotesApp.Web` (a version can be published once) |
| SonarQube | **SonarCloud** (free for public repos) |
| Snyk | **Snyk** (free account) |
| DEV / SIT / PAT / PROD servers | **IIS sites on your PC**: ports 8081 / 8082 / 8083 / 8084 |
| Deploy agent inside the network | **Self-hosted GitHub runner** on your PC |
| Deployment team’s approval | **Required reviewers** on the GitHub environments |

## The flow

```
feature/<n>-name ──PR──▶ main ──▶ Build: test build 1.x.0-ci.N ──▶ DEV (automatic)
   CI: build, Moq + shim tests,                  │
   SonarCloud gate, Snyk, CodeQL                 ├─ Deploy to SIT (run id, approval)
                                                 │
                                                 └─ Release (run id) ─▶ GitHub Packages NotesApp.Web 1.x.0
                                                                       + tag v1.x.0 + GitHub Release
                                                                          │
                                                       Promote ─▶ PAT ─▶ PROD (approval)
hotfix/1.x.1 (from tag v1.x.0) ──▶ Build 1.x.1-ci.N ──▶ SIT ──▶ Release 1.x.1 ──▶ PROD ──▶ PR back into main
```

Every deploy: download → verify checksum → fill `#{tokens}#` from the environment’s variables →
**database migrations** → new folder `releases\<version>` → switch IIS → `/health.ashx` must answer
200 with the new version → otherwise **switch back automatically**.

---

## One-time setup

### 1. Run it locally (Visual Studio)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup\Setup-LocalDb.ps1
```

Open `NotesApp.sln`, set **NotesApp.Web** as startup project, press **F5**.
`Web.config` points at LocalDB, so this works without any tokens.

Shim tests (`tests/NotesApp.ShimTests`) need Visual Studio **Enterprise**; with Community they only
run in CI. That is expected.

### 2. Turn your PC into DEV/SIT/PAT/PROD

1. **IIS**: elevated PowerShell:
   ```powershell
   Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-WebServerRole,IIS-WebServer,IIS-ASPNET45,IIS-NetFxExtensibility45,IIS-ISAPIExtensions,IIS-ISAPIFilter,IIS-ManagementConsole,IIS-ManagementScriptingTools
   ```
2. **SQL Server Express** (free): download from Microsoft, choose **Basic**, keep instance name `SQLEXPRESS`.
   LocalDB can’t be used by IIS, which is why Express is needed.
3. **Create the sites, app pools, databases and SQL logins**: elevated PowerShell in the repo folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\setup\Setup-LocalServer.ps1
   ```
   It prints `gh variable set ...` commands for each environment. Run them (they are config, not secrets).

### 3. Self-hosted runner (your PC deploys)

1. GitHub → repo → **Settings → Actions → Runners → New self-hosted runner** → Windows x64.
   Follow the commands into `C:\actions-runner` (keep the default labels).
2. Start it from an **elevated** PowerShell (changing IIS needs admin): `C:\actions-runner\run.cmd`
3. Tell the workflows to use it:
   ```powershell
   gh variable set DEPLOY_RUNNER --body "self-hosted"
   ```
4. **Safety (public repo):** Settings → Actions → General → *Fork pull request workflows*:
   require approval for all outside contributors. Only `push`/manual workflows use your runner;
   PR checks always run on GitHub’s machines.

Without steps 2–3 everything still runs, as a **dry run** on GitHub’s machines.

### 4. SonarCloud (the SonarQube quality gate)

1. Sign in at sonarcloud.io with GitHub → import your account as an organization → **Analyze new project** → NotesApp.
2. Choose **GitHub Actions** as the analysis method (turn **Automatic Analysis off**).
3. Create a token, then:
   ```powershell
   gh secret set SONAR_TOKEN
   gh variable set SONAR_ORGANIZATION --body "<your organization key>"
   gh variable set SONAR_PROJECT_KEY --body "<your project key>"
   ```

### 5. Snyk

Free account at snyk.io → Account settings → Auth token → `gh secret set SNYK_TOKEN`.

### 6. Approvals

Settings → Environments → **SIT**, **PAT**, **PROD** → *Required reviewers* → add yourself.
(DEV stays automatic.)

Branch and tag rules are already set: `main` only changes through a PR with a green `all-green`
check; `v*` tags can’t be moved or deleted.

---

## Exercises

### 1. Your first feature (PR checks → DEV)

```powershell
git checkout main; git pull
git checkout -b feature/1-note-count
```
Show “N notes” above the list (`Default.aspx` + code-behind). Add a unit test in
`tests/NotesApp.Tests`. Push, open a PR into `main`, and watch **CI**: build, unit tests, shim
tests, SonarCloud, Snyk, CodeQL. Merge it.
**Build** runs and **DEV** deploys automatically: http://localhost:8081 shows `DEV · v1.0.0-ci.N`.

### 2. Break a gate on purpose

On a new branch, make a unit test fail (or add an unused variable for Sonar). Open a PR: the merge
button is blocked. Fix it and push again.

### 3. Deploy to SIT

Copy the **run id** from the Build run’s summary → Actions → **Deploy to SIT** → run id → approve.
http://localhost:8082 shows `SIT · v1.0.0-ci.N`. Same package as DEV, different config.

### 4. Release 1.0.0 (the Nexus step)

Actions → **Release** → same run id. Check:
- Packages: `NotesApp.Web 1.0.0`
- Tags: `v1.0.0`; Releases: “NotesApp 1.0.0” with the zip
- The zip’s SHA-256 equals the test build’s: **promoted, not rebuilt**

Try **Release** with the same run id again: refused (“v1.0.0 already exists”).
Try a Build run that never went to SIT: refused.

### 5. Promote to PAT, then PROD

Actions → **Promote** → `1.0.0` → PAT, approve. Then PROD.
http://localhost:8084 shows `PROD · v1.0.0`. Look at `C:\Sites\NotesApp\PROD\releases\`.

### 6. Keep developing (and change the database)

New feature branch: add `database/migrations/0002_AddPinned.sql`
(`ALTER TABLE dbo.Notes ADD IsPinned BIT NOT NULL CONSTRAINT DF_Notes_IsPinned DEFAULT 0;`).
It is backward-compatible: 1.0.0 still works with it. Merge → DEV shows `v1.1.0-ci.N`
(next MINOR after the `v1.0.0` tag), and the migration ran once, recorded in `dbo.SchemaVersions`.

### 7. A production bug, while main has moved on

PROD runs 1.0.0, `main` already contains 1.1 work. Fix it from the **tag**:
```powershell
git fetch --tags
git checkout -b hotfix/1.0.1 v1.0.0
```
Make a small fix, push. **Build** makes `1.0.1-ci.N` (no DEV deploy). **Deploy to SIT** →
**Release** (it can only release `1.0.1` from this branch) → **Promote** to PROD.
PROD shows `v1.0.1` and **none** of the 1.1 work. Finally open a PR from `hotfix/1.0.1` into `main`.
Merging creates **no** tag: only releasing does.

### 8. Debug exactly what PROD runs

```powershell
git checkout v1.0.1
```
That is the code PROD runs, however far `main` has moved.
`git log v1.0.0..v1.0.1 --oneline` shows what the hotfix changed.

### 9. Watch an automatic rollback

Set SIT’s `SqlDatabase` variable to `NotesApp_WRONG` and deploy a build to SIT. Migrations fail,
or the health check returns 503, and IIS is switched back to the previous release. Restore the variable.

### 10. Add a new setting the right way

Add an appSetting `SupportEmail` with value `#{SupportEmail}#` in `Web.Release.config`, show it on
the page, and deploy without adding the variable: the deploy stops with
“Missing values for DEV : SupportEmail … Nothing was changed”. Add the variable to every
environment and deploy again.

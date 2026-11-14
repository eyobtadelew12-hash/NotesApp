# NotesApp: release-process practice

A deliberately small **.NET Framework 4.8 ASP.NET Web Forms** notes app, used to practise an
enterprise CI/CD process end to end:

- PR checks: MSBuild, MSTest + **Moq** unit tests, **Microsoft Fakes** shim tests, coverage,
  **SonarCloud** quality gate, **Snyk**, CodeQL, dependency review
- Build once: every merge to `main` makes a test build that deploys to **DEV** automatically
- **Deploy to SIT** on demand; **Release** promotes the SIT-tested build to **GitHub Packages**
  (the Nexus stand-in) and tags it; **Promote** sends a release to **PAT** and **PROD**
- `Web.config` ships as a template with `#{tokens}#`, filled per environment at deploy time
- Versioned database migrations, versioned IIS release folders, health check, automatic rollback
- Hotfixes from release tags

**Start here: [docs/PRACTICE.md](docs/PRACTICE.md)**

| Folder | What |
|---|---|
| `src/NotesApp.Core` | Business rules (`NoteService`), SQL storage, a legacy static class for shim practice |
| `src/NotesApp.Web` | Web Forms site: `Default.aspx`, `/health.ashx`, `Web.config` + `Web.Release.config` |
| `tests/NotesApp.Tests` | Moq unit tests (in the solution) |
| `tests/NotesApp.ShimTests` | Fakes shim tests (needs VS Enterprise: runs in CI) |
| `database/migrations` | Numbered SQL scripts, applied once per database |
| `scripts/` | Version, package, deploy, migrations, one-time setup |
| `.github/workflows` | CI, Build, Deploy to SIT, Release, Promote, CodeQL, dependency review |

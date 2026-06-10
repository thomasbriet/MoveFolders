# MoveFolders

MoveFolders is een macOS AppKit tool om projectmappen tussen volumes/netwerkschijven over te zetten met rsync, post-verify, mismatch-afhandeling en optionele bronverwijdering.

## Build

```bash
./scripts/build_release.sh 0.4
```

Dit maakt lokaal:

- `MoveFolders_v0.4.app`
- `MoveFolders_v0.4_share.zip`
- `MoveFolders_v0.4_installer.pkg`

## Updates

De app heeft een knop `Updates` die de nieuwste GitHub Release kan controleren en de `.pkg` installer kan openen.

Voor gebruik moet in `MoveFolders_v0.3.swift` deze constante worden ingesteld:

```swift
let updateGitHubOwner = "JOUW_GITHUB_OWNER"
let updateGitHubRepo = "MoveFolders"
```

Publiceer nieuwe installers als GitHub Release assets, bijvoorbeeld met tag `v0.4`, `v0.5`, enzovoort.

## Release checklist

1. Werk versie aan met `./scripts/build_release.sh <versie>`.
2. Commit bronwijzigingen.
3. Push naar GitHub.
4. Maak een GitHub Release met tag `v<versie>`.
5. Upload `MoveFolders_v<versie>_installer.pkg` als release asset.


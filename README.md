# lexfrei apt repository

apt repository for my own tools, served from GitHub Pages. Same idea as [lexfrei/homebrew-tap](https://github.com/lexfrei/homebrew-tap), for Debian and Ubuntu.

## Use it

```bash
curl --fail --silent --show-error --location https://apt.lexfrei.dev/lexfrei.asc \
  | sudo gpg --dearmor --output /usr/share/keyrings/lexfrei.gpg

sudo tee /etc/apt/sources.list.d/lexfrei.sources >/dev/null <<'EOF'
Types: deb
URIs: https://apt.lexfrei.dev
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/lexfrei.gpg
EOF

sudo apt update
```

Then install what you came for:

```bash
sudo apt install mcp-tg
sudo apt install claudeline
```

Built for `amd64` and `arm64`.

## Packages

| Package | What it does |
| --- | --- |
| [mcp-tg](https://github.com/lexfrei/mcp-tg) | MCP server for the Telegram Client API |
| [claudeline](https://github.com/lexfrei/claudeline) | Statusline for Claude Code |

## How it works

`build-repo.sh` takes a directory of `.deb` files, lays them out in a pool, generates the indexes with `dpkg-scanpackages` and `apt-ftparchive`, and signs `InRelease`. Every run rebuilds the whole tree, so there is no state to drift.

The packages come from the projects themselves. Each one builds its own `.deb` with GoReleaser `nfpms` and attaches it to its GitHub release, and the workflow here downloads the latest release of every project in `PROJECTS`. No binaries are stored in this repo.

Runs happen on a `repository_dispatch` of type `release` and on `workflow_dispatch` for a manual rebuild. There is no schedule, so every project has to send the dispatch at the end of its release workflow:

```yaml
- run: gh api repos/lexfrei/apt/dispatches --field event_type=release
  env:
    GH_TOKEN: ${{ secrets.APT_DISPATCH_TOKEN }}
```

## Adding a project

1. Add an `nfpms` block to the project's `.goreleaser.yaml`, so its releases carry a `.deb`.
2. Append the repo name to `PROJECTS` in [publish.yml](.github/workflows/publish.yml).

A project listed before its first release with a `.deb` gets skipped, not treated as an error.

## Signing key

Signed with a dedicated key, not my personal one. To rotate it:

```bash
gpg --batch --passphrase '' --quick-generate-key 'lexfrei apt repository <f@lex.la>' default sign 3y
gpg --armor --export-secret-key 'lexfrei apt repository' | gh secret set APT_GPG_PRIVATE_KEY --repo lexfrei/apt
```

The key carries no passphrase. One would live in the same secret store as the key it protects, so anything that reads the key reads the passphrase beside it; the secret itself is the boundary.

The build exports the public half into the published tree, so users always fetch it from the repository itself. Rotating means everyone re-imports the key.

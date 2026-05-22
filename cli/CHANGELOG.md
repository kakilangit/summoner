# Changelog

All notable changes to the Summoner CLI will be documented in this file.

## [0.1.9] - 2025-05-22

### Added

- Initial release
- Commands: `agents list/show`, `invoke`, `chat` (interactive + one-shot), `pipelines list/runs`, `swarms list`, `completion`
- TOML config with profiles (`~/.config/summoner/config.toml`)
- Environment variable overrides (`SUMMONER_URL`, `SUMMONER_TOKEN`, `SUMMONER_WORKSPACE`, `SUMMONER_PROFILE`)
- Clippy pedantic lints with deny on `unwrap_used`, `panic`, `expect_used`

# Summoner CLI

Command-line interface for the Summoner AI agent orchestration platform.

## Installation

### From source

Requires [Rust toolchain](https://rustup.rs/) (1.85+).

```sh
# From GitHub (no clone needed)
cargo install --git https://github.com/kakilangit/summoner.git --path cli

# Or from a local clone
cd cli
cargo install --path .
```

This installs the `summoner` binary to `~/.cargo/bin/`.

### From GitHub Releases

Download the prebuilt binary for your platform from
[Releases](https://github.com/kakilangit/summoner/releases), extract it,
and place it somewhere on your `PATH`.

Available targets:

| Platform      | Architecture | Binary               |
|---------------|-------------|----------------------|
| Linux         | x86_64      | `summoner-linux-amd64`  |
| Linux         | aarch64     | `summoner-linux-arm64`  |

For other platforms, build from source using `cargo install --path .`.

## Configuration

Create `~/.config/summoner/config.toml`:

```toml
[default]
url = "http://localhost:4000"
token = "your-api-token"

[profiles.production]
url = "https://summoner.example.com"
token = "prod-token"
workspace_id = "01HC5M6N0JZPFTMB19HTXP1RJ9"
```

### Environment variables

Environment variables override config file values:

| Variable             | Description                  |
|---------------------|------------------------------|
| `SUMMONER_URL`      | Server URL                   |
| `SUMMONER_TOKEN`    | API bearer token             |
| `SUMMONER_WORKSPACE`| Workspace ID                 |
| `SUMMONER_PROFILE`  | Profile name to use          |

## Usage

### Agents

```sh
# List all agents
summoner agents list

# List only remote agents
summoner agents list --type remote

# Show agent details
summoner agents show <agent-id>

# Output as JSON
summoner agents list -f json
```

### Invoke

```sh
# One-shot invocation
summoner invoke <agent-id> "What is the weather today?"

# Read message from stdin
echo "Summarize this" | summoner invoke <agent-id>
```

### Chat

```sh
# Interactive chat
summoner chat <agent-id>

# One-shot chat
summoner chat <agent-id> "Hello"
```

### Pipelines

```sh
# List pipelines
summoner pipelines list

# Show pipeline runs
summoner pipelines runs <pipeline-id>
```

### Swarms

```sh
# List swarms
summoner swarms list
```

### Shell completions

```sh
# Bash
summoner completion bash >> ~/.bashrc

# Zsh
summoner completion zsh >> ~/.zshrc

# Fish
summoner completion fish > ~/.config/fish/completions/summoner.fish
```

### Global options

```sh
# Use a specific profile
summoner --profile production agents list
```

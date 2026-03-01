# Iroha

A command-line interface for conversing with Claude.

## Features

- **Persistent conversations** -- Chat history is automatically saved and resumed across sessions
- **Multi-turn dialogue** — Continue previous conversations or start fresh with `--new`
- **File resources** — Attach files to your requests with `-r`
- **Flexible input** — Provide prompts via flag, stdin pipe, or both
- **Log management** — Automatically prunes old conversation logs based on a configurable limit

## Requirements

- [Zig](https://ziglang.org/) (nightly / latest dev build)
- An [Anthropic API key](https://console.anthropic.com/)

## Installation

```sh
git clone https://github.com/okonomippiza/iroha
cd iroha
zig build
```

Or with Nix:

```sh
nix build
```

## Setup

Export your Anthropic API key:

```sh
export ANTHROPIC_API_KEY=your_api_key_here
```

## Usage

```
iroha [options]

Options:
  -h, --help              Display this help and exit
  -v, --version           Print version
  -n, --new               Start a new conversation (creates a new log file)
  -r, --resource <str>    Path to resource file(s) sent to Claude (repeatable)
  -p, --prompt <str>      Set the prompt/request content for Claude
```

### Examples

**Simple prompt:**
```sh
iroha -p "Hello, what's your name?"
```

**Pipe input from stdin:**
```sh
echo "Hello, what's your name?" | iroha
```

**Combine prompt and piped input:**
```sh
cat main.zig | iroha -p "Review the following code:"
```

**Attach resource files:**
```sh
// Resource files are resolved relative to the current directory.
iroha -p "What does this code do?" -r main.zig
```

**Start a fresh conversation:**
```sh
iroha --new -p "Let's start over"
```

**Resume the latest conversation (default):**
```sh
iroha -p "Continue where we left off"
```

## Configuration

Iroha stores its config and logs in `$HOME/.config/iroha/`.

The config file is `$HOME/.config/iroha/config.jsonc`:

```jsonc
{
  // Model to use for requests
  "model": "claude-sonnet-4-6",
  // Maximum number of conversation log files to keep
  "max_log": 100
}
```

If the config directory does not exist, it will be created automatically on first run.


## License

MIT⏎


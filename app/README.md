# app — Tauri 2 desktop shell

Scaffolded 21 Sep 2026 with `pnpm create tauri-app@latest app --template react-ts --manager pnpm` (bead sam-yku.1).

Toolchain on this Mac: Rust via rustup (`source ~/.cargo/env`, cargo 1.98.1), Node 22, pnpm 11, Xcode Command Line Tools.

```bash
cd ~/projects/jev-samsho2/app
source ~/.cargo/env
pnpm install            # once
pnpm tauri dev          # development window (Vite on :1420 + native window)
pnpm tauri build        # release bundle -> src-tauri/target/release/bundle/macos/*.app
```

Layout: game view on top (canvas 320×224 scaled), panel below with Start / Pause / Reset / Stop and the two fighter columns. Only Start is enabled until a match is running (PRD §6).

## Sidecar (sam-yku.2)

The bridge is a *script sidecar*, not a bundled binary: `start_bridge` (Rust, `src-tauri/src/lib.rs`) spawns
`/bin/zsh -lc` in the repo (`$SAM2_ROOT`, default `~/projects/jev-samsho2`), picks the first interpreter among
`$SAM2_PYTHON`, `/opt/anaconda3/bin/python3`, `/opt/homebrew/bin/python3`, `python3` that can import `websockets`
and `PIL`, and runs `python3 -m bridge.core --seconds 0 --jev --relay --launch-mame`. The login shell is what gives
the bridge `TYPESAFE_API_KEY` from `~/.zshenv`; this app never reads the key. The bridge launches MAME from `~/mame`
(`-video none`) and owns its lifetime. Stop = the UI sends `{"cmd":"stop"}` over the WebSocket (Lua exits MAME,
bridge loop ends), then `stop_bridge` waits up to 8 s and only then kills the bridge's own PID. Closing the window
kills the bridge too. Why not PyInstaller: the bridge and its Lua files live in this repo and change daily; bundling
is a packaging task for later.

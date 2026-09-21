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

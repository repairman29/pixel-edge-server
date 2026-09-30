# Install Rust on your Mac (one-time)

You need `cargo` to build the agent. Install the Rust toolchain:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Choose **1** (default install). When it’s done, either open a **new terminal** or run:

```bash
source "$HOME/.cargo/env"
```

Then build and run:

```bash
cd /Users/jeffadkins/Projects/pixel-edge-server/pixel-agent-v2
cargo build
./target/debug/pixel-agent-v2
```

Test in another terminal:

```bash
curl -s -X POST http://127.0.0.1:18789/chat -H "Content-Type: application/json" -d '{"message":"hi"}'
```

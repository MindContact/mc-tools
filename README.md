# mc-tools

Small public utility scripts by [MindContact](https://github.com/MindContact).
Each tool lives in its own folder and is self-contained: copy the folder,
read the script header, run it.

Written for Linux (developed on Manjaro/Arch); a script that needs something
specific says so in its header.

## Configuration

Machine-specific paths and settings live in a `.env` file inside each tool's
folder, loaded automatically when present. Start from the template:

```bash
cp clean-caches/.env.example clean-caches/.env   # then edit; .env is git-ignored
```

Every value is optional; each `.env.example` lists the defaults.

## Scripts

| Script | What it does |
|--------|--------------|
| [`clean-caches`](clean-caches/) | Lists and clears developer caches (Gradle, npm/pnpm/yarn, pip, NuGet, Maven, pub, Playwright, browsers, IDEs, pacman/yay, journal, Docker build cache, flatpak), Android AVDs and the Claude desktop VM. |

### clean-caches

```bash
clean-caches/clean-caches.sh                 # list every cache with its size, delete nothing
clean-caches/clean-caches.sh all             # clear everything listed
clean-caches/clean-caches.sh node pip docker # clear only the ones named
```

- Everything it clears is re-downloaded or rebuilt on demand.
- A target skips itself while the program using it is running.
- `docker` never touches volumes or stopped containers.
- `pacman` and `journal` need `sudo`.
- `avd` deletes every AVD except `KEEP_AVD` (default `lite`), and recreates it
  from `KEEP_AVD_IMAGE` if missing, using the SDK at `ANDROID_SDK_ROOT`.

## License

[MIT](LICENSE)

# mc-tools

Small public utility scripts by [MindContact](https://github.com/MindContact).
Each script is self-contained: copy it, read the header, run it.

Written for Linux (developed on Manjaro/Arch); a script that needs something
specific says so in its header. Script output is in Italian.

## Scripts

| Script | What it does |
|--------|--------------|
| [`clean-caches.sh`](clean-caches.sh) | Lists and clears developer caches (Gradle, npm/pnpm/yarn, pip, NuGet, Maven, pub, Playwright, browsers, IDEs, pacman/yay, journal, Docker build cache, flatpak), Android AVDs and the Claude desktop VM. |

### clean-caches.sh

```bash
./clean-caches.sh                 # list every cache with its size, delete nothing
./clean-caches.sh all             # clear everything listed
./clean-caches.sh node pip docker # clear only the ones named
```

- Everything it clears is re-downloaded or rebuilt on demand.
- A target skips itself while the program using it is running.
- `docker` never touches volumes or stopped containers.
- `pacman` and `journal` need `sudo`.
- `avd` deletes every AVD except one named `lite`, and recreates `lite` if
  missing. The Android SDK is taken from `ANDROID_SDK_ROOT` / `ANDROID_HOME`.

## License

[MIT](LICENSE)

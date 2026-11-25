# How to install

1. Install Docker Desktop and open it.
2. Quit it from the whale icon → Quit. In the terminal:

```
sudo /Applications/Docker.app/Contents/MacOS/install vmnetd
```

This installs the helper that lets Docker open port 80. Open Docker again.

3. In `~/.zshrc`, or in `~/.zprofile`, or in `~/.bash_profile` if you use bash. The folder that contains `lar`:

```
export PATH="/path/to/lar:$PATH"
```

That makes `lar` available from any folder. Open a new terminal.

4. Docker Desktop → Settings → Resources → File sharing. The project's `data/` folder and every `path` and `public_path` in `data/config/sites.yaml` must be listed. With Docker closed, `lar install` can add them. If it is open, quit it, run `lar install`, and open it again.

`lar install` checks Docker, `vmnetd`, and those shared folders.

5. `lar init` creates `settings.yaml`, `sites.yaml`, and `data/.env` when they do not exist. If they already have content, `lar install` leaves them unless you answer yes to DANGER.

6. `lar up` starts the environment and writes the domains into `/etc/hosts`. macOS asks for the password when the block changes. `lar down` stops the environment and removes that block.

7. `lar -s site1` opens that site's shell from any folder.

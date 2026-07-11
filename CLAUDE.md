# ssh info

Host arr-box
  HostName arr-box.local
  User gulasz101
  IdentityFile ~/.ssh/id_ed25519.homelab-2nd

Host openmediavault
  HostName openmediavault.local
  User root
  IdentityFile ~/.ssh/id_ed25519.homelab-2nd

# arr-box access

- SSH: `gulasz101@arr-box.local` via `~/.ssh/id_ed25519.homelab-2nd`
- `gulasz101` is in the `docker` group, which is root-equivalent for container/file operations.
- For rare operations that truly need `sudo`, the agent MUST NOT hard-code, print, or commit the password. Ask the Supreme Leader via a secure channel or fetch it from the password manager.

# overview

this is project which I'm using for selhosting the media center which I'm sharing with wife.

project is selhosted in my local network on old pc -> openmediavault is serving as network storage, arr-box is a "media server"

entire thing should be a "git ops driven" with small github repo behind, for simplicity everything is setup around docker compose

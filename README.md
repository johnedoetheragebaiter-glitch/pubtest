# setup_ssh.sh

A bash script for automating SSH key generation, client config, and server hardening. Designed for homelabs — run it once on each machine to get a consistent, secure SSH setup everywhere.

---

## Requirements

- `bash` 4+
- `openssh` (provides `ssh`, `ssh-keygen`, `ssh-copy-id`)
- `curl` (for GitHub key sync)
- `sudo` (for server hardening only)

---

## Quick start

```bash
git clone https://github.com/johnedoetheragebaiter-glitch/pubtest.git
cd pubtest
chmod +x test1
```

---

## Usage examples

### 1. Basic client setup — new machine connecting to a server

Generates an ed25519 key, writes a `Host` block to `~/.ssh/config`, and prints the public key to add to the server.

```bash
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user snorlax \
  --host-name homeserver \
  --port 2222
```

After running, connect with just:
```bash
ssh homeserver
```

---

### 2. Connect to a Proxmox server over Tailscale

```bash
./setup_ssh.sh \
  --host-addr 100.68.130.31 \
  --user root \
  --host-name proxmox \
  --port 22
```

Then connect with:
```bash
ssh proxmox
```

---

### 3. Set up GitHub SSH access

```bash
./setup_ssh.sh \
  --host-addr github.com \
  --user git \
  --host-name github.com \
  --port 22 \
  --github-user yourname
```

Test it:
```bash
ssh -T git@github.com
# Hi yourname!
```

---

### 4. Harden a server you're already logged into

Runs only server-side changes — no key generation, no `~/.ssh/config` edits. Useful when you're already on the machine you want to lock down.

```bash
./setup_ssh.sh \
  --mode server \
  --harden-server \
  --port 2222
```

What it sets in `/etc/ssh/sshd_config`:
- Disables password auth and root login
- Sets `MaxAuthTries 3`, `LoginGraceTime 30`
- Disables X11 and agent forwarding
- Sets verbose logging

---

### 5. Full hardening — client setup + server hardening in one pass

Run this from a desktop connecting to a fresh server. Does everything: generates a key, writes the config, then hardens the remote's sshd.

```bash
./setup_ssh.sh \
  --mode both \
  --host-addr 192.168.1.50 \
  --user admin \
  --host-name myserver \
  --port 2222 \
  --harden-server \
  --harden-crypto \
  --harden-moduli
```

`--harden-crypto` tightens the allowed ciphers, key exchange algorithms, and MACs to modern-only values.
`--harden-moduli` removes weak Diffie-Hellman groups from `/etc/ssh/moduli`.

---

### 6. Automatic key upload to GitHub via PAT

If you export a GitHub personal access token, the script will upload the generated public key to your GitHub account automatically.

```bash
export GITHUB_TOKEN="ghp_..."
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user snorlax \
  --host-name homeserver \
  --github-user yourname
```

> Never pass the token as a CLI argument — it shows up in `ps` output and shell history.

---

### 7. Verify local keys are registered on GitHub

Fetches your registered keys from `https://github.com/yourname.keys` and checks each `~/.ssh/id_*.pub` against the list.

```bash
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user snorlax \
  --github-user yourname \
  --sync-keys
```

Example output:
```
── GitHub key sync ──
[✔] Fetched 3 key(s) from github.com/yourname
[✔]   Registered on GitHub: id_ed25519_homeserver.pub
[✔]   Registered on GitHub: id_ed25519_github.com.pub
[!]   NOT on GitHub:        id_ed25519_oldlaptop.pub
[✔] 2 local key(s) confirmed on GitHub
[!] 1 local key(s) not registered
```

---

### 8. Deploy all GitHub keys to a server

Pulls every public key from your GitHub account and installs them all into the server's `authorized_keys` in one step. Useful for bootstrapping a new machine — any device with a GitHub-registered key can log in immediately.

```bash
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user snorlax \
  --host-name homeserver \
  --github-user yourname \
  --sync-keys \
  --deploy-keys
```

Safe to run multiple times — duplicate keys are automatically removed with `sort -u`.

---

### 9. Set up SFTP-only access for a group

Creates a chrooted SFTP jail for users in a group. Those users can transfer files but cannot get a shell.

```bash
./setup_ssh.sh \
  --mode server \
  --harden-server \
  --sftp-group ftpusers
```

Appends to `/etc/ssh/sshd_config`:
```
Match Group ftpusers
    ChrootDirectory /sftp/%u
    ForceCommand internal-sftp -l VERBOSE
    PasswordAuthentication no
    AllowTcpForwarding no
    PermitTTY no
```

---

### 10. Lock a key to a specific IP and command

Useful for automated scripts or CI systems — the key can only be used from a known IP and only runs one specific command.

```bash
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user deploy \
  --host-name deployserver \
  --from-ip 10.0.0.5 \
  --force-command "/usr/bin/rsync --server"
```

The generated `authorized_keys` entry will look like:
```
from="10.0.0.5",command="/usr/bin/rsync --server",no-agent-forwarding,no-x11-forwarding,no-pty ssh-ed25519 AAAA...
```

---

### 11. Add fail2ban and TOTP (two-factor auth)

Installs and configures fail2ban to ban IPs after 3 failed attempts, and sets up Google Authenticator so login requires both a key and a 6-digit code.

```bash
./setup_ssh.sh \
  --mode server \
  --harden-server \
  --fail2ban \
  --totp
```

> After running `--totp`, keep your current session open and verify login works in a second terminal before closing.

---

### 12. Validate config only (no changes)

Runs `sshd -t` to check syntax, prints the effective values of key directives, and tests the connection — without changing anything.

```bash
./setup_ssh.sh \
  --host-addr 192.168.1.10 \
  --user snorlax \
  --validate
```

---

## All flags

| Flag | Description |
|---|---|
| `-h, --host-addr` | IP or hostname of the remote machine |
| `-u, --user` | SSH username on the remote |
| `-n, --host-name` | Alias for `~/.ssh/config` and `ssh` commands |
| `-p, --port` | SSH port (default: `2222`) |
| `-k, --key-file` | Path to private key (default: `~/.ssh/id_<type>_<host-name>`) |
| `-t, --key-type` | `ed25519` or `rsa` (default: `ed25519`) |
| `-b, --bits` | RSA key size (default: `4096`) |
| `-g, --github-user` | GitHub username |
| `--mode` | `client` / `server` / `both` (default: `client`) |
| `--harden-server` | Harden `/etc/ssh/sshd_config` |
| `--harden-crypto` | Restrict ciphers, KEX algorithms, MACs |
| `--harden-moduli` | Remove weak DH groups from `/etc/ssh/moduli` |
| `--allow-forwarding` | Enable agent/TCP forwarding (off by default) |
| `--sftp-group` | Create SFTP chroot block for this group |
| `--internal-cidr` | Allow password auth from this network range |
| `--admin-group` | Group with elevated SSH permissions |
| `--management-port` | Port the admin group connects on |
| `--allow-users` | Comma-separated `AllowUsers` whitelist |
| `--allow-groups` | Comma-separated `AllowGroups` whitelist |
| `--force-command` | Lock key to a single command |
| `--from-ip` | Restrict key to a source IP |
| `--fail2ban` | Install and configure fail2ban for SSH |
| `--totp` | Set up Google Authenticator two-factor auth |
| `--sync-keys` | Verify local keys against GitHub |
| `--deploy-keys` | With `--sync-keys`: install GitHub keys on the server |
| `--validate` | Check config and test connection, no changes |
| `--no-backup` | Skip config file backups |

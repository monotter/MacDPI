# MacDPI

DPI bypass for Discord and Roblox on macOS. The two apps are routed through a local
[byedpi](https://github.com/hufrea/byedpi) proxy sitting behind
[sing-box](https://github.com/SagerNet/sing-box) in TUN mode. Everything else on the
machine goes out untouched.

The ISP blocks these services in three ways at once: SNI-based DPI, DNS poisoning,
and QUIC. This setup deals with all three. It runs on both Apple Silicon and Intel
Macs.

## Requirements

- macOS (Apple Silicon or Intel)
- Admin password (sing-box needs root to create the TUN interface)

The `ciadpi` and `sing-box` binaries are compiled from source by `bin/Build.sh`,
which pulls whatever build tools it needs (see Building). If they are missing or
built for a different CPU, `Run.sh` builds them automatically on first launch.

## Running

```
./Run.sh
```

This builds the binaries if needed, generates the sing-box config from
`settings.conf`, starts the proxy and the tunnel, switches Wi-Fi to a static IP,
and points DNS at Cloudflare over DoH. Ctrl+C stops everything and restores the
network to DHCP.

Proxy or tunnel on their own:

```
./core/RunDPI.sh
./core/RunSingBox.sh
```

### Layout

```
Run.sh  ServiceInstall.sh  ServiceRemove.sh  ServiceRestart.sh  settings.conf
bin/    ciadpi, sing-box (compiled), Build.sh
core/   GenConfig.sh, RunDPI.sh, RunSingBox.sh
net/    SetStaticIP.sh, UnsetStaticIP.sh
logs/   box.log, service.log
```

Root holds the entry points and `settings.conf`; everything else is grouped by
what it does. Every script can be run directly from the project root.

## Running as a service

To keep the bypass on across reboots, install it as a launchd daemon:

```
./ServiceInstall.sh
./ServiceRemove.sh
```

Install builds the binaries if needed, then registers a system daemon that runs at
boot. Remove stops it, deletes the daemon, and returns the network to DHCP.

While the service is running it watches `settings.conf`. Edit and save that file
and the service restarts itself within a few seconds, regenerating the config with
your changes — no manual step. To force a restart yourself:

```
./ServiceRestart.sh
```

(This auto-restart only happens under the service. A foreground `./Run.sh` applies
config changes when you stop and start it again.)

The project must live outside Desktop, Documents, and Downloads for this to work.
macOS blocks background daemons from reading those folders, so `ServiceInstall.sh`
refuses to run from there. Somewhere like `~/MacDPI` is fine. This only affects the
service; `./Run.sh` by hand works from anywhere.

## Configuration

Everything is driven by one file, `settings.conf`. There is no `config.json` to
edit — the sing-box config is generated from `settings.conf` and piped straight
into sing-box each run, so it never touches disk. `settings.conf` sets:

- `PROXY_PORT` — the local port ciadpi and sing-box share
- `CIADPI_ARGS` — the desync strategy (see Changing the desync strategy)
- `DOH_SERVER` — the DoH resolver, so the ISP cannot poison DNS
- `BLOCK_QUIC` — drop UDP 443 so apps fall back to TCP, where the desync works
- `MODE` — `selective` routes only the listed `APPS` and `DOMAINS` through the
  bypass and sends everything else direct; `global` routes everything through the
  bypass except LAN traffic and ciadpi's own connections
- `APPS` / `DOMAINS` — what to bypass in `selective` mode

`core/GenConfig.sh` builds the config: with no arguments it prints it to stdout
(this is what gets piped into sing-box); `core/GenConfig.sh --out cfg.json` writes
a file instead, handy for inspecting what would be generated. Either way it is
validated against sing-box, and `Run.sh` runs that validation before it touches
the network, so a broken `settings.conf` fails fast.

byedpi runs the desync strategies in `CIADPI_ARGS` as a fallback chain. When a
connection is reset or the TLS handshake fails it moves on to the next one and
caches the winner per IP.

## Static IP

sing-box's TUN routing does not survive DHCP lease renewals well. On renewal the
default route drops for a few seconds, sing-box reads that as "no interface" and
stalls every connection, which shows up as a disconnect in the middle of a game. A
static IP has no lease and therefore no renewal, so it never happens. Run.sh applies
it on start and reverts to DHCP on exit.

The address is the router's subnet with host `.240`, chosen to land outside the
usual DHCP pool. If your pool is different, change `STATIC_HOST` at the top of
`net/SetStaticIP.sh`.

To do it by hand:

```
./net/SetStaticIP.sh
./net/UnsetStaticIP.sh
```

## DNS

The ISP returns fake addresses for the blocked domains and blocks plain DNS on port
53, so the only resolver that still gives real answers is DoH over 443. sing-box
resolves over DoH and hijacks port 53, but it can only touch DNS that passes through
the tunnel, and queries aimed at the LAN router never do. Setting the system DNS to
1.1.1.1, a non-local address, forces those queries through the tunnel where the
hijack catches them. Run.sh handles this and puts DNS back on exit.

## Building

```
./bin/Build.sh
```

One script builds both binaries. It clones the pinned versions of byedpi and
sing-box from GitHub, compiles them into `bin/` as `ciadpi` and `sing-box`, and
deletes the sources afterwards. It builds for whatever machine it runs on, so the
same repo works on Apple Silicon and Intel.

If a build tool is missing it asks before installing, step by step, and stops if you
decline:

- the C compiler for byedpi (Xcode Command Line Tools)
- Go for sing-box (through Homebrew, offering to install Homebrew first if absent)

To change versions, edit `SINGBOX_TAG` and `BYEDPI_REF` at the top of
`bin/Build.sh` and run it again.

## Changing the desync strategy

Edit `CIADPI_ARGS` in `settings.conf`. `--fake` and `--timeout` are compiled out
on macOS, so any guide that leans on fake packets will not work here. What does
work: `--split`, `--disorder`, `--oob`, `--disoob`, `--tlsrec`, `--mod-http`.

To try a strategy without disturbing the running setup, put it on a spare port and
send a request through it:

```
./bin/ciadpi --port 1081 <flags> &
curl -sk -o /dev/null -w "%{http_code}\n" -x socks5h://127.0.0.1:1081 https://discord.com
```

Anything other than `000` means it got through.

## Logs

sing-box writes to `logs/box.log` at `warn` level. Run.sh clears it on start and
caps it at 10 MB while running, so it never grows without bound. The launchd
service writes its own output to `logs/service.log`.

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

The `ciadpi` and `sing-box` binaries are compiled from source by `Build.sh`, which
pulls whatever build tools it needs (see Building). If they are missing or built for
a different CPU, `Run.sh` builds them automatically on first launch.

## Running

```
./Run.sh
```

This builds the binaries if needed, starts the proxy and the tunnel, switches Wi-Fi
to a static IP, and points DNS at Cloudflare over DoH. Ctrl+C stops everything and
restores the network to DHCP.

Proxy or tunnel on their own:

```
./RunDPI.sh
./RunSingBox.sh
```

## Running as a service

To keep the bypass on across reboots, install it as a launchd daemon:

```
./ServiceInstall.sh
./ServiceRemove.sh
```

Install builds the binaries if needed, then registers a system daemon that runs at
boot. Remove stops it, deletes the daemon, and returns the network to DHCP.

The project must live outside Desktop, Documents, and Downloads for this to work.
macOS blocks background daemons from reading those folders, so `ServiceInstall.sh`
refuses to run from there. Somewhere like `~/MacDPI` is fine. This only affects the
service; `./Run.sh` by hand works from anywhere.

## What the config does

`config.json` decides where traffic from the tunnel goes:

- Discord and Roblox (matched by process name and domain) go through the proxy
- UDP 443 is rejected so those apps drop QUIC and fall back to TCP, which is where
  the desync actually works
- DNS is answered over DoH so the ISP cannot poison it
- anything else goes direct

byedpi runs three desync strategies. When a connection is reset or the TLS
handshake fails it moves on to the next one and caches the winner per IP.

## Static IP

sing-box's TUN routing does not survive DHCP lease renewals well. On renewal the
default route drops for a few seconds, sing-box reads that as "no interface" and
stalls every connection, which shows up as a disconnect in the middle of a game. A
static IP has no lease and therefore no renewal, so it never happens. Run.sh applies
it on start and reverts to DHCP on exit.

The address is the router's subnet with host `.240`, chosen to land outside the
usual DHCP pool. If your pool is different, change `STATIC_HOST` at the top of
SetStaticIP.sh.

To do it by hand:

```
./SetStaticIP.sh
./UnsetStaticIP.sh
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
./Build.sh
```

One script builds both binaries. It clones the pinned versions of byedpi and
sing-box from GitHub, compiles them into the project root as `ciadpi` and
`sing-box`, and deletes the sources afterwards. It builds for whatever machine it
runs on, so the same repo works on Apple Silicon and Intel.

If a build tool is missing it asks before installing, step by step, and stops if you
decline:

- the C compiler for byedpi (Xcode Command Line Tools)
- Go for sing-box (through Homebrew, offering to install Homebrew first if absent)

To change versions, edit `SINGBOX_TAG` and `BYEDPI_REF` at the top of Build.sh and
run it again.

## Changing the desync strategy

Edit the ciadpi line in RunDPI.sh. `--fake` and `--timeout` are compiled out on
macOS, so any guide that leans on fake packets will not work here. What does work:
`--split`, `--disorder`, `--oob`, `--disoob`, `--tlsrec`, `--mod-http`.

To try a strategy without disturbing the running setup, put it on a spare port and
send a request through it:

```
./ciadpi --port 1081 <flags> &
curl -sk -o /dev/null -w "%{http_code}\n" -x socks5h://127.0.0.1:1081 https://discord.com
```

Anything other than `000` means it got through.

## Logs

sing-box writes to `box.log` at `warn` level. Run.sh clears it on start and caps it
at 10 MB while running, so it never grows without bound. The launchd service also
writes its own output to `service.log`.

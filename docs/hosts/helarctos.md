# helarctos

Minisforum MS-S1 MAX: Ryzen AI Max+ 395 (Radeon 8060S iGPU, gfx1151), 128 GB unified LPDDR5x, 2× 10GbE (RTL8127), Debian 13 with the trixie-backports kernel and firmware. CI runner and local inference for the agent pipeline. Named for the sun bear genus: black with a tan muzzle, like Laiko. Debian, the backports kernel and GTT are verified live; services are being deployed. Plan and open work: [#155](https://github.com/hsimah/the-loft/issues/155).

[host.conf](../../hosts/helarctos/host.conf) runs the [Kennl](../services/kennl.md) runner (the forge is on space-needle), Sputnik `gpu` ([llama-swap](../services/sputnik.md#gpu-engine-on-helarctos)), Snoot and Houstn `metrics`. Trusted LAN; never on the tunnel.

## Storage

| Device | Mount | Contents |
|---|---|---|
| M.2 PCIe 4.0 x4: Crucial P310 2 TB | `/` | OS, `/opt/kennl/runner`, Docker and job caches, `/den/sputnik/models` (GGUF weights) |
| M.2 PCIe 4.0 x1 | empty | Planned: model weights, mounted at `/den` by label. Move `/den` aside before setup mounts it |

## Before the first setup

1. Update the BIOS/EC firmware. In the BIOS set the UMA frame buffer to its 1 GB minimum (AMD CBS → NBIO Common Options → GFX Configuration), the performance power profile, and power-on after AC loss. A firmware update resets these.
2. Install from the Debian 13 amd64 netinst image over Wi-Fi. The installer's 6.12 kernel has no driver for the 10GbE ports; the MT7925 Wi-Fi works and its firmware is on the image. Hostname `helarctos`. Leave the root password empty so `adminhabl` gets sudo. Use guided partitioning, entire disk, all files in one partition. For software, select only SSH server and standard system utilities.
3. Clone to `/srv/the-loft` and run `sudo bash setup.sh` with no `.env` files yet. It skips the services. The [bootstrap](../../hosts/helarctos/bootstrap) installs the trixie-backports kernel and firmware and the GTT parameters. Reboot, then confirm `uname -r` is 6.18 or newer; older kernels lack the driver or hang on shutdown.
4. Create each service's `.env` from its example (Sputnik `COMPOSE_PROFILES=gpu`), then rerun setup.
5. Wired: add a DHCP stanza for the 10GbE port to `/etc/network/interfaces` and connect it. Move the router reservation from the Wi-Fi MAC to that port's MAC, keeping the address. Once SSH works over the wire, remove the Wi-Fi stanza and the `WIFI_*` fields from host.conf, then rerun setup.

## iGPU memory

The [bootstrap](../../hosts/helarctos/bootstrap) sets `amdgpu.gttsize` and `ttm.pages_limit` from `GPU_GTT_GIB` in host.conf, so the iGPU can map that much system RAM. Kernels differ on which parameter wins; check after a reboot:

```bash
cat /proc/cmdline
echo $(( $(cat /sys/class/drm/card*/device/mem_info_gtt_total) / 1024**3 )) GiB
ls -l /dev/kfd /dev/dri/renderD128
ethtool <iface> | grep -E 'Speed|Link detected'
```

## Ports

| Port | Service | Reached by |
|---|---|---|
| 8080 | llama-swap | Agents and LAN clients, with the API key |

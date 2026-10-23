# helarctos

Minisforum MS-S1 MAX: Ryzen AI Max+ 395 (Radeon 8060S iGPU, gfx1151), 128 GB unified LPDDR5x, 2× 10GbE (RTL8127), Ubuntu 26.04 LTS. On-prem forge, CI runner and local inference for the agent pipeline. Named for the sun bear genus: black with a tan muzzle, like Laiko. **Proposed: not provisioned.** Plan and open work: [#155](https://github.com/hsimah/the-loft/issues/155).

[host.conf](../../hosts/helarctos/host.conf) runs [Kennl](../services/kennl.md), Sputnik `gpu` ([llama-swap](../services/sputnik.md#gpu-engine-on-helarctos)), Snoot and Houstn `metrics`. Trusted LAN, wired; never on the tunnel.

## Storage

| Device | Mount | Contents |
|---|---|---|
| M.2 PCIe 4.0 x4 | `/` | OS, `/opt/kennl` (Forgejo, Postgres, runner), Docker and job caches |
| M.2 PCIe 4.0 x1 | `/den` (label `den`) | `/den/sputnik/models`: GGUF weights, read only at load time |

## Before the first setup

1. Update the BIOS/EC firmware. In the BIOS set the UMA frame buffer to its minimum, the performance power profile, and power-on after AC loss.
2. Install Ubuntu 26.04 LTS Server on the x4 disk, with `adminhabl` as the only account. Confirm the kernel is 6.18 or newer (`uname -r`); older kernels lack the 10GbE driver or hang on shutdown.
3. Reserve its LAN address on the router, then format and label the x1 disk (setup mounts it, never formats it):

   ```bash
   lsblk -o NAME,SIZE,MODEL
   sudo mkfs.xfs -L den /dev/<x1 partition>
   ```

4. Clone to `/srv/the-loft`, create each service's `.env` from its example, then `sudo bash setup.sh` and reboot so the GTT kernel parameters apply.

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
| 3000 | Forgejo HTTP | space-needle's Caddy (`kennl.loft.hsimah.com`) |
| 2222 | Forgejo git SSH | `ssh://git@helarctos:2222/...` |
| 8080 | llama-swap | Agents and LAN clients, with the API key |

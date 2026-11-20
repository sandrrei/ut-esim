# ut-esim

An eSIM profile manager for **Ubuntu Touch**. It lets you download, enable, disable and delete eSIM profiles on a removable eSIM card (for example **9eSIM**) **directly in the phone's SIM tray**, with no USB reader and no Android phone.

`ut-esim` is a small wrapper around [lpac](https://github.com/estkme-group/lpac), built with its **gbinder** backend. lpac talks to the card through the Android radio service (HIDL `IRadio`) that Halium exposes, the same approach that already works on Sailfish OS.

> **Status: early / experimental.** Card access in the SIM tray works on a Pixel 3a XL with Ubuntu Touch 24.04 (see [Compatibility](#compatibility)). Downloading a profile on the phone itself has not been tested yet.

---

## Features

- Show card information (EID, free memory, firmware)
- List installed profiles in a readable table
- Download a profile from an activation code (`LPA:1$...`), with an optional confirmation code
- Enable, disable, rename and delete profiles
- Send pending notifications to the operator automatically after each change
- Clear hints for the most common errors (refused code, wrong SM-DP+ address, wrong slot)

Planned:
- USB card reader mode (`--usb`) for devices where the modem does not allow access to the card
- A graphical app (QML) published on the **OpenStore**

---

## How it works

```
                 ut-esim (bash)
                       │
            ┌──────────┴──────────┐
            ▼                     ▼
   lpac  LPAC_APDU=gbinder   lpac  LPAC_APDU=pcsc   (planned)
            │ libgbinder (system)  │ libpcsclite
            ▼                     ▼
   IRadio/slotN (Halium)      pcscd + ccid driver
            │                     │ USB OTG
            ▼                     ▼
   Modem ─► card in SIM tray  USB reader ─► card
```

lpac opens a logical channel on the card through `IRadio` and sends the SGP.22 (GSMA Remote SIM Provisioning) APDU commands. Profiles are downloaded over HTTPS straight from the operator's SM-DP+ server.

---

## Requirements

**Phone**
- Ubuntu Touch 24.04 (arm64) on a Halium device with the `android.hardware.radio` HIDL service
- The system `libgbinder` and `libglibutil` (already present on Ubuntu Touch, used by oFono)
- A removable eSIM card (9eSIM, 5ber, ...) in the SIM tray
- `sudo` access and an internet connection (Wi-Fi) to download profiles

**Build machine**
- Docker with arm64 emulation

---

## Building lpac

lpac is built inside an **Ubuntu 24.04 arm64** container, the same base as Ubuntu Touch 24.04, so nothing has to be installed on the phone's read-only root filesystem.

```bash
# Once: allow Docker to run arm64 images
docker run --privileged --rm tonistiigi/binfmt --install arm64

# Build (takes 10-30 minutes under emulation)
./build-lpac.sh
```

The result is `lpac-ut.tar.gz`. It contains lpac installed for the prefix `/home/phablet/.local/lpac`.

What the build script takes care of:

| Problem | Fix in `build-lpac.sh` |
| --- | --- |
| `libgbinder-dev` is not packaged in Ubuntu 24.04 | Build `libglibutil` and `libgbinder` from source, **for compiling only** |
| lpac's CMake looks for the Criterion test framework | Install `libcriterion-dev` and pass `-DBUILD_TESTING=OFF` |
| lpac loads its drivers from `<first RUNPATH>/driver` | Install with the final prefix and RPATH, then move `driver_*.so` into `lib/driver/` |
| The freshly built `libgbinder` needs a newer `libglibutil` than the phone has (`undefined symbol: gutil_cleanup_add`) | Do **not** ship them: at runtime the driver uses the phone's own `libgbinder`/`libglibutil` |

---

## Installation on the phone

**The script** can be installed straight from this repository:

```bash
mkdir -p ~/.local/bin
wget -O ~/.local/bin/ut-esim https://raw.githubusercontent.com/sandrrei/ut-esim/main/ut-esim
chmod 755 ~/.local/bin/ut-esim
```

**lpac** has to be built first (see [Building lpac](#building-lpac)) until prebuilt releases are available.

1. Copy `lpac-ut.tar.gz` (and the `ut-esim` script, if you did not download it as above) to the phone. For example, over the local network:

   ```bash
   # on the build machine
   python3 -m http.server 8000

   # on the phone
   cd ~
   wget http://<build-machine-ip>:8000/lpac-ut.tar.gz
   wget http://<build-machine-ip>:8000/ut-esim
   ```

2. Install:

   ```bash
   mkdir -p ~/.local ~/.local/bin
   tar -xzf ~/lpac-ut.tar.gz -C ~/.local
   install -m 755 ~/ut-esim ~/.local/bin/ut-esim
   ```

3. Check that lpac finds the gbinder driver, then read the card (insert it in the SIM tray first):

   ```bash
   ~/.local/bin/ut-esim drivers
   ~/.local/bin/ut-esim info
   ```

   If `info` shows your card's EID, your device is compatible.

`ut-esim` asks for your password and re-runs itself with `sudo`, because the radio service needs root.

---

## Usage

```
ut-esim [options] <command> [arguments]

Commands:
  info                       Show eUICC information (EID, free memory)
  list                       List installed profiles
  add <activation-code>      Download a profile ('LPA:1$smdp$matching-id')
  enable <ICCID>             Enable a profile
  disable <ICCID>            Disable a profile
  delete <ICCID>             Delete a profile (permanent!)
  nickname <ICCID> <name>    Set a profile nickname
  notify                     Send pending notifications to the operator
  drivers                    List the lpac drivers that were found
  raw <lpac arguments...>    Run lpac directly with the selected backend

Options:
  --usb                      Use a USB PC/SC card reader instead of the SIM slot
  --slot <n>                 SIM slot to use in slot mode (default: auto)
  --reader <n>               Reader index in USB mode
  --confirm <code>           Confirmation code for 'add'
  --json                     Print the raw lpac JSON output
  -y, --yes                  Do not ask for confirmation
```

Typical session:

```bash
ut-esim info
ut-esim add 'LPA:1$rsp-xxxx.example.com$MATCHING-ID'
ut-esim list
ut-esim enable 8935xxxxxxxxxxxxxxxx
```

- Always put the activation code in **single quotes**, otherwise the shell interprets the `$`.
- A downloaded profile starts **disabled**: enable it before use.
- After enabling or switching profiles, the modem may need a minute (or a reboot) to pick up the new profile.

Example output:

```
$ ut-esim list
ICCID                  STATE     PROVIDER       NAME / NICKNAME
89351060001200067904   enabled   MEO            MEO
```

---

## USB reader mode (planned)

For devices where the modem refuses logical channels, `ut-esim --usb` will use a USB PC/SC reader (for example the Alcor Link AK9563 sold with 9eSIM) connected through USB OTG.

Ubuntu Touch does not ship `pcscd` and its root filesystem is read-only, so this mode needs a self-contained build of `pcsc-lite` and the `ccid` driver inside the lpac prefix (`$LPAC_HOME/sbin/pcscd`), plus lpac built with `-DLPAC_WITH_APDU_PCSC=ON`. The script already supports `--usb`; the bundled build is not done yet.

Until then, the same lpac commands work on any Linux PC with the reader (`sudo apt install pcscd`, then `LPAC_APDU=pcsc lpac ...`).

---

## Compatibility

| Device | Ubuntu Touch | Card | Mode | `info` | `list` | `add` | `enable` / `disable` | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Google Pixel 3a XL (bonito) | 24.04 | 9eSIM v0 | SIM tray | Yes | Yes | Not tested | Not tested | `IRadio/slot1`, logical channel 2 |
| PC, Ubuntu 24.04 (reference) | — | 9eSIM v0 | USB (Alcor Link AK9563) | Yes | Yes | Yes | Yes | Official lpac 2.3.0, `LPAC_APDU=pcsc` |

Please report other devices by opening an issue with the output of `ut-esim drivers` and `ut-esim info`. **Never post your activation code.**

---

## Troubleshooting

| Error | Likely cause | What to do |
| --- | --- | --- |
| `No APDU driver found` | Drivers are not in `<prefix>/lib/driver/` | `mkdir -p ~/.local/lpac/lib/driver && mv ~/.local/lpac/lib/driver_*.so ~/.local/lpac/lib/driver/` |
| `Segmentation fault` on `drivers` | One driver fails to load (lpac does not handle it) | Load each driver with Python `ctypes.CDLL(...)` to see the real error |
| `undefined symbol: gutil_cleanup_add` | A bundled `libgbinder` picked up the older system `libglibutil` | Remove the bundled `libgbinder*`/`libglibutil*` from `~/.local/lpac/lib` and use the system ones |
| `Failed to open APDU logical channel` | Wrong slot, or the modem/vendor blobs do not allow logical channels | Try `--slot 1` and `--slot 2`; otherwise use a USB reader |
| `Couldn't resolve host name` | Typo in the SM-DP+ address of the code | Check it with `getent hosts <address>` (e.g. `rsp-...`, not `rps-...`) |
| `es9p_authenticate_client` → `Refused` (8.2.6 / 3.8) | Code already used, issued for another EID, or the operator does not accept removable eUICCs | Ask for a new code that is not tied to another device, or for the card's EID |
| Profile installed but no network | Profile is `disabled` | `ut-esim enable <ICCID>`, then reboot if needed |

---

## Security

- An **activation code** (`LPA:1$...`) works like a password: whoever has it can download the profile. Do not share it or post it in issues.
- The **EID** cannot be changed: it is part of a certificate signed by the eUICC manufacturer.
- **Deleting** a profile is permanent. To get it back, the operator has to issue a new code.

---

## Roadmap

1. [x] Build lpac with the gbinder backend for arm64
2. [x] Read the card (`info`, `list`) in the SIM tray on a real device
3. [x] `ut-esim` script with the basic commands
4. [ ] Test `add`, `enable` and `disable` on the phone
5. [ ] Bundled `pcsc-lite` + `ccid` for USB reader mode
6. [ ] QML app (built with `clickable`)
7. [ ] OpenStore release (the app needs root and access to the radio service, so it will be an *unconfined* app subject to manual review)

---

## Credits

- [lpac](https://github.com/estkme-group/lpac) by estkme-group: the LPA that does the real work
- [libgbinder](https://github.com/mer-hybris/libgbinder) and [libglibutil](https://github.com/sailfishos/libglibutil)
- The Sailfish OS community, who first used lpac's gbinder backend on Halium/libhybris devices
- [pcsc-lite](https://github.com/LudovicRousseau/PCSC) and [CCID](https://github.com/LudovicRousseau/CCID) by Ludovic Rousseau (USB mode)

## License

The `ut-esim` scripts are released under the MIT license. lpac and the other components keep their own licenses.

This project is not affiliated with any operator, with the GSMA or with any eSIM card manufacturer. Use it at your own risk.

# Allowed Networks

An organization can restrict Ziti Desktop Edge (macOS) and Ziti Mobile Edge (iOS) to its own Ziti networks, so a managed device can't dial or host services on any other network. The restriction is enforced by the tunnel, not just the app's screens, and it's keyed on the networks' CA certificates rather than controller hostnames, so pointing a hostname somewhere else or editing an identity file doesn't get around it.

It's set with the `allowedCAs` key in a locked tunnel configuration profile (see [configuration-profiles.md](configuration-profiles.md)).

## How it works

Every Ziti identity carries a CA bundle: the certificates it trusts for its network's controllers and routers. An identity can only make TLS connections to servers whose certificates chain to its bundle, so if every certificate in the bundle belongs to your organization, the identity can only reach your networks.

`allowedCAs` lists the SHA-256 fingerprints of your networks' CA certificates. An identity is allowed when its CA bundle is not empty and every certificate in it either is listed or chains, within the bundle, to a listed one. Listing a network's root is usually enough; listing an intermediate allows only what it signed.

The bundle must be plain PEM certificates (`-----BEGIN CERTIFICATE-----` blocks). Anything else in it, such as other PEM blocks, a file reference or extra text, makes it unreadable, and the identity isn't allowed. The tunnel then gives the identity exactly the certificates it checked.

An identity that isn't allowed:

- isn't loaded by the tunnel, and shows as "Blocked by your organization" in the app, with its on/off switch disabled. Its files are kept, so it comes back if the policy changes;
- can't be added: enrolling with a network that isn't allowed fails with "This network isn't allowed by your organization." and the app removes what the enrollment created on the device.

If a controller later sends an identity a new CA bundle that isn't allowed (e.g., after a CA rotation that the policy doesn't list yet), the tunnel stops that identity and shows a notification.

HA clusters need nothing extra: their controllers and routers share the network's CAs.

## Setting it

Add `allowedCAs` to the `VendorConfig` of a tunnel configuration profile with `locked` set to true:

```xml
<key>VendorConfig</key>
<dict>
    <key>locked</key>
    <true/>
    <key>allowedCAs</key>
    <array>
        <string>15:71:F3:C0:A1:A7:AB:7F:1C:C0:41:A2:BE:4C:20:66:32:4F:28:A6:6D:1E:03:02:B5:89:A8:53:A1:99:BC:40</string>
    </array>
    <!-- ip, subnet, mtu, dns and the other tunnel settings -->
</dict>
```

- Fingerprints are hex, in any case, with or without colons. A single comma-separated string also works.
- Without `locked`, `allowedCAs` is ignored: an unlocked configuration can be edited or replaced.
- If `allowedCAs` is set but contains no valid fingerprint (including an empty list), no network is allowed, so a typo can't silently lift the restriction. Invalid entries are skipped and logged.
- Changes take effect when the tunnel restarts.

## Getting the fingerprints

Any of these:

- **From a device that works.** Snapshot (macOS: menu bar > Snapshot...; iOS: Advanced > Snapshot) lists each identity's CA certificates with their fingerprints:

  ```
  Identity: laptop [Zk3...]
    ...
    CA: intermediate-ca-instance-1 6A:E4:F5:...:5B:BA
    CA: root-ca 24:E2:D5:...:ED:81
  ```

- **From the network's CA files**, if you run the network:

  ```
  openssl x509 -in root-ca.cert -noout -subject -fingerprint -sha256
  ```

- **From the controller**, listing every certificate it hands out to identities:

  ```
  curl -sk https://ctrl.example.com/.well-known/est/cacerts | base64 -d \
    | openssl pkcs7 -inform DER -print_certs \
    | awk '/-----BEGIN/{c=""} {c=c $0 "\n"} /-----END/{cmd="openssl x509 -noout -subject -fingerprint -sha256"; printf "%s", c | cmd; close(cmd)}'
  ```

  `-k` trusts whatever answers at that address, so compare the result with one of the other two before relying on it.

## Rotating CAs

List the old and new fingerprints together, let the profile reach your devices, then rotate the network's CA, and drop the old fingerprint once nothing uses it. A device that gets a new bundle before its profile lists the new CA stops that identity until it does.

## What has to be true

The restriction only holds if these do. Check them before relying on it.

**Your networks**

- **No CA shared with other networks.** If a CA you list also signs another network's controllers or routers, identities on that network are allowed too. Give each network its own root.
- **No publicly trusted certificates for identities.** If the controllers or routers your devices use present certificates from a public CA, the networks' CA bundles include that public root, and allowing it allows every network using the same public CA. Keep public certificates off the listeners managed devices use.

Self-hosted networks: a quickstart or `ziti pki`-based setup creates a dedicated root per network, which meets both. Check again if you add third-party or public CAs to the controller's trust bundle.

**Your devices**

The setting closes the Ziti Desktop Edge and Ziti Mobile Edge path only. A user who can run other software could use another OpenZiti tunneler or SDK app (some need no admin rights). So, with your device management:

- users don't have admin rights;
- only approved software can run;
- other VPN apps are blocked.

On iOS this is mostly given: apps come only from the App Store, and device management can restrict which ones are installed.

## Troubleshooting

- **An identity shows "Blocked by your organization".** The snapshot's `Blocked:` line gives the reason: usually the certificate that isn't allowed, which you either list (or the CA it chains to), or it belongs to a network you don't allow. "no CA bundle" or "CA bundle can't be read" means the identity's bundle is missing or isn't plain PEM certificates.
- **Nothing is blocked.** Check the snapshot for `Allowed CAs:`. "ignored, the tunnel settings aren't locked" means the profile needs `locked`. No line at all means the key isn't in the installed configuration.
- **Everything is blocked.** `Allowed CAs: 0` means no listed fingerprint was valid; the app log has a warning for each invalid entry.

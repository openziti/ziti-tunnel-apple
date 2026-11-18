# Managed App Configuration

An organization can configure Ziti Desktop Edge (macOS) and Ziti Mobile Edge (iOS) through device management (MDM): which networks the app should join, and whether users can add or remove identities themselves.

This is separate from the tunnel configuration profile in [configuration-profiles.md](configuration-profiles.md), which sets the tunnel's network settings. The two can be used together.

Ready-to-edit examples: [`examples/ziti-macos-appconfig.mobileconfig`](examples/ziti-macos-appconfig.mobileconfig) and [`examples/ziti-ios-appconfig.plist`](examples/ziti-ios-appconfig.plist). Replace the controller and provider with your own, and on macOS the `PayloadIdentifier` and `PayloadUUID` values.

## Keys

The same keys on both platforms. Booleans can be native plist booleans, `1`/`0`, or the strings `true`/`false` or `yes`/`no`.

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `networks` | array of dictionaries | | Networks to join, one entry each (below) |
| `disableAddIdentity` | boolean | `false` | Users can't add identities. Identities for `networks` are still added |
| `disableRemoveIdentity` | boolean | `false` | Users can't remove identities on the `networks` controllers. Other identities stay removable |

Each `networks` entry uses the same fields as a `ziti://enroll` link:

| Key | Type | Notes |
|-----|------|-------|
| `controller` | string | Controller URL (`https` only) |
| `jwt` | string | Network JWT. One-time enrollment tokens aren't accepted, since a profile is shared by many devices |
| `provider` | string | Name of the identity provider to enroll with, if the network offers it |
| `type` | string | `cert` (Device Certificate) or `token` (User Session) |

Set exactly one of `controller` and `jwt` in each entry. Without `provider` or `type`, users choose them when they enroll, as they would for a network they added themselves.

An invalid entry is skipped, and the other entries still apply. If two entries are for the same controller (host and port), the first one is used. A restriction that isn't a valid boolean counts as `true`, so a mistake doesn't lift it. Each of these is logged, and the snapshot says how many there were.

## Delivering the configuration

### iOS

Use your MDM's managed app configuration for Ziti Mobile Edge (`io.netfoundry.ZitiMobilePacketTunnel`), with the keys above as the configuration dictionary. The app has to be installed and managed by the MDM. MDMs that take the configuration as XML accept the contents of [`examples/ziti-ios-appconfig.plist`](examples/ziti-ios-appconfig.plist).

### macOS

Use a managed preferences payload (`com.apple.ManagedClient.preferences`) for the app's domain, `io.netfoundry.ZitiPacketTunnel`, with the keys under `Forced`, as in [`examples/ziti-macos-appconfig.mobileconfig`](examples/ziti-macos-appconfig.mobileconfig). Most MDMs build this payload from a form for "application preferences" or "custom settings".

Only forced values count: values in the app's own preferences (e.g., set with `defaults write`) are ignored. Deliver the payload with your MDM. macOS treats values from any configuration profile as forced, including one a user installs, so on Macs where users can install profiles they could set these keys too.

The IDs above are for the App Store builds. Builds with other identifiers (see the `*_IDENTIFIER` settings in the README) need their own values.

## Behavior

- **Joining networks.** For each network without an identity yet, the app adds one waiting to enroll, at the top of the list. Enrollment starts when the user taps Enroll, and goes straight to the network's `provider` and `type` when they're set. Nothing opens in the browser until the user asks.
- **Matching.** An identity belongs to a network when one of its controllers has the same host and port (443 if not given), enrolled or not, so the app doesn't add a second one on later launches. The app records the network on the identity, so it stays matched after the network reports other controller addresses (an HA cluster's members, for example) than the one in the configuration.
- **Adding turned off.** macOS: the + button is disabled, and enrollment links are refused. iOS: the Add Identity row is hidden, and files, links and imports through the share sheet are refused. Identities added before the configuration arrived can't be enrolled either. The app explains that adding identities is turned off by the organization.
- **Links for your networks.** A `ziti://enroll` link for a network in `networks` is refused, whatever the restrictions, since the configuration already adds it.
- **Removing turned off.** The remove button (macOS) or Forget This Identity (iOS) is disabled or hidden for identities on the `networks` controllers.
- **Changes.** The app applies a new or changed configuration while it's running, checks again whenever it becomes active, and reads it again before each add, remove or enroll, so none relies on an old copy.
- **Removing the configuration.** The restrictions lift. Identities stay, including the ones added for `networks`. A network dropped from `networks` works the same way: its identity stays and can be removed again.
- **Removed identities.** If a user removes an identity for a network in `networks` (when allowed), the app adds it again, waiting to enroll, the next time it starts or the configuration changes.
- **Diagnostics.** Snapshot and Capture Feedback (macOS) and the support email (iOS) include a line such as `Managed configuration: 1 network, adding identities turned off`, without the values. Whenever the configuration changes, the app log has the same line, plus a warning for each invalid entry or value.

The restrictions shape what the app lets users do, not what the device can do:

- Users can still turn an identity off or disconnect the tunnel, so removing turned off doesn't keep them connected.
- On macOS the app's data files are writable by the user, so a determined user can add or delete identity files directly.
- On iOS, deleting the app removes its identities. Make the app non-removable with your MDM if that matters.
- The share extension learns the restrictions from the app, so until the app has run with the configuration, the share sheet can still import.

To keep devices on your networks whatever the user does, use [allowed networks](allowed-networks.md), which the tunnel enforces.

## Troubleshooting

- **Nothing happens.** Check the snapshot for the `Managed configuration` line. If it's missing, the app isn't receiving the configuration: on macOS, check that the keys are forced for `io.netfoundry.ZitiPacketTunnel` (`profiles list` shows the installed profiles); on iOS, check that the app is managed by the MDM.
- **A network isn't added.** Look in the app log for `Ignoring invalid managed network` and the entry's number.

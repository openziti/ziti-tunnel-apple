# Configuration Profiles

Ziti Desktop Edge (macOS) and Ziti Mobile Edge (iOS) can use a tunnel configuration installed by a configuration profile (`.mobileconfig`), instead of the one the app creates on first launch. Profiles can be installed by hand or delivered by a device management service.

Ready-to-edit examples: [`examples/ziti-ios.mobileconfig`](examples/ziti-ios.mobileconfig) and [`examples/ziti-macos.mobileconfig`](examples/ziti-macos.mobileconfig). They set `locked` and use the app defaults. Replace the `PayloadIdentifier` and `PayloadUUID` values with your own before deploying. The macOS example also needs its `ProviderDesignatedRequirement` filled in (see below).

## VPN payload

Use a `com.apple.vpn.managed` payload:

| Key | iOS | macOS |
|-----|-----|-------|
| `VPNType` | `VPN` | `VPN` |
| `VPNSubType` | `io.netfoundry.ZitiMobilePacketTunnel` | `io.netfoundry.ZitiPacketTunnel` |
| `VPN` > `ProviderBundleIdentifier` | `io.netfoundry.ZitiMobilePacketTunnel.MobilePacketTunnelProvider` | `io.netfoundry.ZitiPacketTunnel.PacketTunnelProvider` |
| `VPN` > `ProviderType` | `packet-tunnel` | `packet-tunnel` |
| `VPN` > `ProviderDesignatedRequirement` | n/a | see below |
| `VPN` > `RemoteAddress` | any value, e.g. `100.64.0.1` | same |
| `VPN` > `AuthenticationMethod` | `Password` | `Password` |
| `UserDefinedName` | name shown in VPN settings | same |
| `VendorConfig` | tunnel settings, see below | same |

The IDs above are for the App Store builds. Builds with other identifiers (see the `*_IDENTIFIER` settings in the README) need their own values.

On macOS, set `ProviderDesignatedRequirement` to the extension's designated requirement, read from the installed app:

```
codesign -d -r- "/Applications/Ziti Desktop Edge.app/Contents/PlugIns/PacketTunnelProvider.appex"
```

Use the text after `designated =>`.

`RemoteAddress` and `AuthenticationMethod` are required by the payload format but not used by the tunnel.

## Tunnel settings (`VendorConfig`)

Numbers and booleans can be native plist types (`<integer>`, `<true/>`) or strings.

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `ip` | string | `100.64.0.1` | **Required.** Tunnel interface IPv4 address |
| `subnet` | string | `255.192.0.0` | **Required.** Tunnel subnet mask |
| `mtu` | integer | `4000` | **Required** |
| `dns` | string | `100.64.0.2` | **Required.** Comma-separated IPv4 addresses |
| `locked` | boolean | `false` | Settings can't be changed in the app (see below) |
| `fallbackDnsEnabled` | boolean | `false` | |
| `fallbackDns` | string | `1.1.1.1` | Required when `fallbackDnsEnabled` is true |
| `interceptMatchedDns` | boolean | `true` | |
| `lowPowerMode` | boolean | `false` | |
| `logLevel` | integer | `3` | 0 none, 1 error, 2 warn, 3 info, 4 debug, 5 verbose, 6 trace |
| `logTlsuv` | boolean | `false` | Apply `logLevel` to TLS logging (otherwise errors only) |
| `logRotateDaily` | boolean | `true` | |
| `logRotateCount` | integer | iOS `2`, macOS `5` | Rotated log files to keep |
| `logRotateSizeMB` | integer | iOS `5`, macOS `50` | Rotate when a log reaches this size |
| `proxyMode` | string | `none` | `none`, `manual` or `system` |
| `proxyHost` | string | | Required when `proxyMode` is `manual` |
| `proxyPort` | integer | | Required when `proxyMode` is `manual` (1-65535) |

If a required key is missing or a value is invalid, the tunnel won't start and reports a configuration error.

## Locked configurations

Without `locked`, a profile's settings can be changed in the app, and the changes stay until the profile is reinstalled. Set `locked` to true to prevent this:

- The app uses the locked configuration even if it already created its own, and removes its own while that one is disconnected.
- Tunnel settings and log rotation settings are read-only in the app.
- Log level changes in the app apply until the tunnel restarts, then revert to the profile's `logLevel`.
- If the configuration is turned off (e.g., another VPN was used on iOS), it has to be selected again in system VPN settings. The app can't turn it back on.

## Behavior notes

- The app picks up profiles installed or removed while it's running when it next becomes active.
- When the profile is removed, the app creates its own default configuration again.
- Proxy credentials can't be set in a profile. They're entered in the app's tunnel settings, which are read-only when `locked` is set.
- Identities are not part of the profile. Users enroll as usual.

# Ziti Packet Tunnelers for macOS and iOS 
Apple Network Extention (PacketTunnelProvider) for routing traffic over an [OpenZiti](https://docs.openziti.io/docs/learn/introduction/) network.

Released versions are vailable from the respective Apple App Stores:
- [Ziti Desktop Edge for macOS](https://apps.apple.com/app/ziti-desktop-edge/id1460484572)
- [Ziti Mobile Edge for iOS](https://apps.apple.com/us/app/ziti-mobile-edge/id1460484353)

## Required `xcconfig` Settings
Create a file called `Configs/workspace-settings-overrides.xcconfig` and populate with appropriate values. 
```
DEVELOPMENT_TEAM = XXXXXXXXXX

PRIVACY_POLICY_URL = http:/$()/...
TERMS_URL = http:/$()/...
SUPPORT_EMAIL = help@...

MAC_APP_IDENTIFIER = ...
MAC_EXT_IDENTIFIER = ....ptp

IOS_APP_IDENTIFIER = ...mobile
IOS_EXT_IDENTIFIER = ...mobile.ptp
IOS_SHARE_IDENTIFIER = ...mobile.share
```

## Getting Help
Please use these community resources for getting help.
- Read the [docs](https://docs.openziti.io/docs/learn/introduction/)
- Participate in discussion on [Discourse](https://openziti.discourse.group/)
- Use GitHub [issues](https://github.com/openziti/ziti-tunnel-apple/issues) for tracking bugs and feature requests.

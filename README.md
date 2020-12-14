# Ziti Packet Tunnelers for macOS and iOS 
Packet tunneling provider app and appex for macOS and iOS, branded as "Ziti Desktop Edge" and "Ziti Mobile Edge".

## Prerequisities
* Cocoapods (`sudo gem install cocoapods`)

## Update Pods
```bash
$ pod install
```

## Update `xcconfig` Settings
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

## Xcode
Open the `ZitiPacketTunnel.xcworkspace` (_not_ the `.xcodeproj` file), and build targets as per usual with Xcode

Copyright&copy; 2020. NetFoundry, Inc.

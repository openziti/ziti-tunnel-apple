# Ziti Packet Tunnelers for macOS and iOS 
Packet tunneling provider app and appex for macOS and iOS

## Prerequisities
* Apple Developer account and membership in NetFoundry Inc development team
* A Mac with Xcode installed and up-to-date
* Build of ziti-sdk-c located at ../ziti-c-sdk/build-Darwin-x86_64 and ../ziti-c-sdk/build-iOS-arm9

## Creating macOS build to share with development team
* Make sure all developer Macs are registered by UUID in NetFoundry Apple Developer account
* Create an Archive (via Xcode), and sign it using "Organizer/Distribute App" for Development
* ```bash
$ brew install dmgbuild
$ dmgbuild -s dmgbuild_settings.py -D app=/path/to/ZitiPacketTunnel.app "Ziti Packet Tunnel" ZitiPacketTunnel.dmg
```

Copyright&copy; 2019. NetFoundry, Inc.

# Ziti Packet Tunnelers for macOS and iOS 
Packet tunneling provider app and appex for macOS and iOS, branded as "Ziti Desktop Edge" and "Ziti Mobile Edge".

## Prerequisities
* Apple Developer account and membership in NetFoundry Inc development team
* A Mac with Xcode installed and up-to-date
* Cocoapods (`sudo gem install cocoapods`)
* Cmake (`brew install cmake`)
* Ninja (`brew install ninja`)
* Build of ziti-sdk-c located at ../ziti-c-sdk/build-Darwin-x86_64 and ../ziti-c-sdk/build-iOS-arm9

## Git submodules
```bash
git submodule update --init --recursive
```

## Build Tunneler SDK
```bash
$ mkdir -p deps/ziti-tunneler-sdk-c/build-macos-x86_64
$ cd !$
$ cmake -GNinja .. && ninja
$ mkdir ../build-iphoneos-arm64
$ cd !$
$ cmake -GNinja -DCMAKE_TOOLCHAIN_FILE=../build-macos-x86_64/_deps/ziti-sdk-c-src/toolchains/iOS-arm64.cmake .. && ninja
```
## Update Pods
```bash
$ pod install
```

## XCode
Open the `ZitiPacketTunnel.xcworkspace` (_not_ the `.xcodeproj` file), and build targets as per usual with XCode

## Creating macOS build to share with development team
* Make sure all developer Macs are registered by UUID in NetFoundry Apple Developer account
* Create an Archive (via Xcode), and sign it using "Organizer/Distribute App" for Development
* Run dmgbuild against the exported archive
```bash
$ brew install dmgbuild
$ dmgbuild -s dmgbuild_settings.py -D app=/path/to/Ziti\ Desktop\ Edge.app "Ziti Desktop Edge" ZitiDesktopEdge.dmg
```

Copyright&copy; 2020. NetFoundry, Inc.

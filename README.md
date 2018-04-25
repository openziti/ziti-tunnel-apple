# README #

### What is this repository for? ###

* Investigative 'spike' on packet tunneling on macos (very very similiar to ios...)
* Spike / POC

### How do I get set up? ###

* Apple XCODE 9.3+, Swift 4
* An Apple profile for a verified company.  Evenetually this will be NetFoundry... The Entitlements required will not allow executing this code using a Personal profile.
* Once you have a valid Team profile and can run this, you can load the ZitiPacketTunnel-macos.mobileconfig via MacOS Profiles Setting (from System Preferneces), or just run the app (will create some usable defaults)
* The tunnel runs as a VPN service (if setup correctly you see 'Ziti Packet Tunnel' under Network Settings.
* You can see some debug info in the MacOS Console (filter for 'ziti'), or Wireshark on tun3 after starting the tunnel

### Contribution guidelines ###

* None

### Who do I talk to? ###

* Dave Hart
* Anybody else on the ANetFoundry dvanced Development team

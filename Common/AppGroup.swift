//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

class AppGroup {
    // TODO: Get TEAMID programatically... (and will be diff on iOS)
#if os(macOS)
    static let APP_GROUP_ID = "MN5S649TXM.ZitiPacketTunnel.group"
#else
    static let APP_GROUP_ID = "group.io.netfoundry.ZitiMobilePacketTunnel"
#endif
}

//
// Copyright NetFoundry Inc.
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

// Minimal stubs for production dependencies not available in the test target.
// Only the signatures actually called by compiled source files are needed.

class _TestLog {
    func error(_ msg: String) {}
    func warn(_ msg: String) {}
    func info(_ msg: String) {}
    func debug(_ msg: String) {}
}
var zLog = _TestLog()

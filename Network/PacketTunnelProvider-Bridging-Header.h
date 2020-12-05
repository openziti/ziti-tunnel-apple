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
#include "ziti/ziti_tunnel.h"
#include "ziti/ziti_tunnel_cbs.h"
#include "ziti/netif_driver.h"

// deal with type mismatch in tunneler SDL (ziti_context vs void *)
void ziti_sdk_c_host_v1_wrapper(void *ziti_ctx, uv_loop_t *loop, const char *service_id, const char *proto, const char *hostname, int port);

char **get_mac_addrs();
void free_string_array(char **addrs);

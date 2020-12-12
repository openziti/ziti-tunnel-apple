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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <ifaddrs.h>
#include <errno.h>

#include "ziti/ziti_tunnel_cbs.h"

void ziti_sdk_c_host_v1_wrapper(void *ziti_ctx, uv_loop_t *loop, const char *service_id, const char *proto, const char *hostname, int port) {
    ziti_sdk_c_host_v1(ziti_ctx, loop, service_id, proto, hostname, port);
}

char **get_mac_addrs() {
    char **mac_addrs = NULL;
    int i = 0;
    struct ifaddrs *if_addrs = NULL;
    struct ifaddrs *if_addr = NULL;
    
    if (getifaddrs(&if_addrs)) {
        printf("getifaddrs() failed with errno =  %i %s\n", errno, strerror(errno));
        return NULL;
    }
    
    for (if_addr = if_addrs; if_addr != NULL; if_addr = if_addr->ifa_next) {
        if (if_addr->ifa_addr != NULL && if_addr->ifa_addr->sa_family == AF_LINK) {
            struct sockaddr_dl* sdl = (struct sockaddr_dl *)if_addr->ifa_addr;
            unsigned char mac[6];
            if (6 == sdl->sdl_alen) {
                i++;
                mac_addrs = realloc(mac_addrs, sizeof(char*) * (i + 1));
                mac_addrs[i] = NULL;
                mac_addrs[i-1] = calloc(sdl->sdl_alen * 3, sizeof(char));
                memcpy(mac, LLADDR(sdl), sdl->sdl_alen);
                sprintf(mac_addrs[i-1], "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
                mac_addrs[i-1][sdl->sdl_alen * 3 - 1] = '\0';
                //printf("%s\t\t: %s\n", if_addr->ifa_name, mac_addrs[*count -1]);
            }
        }
    }
    freeifaddrs(if_addrs);
    return mac_addrs;
}

void free_string_array(char **addrs) {
    if (!addrs) return;
    for (char **i = addrs; *i; i++) {
        free(*i);
    }
    free(addrs);
}

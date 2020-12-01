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
#include "ZitiPosture-Bridging-Header.h"
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#import <sys/proc_info.h>
#import <libproc.h>

bool is_running(const char *path) {
    bool isRunning = false;
    
    int nProcs = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t pids[nProcs];
    bzero(pids, sizeof(pids));
    proc_listpids(PROC_ALL_PIDS, 0, pids, (int)sizeof(pids));
    
    char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = 0; i < nProcs; ++i) {
        if (pids[i] == 0) { continue; }
        bzero(pathBuffer, PROC_PIDPATHINFO_MAXSIZE);
        proc_pidpath(pids[i], pathBuffer, PROC_PIDPATHINFO_MAXSIZE * sizeof(char));
        if (strlen(pathBuffer) > 0) {
            if (!strcmp(pathBuffer, path)) {
                //printf("   GOTCHA! %s\n", pathBuffer);
                isRunning = true;
                break;
            }
        }
    }
    return isRunning;
}

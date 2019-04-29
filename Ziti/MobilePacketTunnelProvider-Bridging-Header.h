//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <nf/ziti.h>

const char* ziti_get_version(int verbose);
const char* ziti_git_branch();
const char* ziti_git_commit();

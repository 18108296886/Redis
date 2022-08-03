#ifndef __REDIS_CLI_COMMANDS_H
#define __REDIS_CLI_COMMANDS_H

#include <stddef.h>
#include "commands.h"

#define REDIS_CLI_COMMANDS

typedef struct cliCommandArg {
    char *name;
    redisCommandArgType type;
    char *token;
    char *since;
    int flags;
    int numsubargs;
    struct cliCommandArg *subargs;
    char *deprecated_since;

    /* Fields used to keep track of input word matches for command-line hinting. */
    int matched;  /* How many input words have been matched by this argument? */
    int matched_token;  /* Has the token been matched? */
    int matched_name;  /* Has the name been matched? */
    int matched_all;  /* Has the whole argument been consumed (no hint needed)? */
} cliCommandArg;

/* Command documentation info used for help output */
struct commandDocs {
    char *name;
    char *summary;
    char *group;
    char *since;
    int numargs;
    cliCommandArg *args; /* An array of the command arguments. */
    struct commandDocs *subcommands;
    char *params; /* A string describing the syntax of the command arguments. */
};

/* Definitions to configure commands.c to generate the above structs. */

#define MAKE_CMD(name,summary,complexity,since,doc_flags,replaced,deprecated,group,group_enum,history,tips,function,arity,flags,acl,key_specs,get_keys,numargs) name,summary,group,since,numargs
#define MAKE_ARG(name,type,key_spec_index,token,summary,since,flags,numsubargs) name,type,token,since,flags,numsubargs
#define redisCommandArg cliCommandArg
#define COMMAND_STRUCT commandDocs

#endif

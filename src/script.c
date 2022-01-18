/*
 * Copyright (c) 2009-2021, Redis Ltd.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "server.h"
#include "script.h"
#include "cluster.h"

scriptFlag scripts_flags_def[] = {
    {.flag = SCRIPT_FLAG_NO_WRITES, .str = "no-writes"},
    {.flag = SCRIPT_FLAG_ALLOW_OOM, .str = "allow-oom"},
    {.flag = SCRIPT_FLAG_ALLOW_STALE, .str = "allow-stale"},
    {.flag = SCRIPT_FLAG_NO_CLUSTER, .str = "no-cluster"},
    {.flag = 0, .str = NULL}, /* flags array end */
};

/* On script invocation, holding the current run context */
static scriptRunCtx *curr_run_ctx = NULL;

static void exitScriptTimedoutMode(scriptRunCtx *run_ctx) {
    serverAssert(run_ctx == curr_run_ctx);
    serverAssert(scriptIsTimedout());
    run_ctx->flags &= ~SCRIPT_TIMEDOUT;
    blockingOperationEnds();
    /* if we are a replica and we have an active master, set it for continue processing */
    if (server.masterhost && server.master) queueClientForReprocessing(server.master);
}

static void enterScriptTimedoutMode(scriptRunCtx *run_ctx) {
    serverAssert(run_ctx == curr_run_ctx);
    serverAssert(!scriptIsTimedout());
    /* Mark script as timedout */
    run_ctx->flags |= SCRIPT_TIMEDOUT;
    blockingOperationStarts();
}

int scriptIsTimedout() {
    return scriptIsRunning() && (curr_run_ctx->flags & SCRIPT_TIMEDOUT);
}

client* scriptGetClient() {
    serverAssert(scriptIsRunning());
    return curr_run_ctx->c;
}

client* scriptGetCaller() {
    serverAssert(scriptIsRunning());
    return curr_run_ctx->original_client;
}

/* interrupt function for scripts, should be call
 * from time to time to reply some special command (like ping)
 * and also check if the run should be terminated. */
int scriptInterrupt(scriptRunCtx *run_ctx) {
    if (run_ctx->flags & SCRIPT_TIMEDOUT) {
        /* script already timedout
           we just need to precess some events and return */
        processEventsWhileBlocked();
        return (run_ctx->flags & SCRIPT_KILLED) ? SCRIPT_KILL : SCRIPT_CONTINUE;
    }

    long long elapsed = elapsedMs(run_ctx->start_time);
    if (elapsed < server.script_time_limit) {
        return SCRIPT_CONTINUE;
    }

    serverLog(LL_WARNING,
            "Slow script detected: still in execution after %lld milliseconds. "
                    "You can try killing the script using the %s command.",
            elapsed, (run_ctx->flags & SCRIPT_EVAL_MODE) ? "SCRIPT KILL" : "FUNCTION KILL");

    enterScriptTimedoutMode(run_ctx);
    /* Once the script timeouts we reenter the event loop to permit others
     * some commands execution. For this reason
     * we need to mask the client executing the script from the event loop.
     * If we don't do that the client may disconnect and could no longer be
     * here when the EVAL command will return. */
    protectClient(run_ctx->original_client);

    processEventsWhileBlocked();

    return (run_ctx->flags & SCRIPT_KILLED) ? SCRIPT_KILL : SCRIPT_CONTINUE;
}

/* Prepare the given run ctx for execution */
int scriptPrepareForRun(scriptRunCtx *run_ctx, client *engine_client, client *caller, const char *funcname, uint64_t function_flags, int ro) {
    serverAssert(!curr_run_ctx);

    if (!(function_flags & SCRIPT_FLAG_IGNORE_FLAGS)) {
        if ((function_flags & SCRIPT_FLAG_NO_CLUSTER) && server.cluster_enabled) {
            addReplyError(caller, "Can not run function on cluster, 'no-cluster' flag is set.");
            return C_ERR;
        }

        if (!(function_flags & SCRIPT_FLAG_ALLOW_OOM) && server.script_oom && server.maxmemory) {
            addReplyError(caller, "-OOM allow-oom flag is not set on the function, "
                                  "can not run it when used memory > 'maxmemory'");
            return C_ERR;
        }

        if (server.masterhost && server.repl_state != REPL_STATE_CONNECTED &&
            server.repl_serve_stale_data == 0 && !(function_flags & SCRIPT_FLAG_ALLOW_STALE))
        {
            addReplyError(caller, "-MASTERDOWN Link with MASTER is down, "
                             "replica-serve-stale-data is set to 'no' "
                             "and 'allow-stale' flag is not set on the function.");
            return C_ERR;
        }

        if (!(function_flags & SCRIPT_FLAG_NO_WRITES)) {
            /* Function may perform writes we need to verify:
             * 1. we are not a readonly replica
             * 2. no disk error detected
             * 3. command is not 'fcall_ro' */
            if (server.masterhost && server.repl_slave_ro && caller->id != CLIENT_ID_AOF
                && !(caller->flags & CLIENT_MASTER))
            {
                addReplyError(caller, "Can not run a function with write flag on readonly replica");
                return C_ERR;
            }

            int deny_write_type = writeCommandsDeniedByDiskError();
            if (deny_write_type != DISK_ERROR_TYPE_NONE && server.masterhost == NULL) {
                if (deny_write_type == DISK_ERROR_TYPE_RDB)
                    addReplyError(caller, "-MISCONF Redis is configured to save RDB snapshots, "
                                     "but it is currently not able to persist on disk. "
                                     "So its impossible to run functions that has 'write' flag on.");
                else
                    addReplyErrorFormat(caller, "-MISCONF Redis is configured to persist data to AOF, "
                                           "but it is currently not able to persist on disk. "
                                           "So its impossible to run functions that has 'write' flag on. "
                                           "AOF error: %s", strerror(server.aof_last_write_errno));
                return C_ERR;
            }

            if (ro) {
                addReplyError(caller, "Can not execute a function with write flag using fcall_ro.");
                return C_ERR;
            }
        }
    }

    run_ctx->c = engine_client;
    run_ctx->original_client = caller;
    run_ctx->funcname = funcname;

    client *script_client = run_ctx->c;
    client *curr_client = run_ctx->original_client;
    server.script_caller = curr_client;

    /* Select the right DB in the context of the Lua client */
    selectDb(script_client, curr_client->db->id);
    script_client->resp = 2; /* Default is RESP2, scripts can change it. */

    /* If we are in MULTI context, flag Lua client as CLIENT_MULTI. */
    if (curr_client->flags & CLIENT_MULTI) {
        script_client->flags |= CLIENT_MULTI;
    }

    server.in_script = 1;

    run_ctx->start_time = getMonotonicUs();
    run_ctx->snapshot_time = mstime();

    run_ctx->flags = 0;
    run_ctx->repl_flags = PROPAGATE_AOF | PROPAGATE_REPL;

    if (ro || (!(function_flags & SCRIPT_FLAG_IGNORE_FLAGS) && (function_flags & SCRIPT_FLAG_NO_WRITES))) {
        /* On fcall_ro or on functions that do not have the 'write'
         * flag, we will not allow write commands. */
        run_ctx->flags |= SCRIPT_READ_ONLY;
    }
    if (!(function_flags & SCRIPT_FLAG_IGNORE_FLAGS) && (function_flags & SCRIPT_FLAG_ALLOW_OOM)) {
        run_ctx->flags |= SCRIPT_ALLOW_OOM;
    }

    /* set the curr_run_ctx so we can use it to kill the script if needed */
    curr_run_ctx = run_ctx;

    return C_OK;
}

/* Reset the given run ctx after execution */
void scriptResetRun(scriptRunCtx *run_ctx) {
    serverAssert(curr_run_ctx);

    /* After the script done, remove the MULTI state. */
    run_ctx->c->flags &= ~CLIENT_MULTI;

    server.in_script = 0;
    server.script_caller = NULL;

    if (scriptIsTimedout()) {
        exitScriptTimedoutMode(run_ctx);
        /* Restore the client that was protected when the script timeout
         * was detected. */
        unprotectClient(run_ctx->original_client);
    }

    preventCommandPropagation(run_ctx->original_client);

    /*  unset curr_run_ctx so we will know there is no running script */
    curr_run_ctx = NULL;
}

/* return true if a script is currently running */
int scriptIsRunning() {
    return curr_run_ctx != NULL;
}

const char* scriptCurrFunction() {
    serverAssert(scriptIsRunning());
    return curr_run_ctx->funcname;
}

int scriptIsEval() {
    serverAssert(scriptIsRunning());
    return curr_run_ctx->flags & SCRIPT_EVAL_MODE;
}

/* Kill the current running script */
void scriptKill(client *c, int is_eval) {
    if (!curr_run_ctx) {
        addReplyError(c, "-NOTBUSY No scripts in execution right now.");
        return;
    }
    if (curr_run_ctx->original_client->flags & CLIENT_MASTER) {
        addReplyError(c,
                "-UNKILLABLE The busy script was sent by a master instance in the context of replication and cannot be killed.");
    }
    if (curr_run_ctx->flags & SCRIPT_WRITE_DIRTY) {
        addReplyError(c,
                "-UNKILLABLE Sorry the script already executed write "
                        "commands against the dataset. You can either wait the "
                        "script termination or kill the server in a hard way "
                        "using the SHUTDOWN NOSAVE command.");
        return;
    }
    if (is_eval && !(curr_run_ctx->flags & SCRIPT_EVAL_MODE)) {
        /* Kill a function with 'SCRIPT KILL' is not allow */
        addReplyErrorObject(c, shared.slowscripterr);
        return;
    }
    if (!is_eval && (curr_run_ctx->flags & SCRIPT_EVAL_MODE)) {
        /* Kill an eval with 'FUNCTION KILL' is not allow */
        addReplyErrorObject(c, shared.slowevalerr);
        return;
    }
    curr_run_ctx->flags |= SCRIPT_KILLED;
    addReply(c, shared.ok);
}

static int scriptVerifyCommandArity(struct redisCommand *cmd, int argc, sds *err) {
    if (!cmd || ((cmd->arity > 0 && cmd->arity != argc) || (argc < cmd->arity))) {
        if (cmd)
            *err = sdsnew("Wrong number of args calling Redis command from script");
        else
            *err = sdsnew("Unknown Redis command called from script");
        return C_ERR;
    }
    return C_OK;
}

static int scriptVerifyACL(client *c, sds *err) {
    /* Check the ACLs. */
    int acl_errpos;
    int acl_retval = ACLCheckAllPerm(c, &acl_errpos);
    if (acl_retval != ACL_OK) {
        addACLLogEntry(c,acl_retval,ACL_LOG_CTX_LUA,acl_errpos,NULL,NULL);
        switch (acl_retval) {
        case ACL_DENIED_CMD:
            *err = sdsnew("The user executing the script can't run this "
                          "command or subcommand");
            break;
        case ACL_DENIED_KEY:
            *err = sdsnew("The user executing the script can't access "
                          "at least one of the keys mentioned in the "
                          "command arguments");
            break;
        case ACL_DENIED_CHANNEL:
            *err = sdsnew("The user executing the script can't publish "
                          "to the channel mentioned in the command");
            break;
        default:
            *err = sdsnew("The user executing the script is lacking the "
                          "permissions for the command");
            break;
        }
        return C_ERR;
    }
    return C_OK;
}

static int scriptVerifyWriteCommandAllow(scriptRunCtx *run_ctx, char **err) {
    if (!(run_ctx->c->cmd->flags & CMD_WRITE)) {
        return C_OK;
    }

    if (run_ctx->flags & SCRIPT_READ_ONLY) {
        /* We know its a write command, on a read only run we do not allow it. */
        *err = sdsnew("Write commands are not allowed from read-only scripts.");
        return C_ERR;
    }

    /* Write commands are forbidden against read-only slaves, or if a
     * command marked as non-deterministic was already called in the context
     * of this script. */
    int deny_write_type = writeCommandsDeniedByDiskError();

    if (server.masterhost && server.repl_slave_ro && run_ctx->original_client->id != CLIENT_ID_AOF
        && !(run_ctx->original_client->flags & CLIENT_MASTER))
    {
        *err = sdsdup(shared.roslaveerr->ptr);
        return C_ERR;
    }

    if (deny_write_type != DISK_ERROR_TYPE_NONE) {
        if (deny_write_type == DISK_ERROR_TYPE_RDB) {
            *err = sdsdup(shared.bgsaveerr->ptr);
        } else {
            *err = sdsempty();
            *err = sdscatfmt(*err,
                    "MISCONF Errors writing to the AOF file: %s\r\n",
                    strerror(server.aof_last_write_errno));
        }
        return C_ERR;
    }

    return C_OK;
}

static int scriptVerifyOOM(scriptRunCtx *run_ctx, char **err) {
    if (run_ctx->flags & SCRIPT_ALLOW_OOM) {
        /* Allow running any command even if OOM reached */
        return C_OK;
    }

    /* If we reached the memory limit configured via maxmemory, commands that
     * could enlarge the memory usage are not allowed, but only if this is the
     * first write in the context of this script, otherwise we can't stop
     * in the middle. */

    if (server.maxmemory &&                            /* Maxmemory is actually enabled. */
        run_ctx->original_client->id != CLIENT_ID_AOF && /* Don't care about mem if loading from AOF. */
        !server.masterhost &&                          /* Slave must execute the script. */
        !(run_ctx->flags & SCRIPT_WRITE_DIRTY) &&        /* Script had no side effects so far. */
        server.script_oom &&                           /* Detected OOM when script start. */
        (run_ctx->c->cmd->flags & CMD_DENYOOM))
    {
        *err = sdsdup(shared.oomerr->ptr);
        return C_ERR;
    }

    return C_OK;
}

static int scriptVerifyClusterState(client *c, client *original_c, sds *err) {
    if (!server.cluster_enabled || original_c->id == CLIENT_ID_AOF || (original_c->flags & CLIENT_MASTER)) {
        return C_OK;
    }
    /* If this is a Redis Cluster node, we need to make sure the script is not
     * trying to access non-local keys, with the exception of commands
     * received from our master or when loading the AOF back in memory. */
    int error_code;
    /* Duplicate relevant flags in the script client. */
    c->flags &= ~(CLIENT_READONLY | CLIENT_ASKING);
    c->flags |= original_c->flags & (CLIENT_READONLY | CLIENT_ASKING);
    if (getNodeByQuery(c, c->cmd, c->argv, c->argc, NULL, &error_code) != server.cluster->myself) {
        if (error_code == CLUSTER_REDIR_DOWN_RO_STATE) {
            *err = sdsnew(
                    "Script attempted to execute a write command while the "
                            "cluster is down and readonly");
        } else if (error_code == CLUSTER_REDIR_DOWN_STATE) {
            *err = sdsnew("Script attempted to execute a command while the "
                    "cluster is down");
        } else {
            *err = sdsnew("Script attempted to access a non local key in a "
                    "cluster node");
        }
        return C_ERR;
    }
    return C_OK;
}

/* set RESP for a given run_ctx */
int scriptSetResp(scriptRunCtx *run_ctx, int resp) {
    if (resp != 2 && resp != 3) {
        return C_ERR;
    }

    run_ctx->c->resp = resp;
    return C_OK;
}

/* set Repl for a given run_ctx
 * either: PROPAGATE_AOF | PROPAGATE_REPL*/
int scriptSetRepl(scriptRunCtx *run_ctx, int repl) {
    if ((repl & ~(PROPAGATE_AOF | PROPAGATE_REPL)) != 0) {
        return C_ERR;
    }
    run_ctx->repl_flags = repl;
    return C_OK;
}

static int scriptVerifyAllowStale(client *c, sds *err) {
    if (!server.masterhost) {
        /* Not a replica, stale is irrelevant */
        return C_OK;
    }

    if (server.repl_state == REPL_STATE_CONNECTED) {
        /* Connected to replica, stale is irrelevant */
        return C_OK;
    }

    if (server.repl_serve_stale_data == 1) {
        /* Disconnected from replica but allow to serve data */
        return C_OK;
    }

    if (c->cmd->flags & CMD_STALE) {
        /* Command is allow while stale */
        return C_OK;
    }

    /* On stale replica, can not run the command */
    *err = sdsnew("Can not execute the command on a stale replica");
    return C_ERR;
}

/* Call a Redis command.
 * The reply is written to the run_ctx client and it is
 * up to the engine to take and parse.
 * The err out variable is set only if error occurs and describe the error.
 * If err is set on reply is written to the run_ctx client. */
void scriptCall(scriptRunCtx *run_ctx, robj* *argv, int argc, sds *err) {
    client *c = run_ctx->c;

    /* Setup our fake client for command execution */
    c->argv = argv;
    c->argc = argc;
    c->user = run_ctx->original_client->user;

    /* Process module hooks */
    moduleCallCommandFilters(c);
    argv = c->argv;
    argc = c->argc;

    struct redisCommand *cmd = lookupCommand(argv, argc);
    if (scriptVerifyCommandArity(cmd, argc, err) != C_OK) {
        return;
    }

    c->cmd = c->lastcmd = cmd;

    /* There are commands that are not allowed inside scripts. */
    if (!server.script_disable_deny_script && (cmd->flags & CMD_NOSCRIPT)) {
        *err = sdsnew("This Redis command is not allowed from script");
        return;
    }

    if (scriptVerifyAllowStale(c, err) != C_OK) {
        return;
    }

    if (scriptVerifyACL(c, err) != C_OK) {
        return;
    }

    if (scriptVerifyWriteCommandAllow(run_ctx, err) != C_OK) {
        return;
    }

    if (scriptVerifyOOM(run_ctx, err) != C_OK) {
        return;
    }

    if (cmd->flags & CMD_WRITE) {
        /* signify that we already change the data in this execution */
        run_ctx->flags |= SCRIPT_WRITE_DIRTY;
    }

    if (scriptVerifyClusterState(c, run_ctx->original_client, err) != C_OK) {
        return;
    }

    int call_flags = CMD_CALL_SLOWLOG | CMD_CALL_STATS;
    if (run_ctx->repl_flags & PROPAGATE_AOF) {
        call_flags |= CMD_CALL_PROPAGATE_AOF;
    }
    if (run_ctx->repl_flags & PROPAGATE_REPL) {
        call_flags |= CMD_CALL_PROPAGATE_REPL;
    }
    call(c, call_flags);
    serverAssert((c->flags & CLIENT_BLOCKED) == 0);
}

/* Returns the time when the script invocation started */
mstime_t scriptTimeSnapshot() {
    serverAssert(curr_run_ctx);
    return curr_run_ctx->snapshot_time;
}

long long scriptRunDuration() {
    serverAssert(scriptIsRunning());
    return elapsedMs(curr_run_ctx->start_time);
}

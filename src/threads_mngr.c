/*
 * Copyright (c) 2021, Redis Ltd.
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

#include "threads_mngr.h"
/* Anti-warning macro... */
#define UNUSED(V) ((void) V)

#ifdef __linux__
#include "zmalloc.h"
#include "atomicvar.h"
#include "server.h"

#include <signal.h>
#include <time.h>
#include <sys/syscall.h>

#define IN_PROGRESS 1
static const clock_t RUN_ON_THREADS_TIMEOUT = 10;

/*================================= Globals ================================= */

static run_on_thread_cb g_callback = NULL;
static volatile size_t g_tids_len = 0;
static redisAtomic size_t g_num_threads_done = 0;

/* This flag is set while ThreadsManager_runOnThreads is running */
static redisAtomic int g_in_progress = 0;

/*============================ Internal prototypes ========================== */

static void invoke_callback(int sig);
/* returns 0 if it is safe to start, IN_PROGRESS otherwise. */
static int test_and_start(void);
static void wait_threads(void);
/* Clean up global variable.
Assuming we are under the g_in_progress protection, this is not a thread-safe function */
static void ThreadsManager_cleanups(void);

/*============================ API functions implementations ========================== */

void ThreadsManager_init(void) {
    /* Register signal handler */
    struct sigaction act;
    sigemptyset(&act.sa_mask);
    /* Not setting SA_RESTART flag means that If a signal handler is invoked while a
    system call or library function call is blocked, use the default behavior
    i.e., the call fails with the error EINTR */
    act.sa_flags = 0;
    act.sa_handler = invoke_callback;
    sigaction(SIGUSR2, &act, NULL);
}

__attribute__ ((noinline))
int ThreadsManager_runOnThreads(pid_t *tids, size_t tids_len, run_on_thread_cb callback) {
    /* Check if it is safe to start running. If not - return */
    if(test_and_start() == IN_PROGRESS) {
        return 0;
    }

    /* Update g_callback */
    g_callback = callback;

    /* Set g_tids_len */
    g_tids_len = tids_len;

    /* Send signal to all the threads in tids */
    pid_t pid = getpid();
    for (size_t i = 0; i < tids_len ; ++i) {
        syscall(SYS_tgkill, pid, tids[i], THREADS_SIGNAL);
    }

    /* Wait for all the threads to write to the output array, or until timeout is reached */
    wait_threads();

    /* Cleanups to allow next execution */
    ThreadsManager_cleanups();

    return 1;
}

/*============================ Internal functions implementations ========================== */


static int test_and_start(void) {
    /* atomicFlagGetSet sets the variable to 1 and returns the previous value */
    int prev_state;
    atomicFlagGetSet(g_in_progress, prev_state);

    /* If prev_state is 1, g_in_progress was on. */
    return prev_state;
}

__attribute__ ((noinline))
static void invoke_callback(int sig) {
    UNUSED(sig);

    g_callback();
    atomicIncr(g_num_threads_done, 1);
}

static void wait_threads(void) {
    struct timespec timeout_time;
    clock_gettime(CLOCK_REALTIME, &timeout_time);

    /* calculate relative time until timeout */
    timeout_time.tv_sec += RUN_ON_THREADS_TIMEOUT;

    /* Wait until all threads are done to invoke the callback or until we reached the timeout */
    size_t curr_done_count;
    struct timespec curr_time;

    do
    {
        atomicGet(g_num_threads_done, curr_done_count);
        clock_gettime(CLOCK_REALTIME, &curr_time);
    } while (curr_done_count < g_tids_len &&
            curr_time.tv_sec <= timeout_time.tv_sec);

    if (curr_time.tv_sec > timeout_time.tv_sec) {
        serverLogFromHandler(LL_WARNING, "wait_threads(): waiting threads timed out");
    }

}

static void ThreadsManager_cleanups(void) {
    g_callback = NULL;
    g_tids_len = 0;
    g_num_threads_done = 0;

    /* Lastly, turn off g_in_progress */
    atomicSet(g_in_progress, 0);

}
#else

void ThreadsManager_init(void) {
    /* DO NOTHING */
}

int ThreadsManager_runOnThreads(pid_t *tids, size_t tids_len, run_on_thread_cb callback) {
    /* DO NOTHING */
    UNUSED(tids);
    UNUSED(tids_len);
    UNUSED(callback);
    return 1;
}

#endif /* __linux__ */

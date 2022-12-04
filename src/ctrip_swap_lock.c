/* Copyright (c) 2022, ctrip.com
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

#include "ctrip_swap.h"

#define LOCK_LINKS_LINER_SIZE 4096

#define LINK_SIGNAL_PROCEEDED 0
#define LINK_SIGNAL_UNLOCK 1

#define LINK_TO_LOCK(link_ptr) ((struct lock*)((char*)(link_ptr)-offsetof(struct lock,link)))

/* callback when link target is ready. */
typedef void (*linkProceed)(struct lockLink *link, void *pd);

static size_t lock_memory_used;

static inline void *lock_malloc(size_t size) {
    void *ptr = zmalloc(size);
#ifdef HAVE_MALLOC_SIZE
    if (ptr) lock_memory_used += zmalloc_size(ptr);
#endif
    return ptr;
}

static inline void *lock_realloc(void *oldptr, size_t size) {
#ifdef HAVE_MALLOC_SIZE
    if (oldptr) lock_memory_used -= zmalloc_size(oldptr);
#endif
    void *ptr = zrealloc(oldptr,size);
#ifdef HAVE_MALLOC_SIZE
    if (ptr) lock_memory_used += zmalloc_size(ptr);
#endif
    return ptr;
}

static inline void lock_free(void *ptr) {
#ifdef HAVE_MALLOC_SIZE
    if (ptr) lock_memory_used -= zmalloc_size(ptr);
#endif
    zfree(ptr);
}


static void lockLinksInit(lockLinks *links) {
    links->links = links->buf;
    links->capacity = LOCK_LINKS_BUF_SIZE;
    links->count = 0;
    links->signaled = 0;
}

static void lockLinksDeinit(lockLinks *links) {
    if (links->links && links->links != links->buf)
        lock_free(links->links);
    lockLinksInit(links);
}

static void lockLinksMakeRoomFor(lockLinks *links, int count) {
    if (count <= links->capacity) return;

    while (links->capacity < count &&
            links->capacity < LOCK_LINKS_LINER_SIZE) {
        links->capacity *= 2;
    }
    while (links->capacity < count &&
            links->capacity >= LOCK_LINKS_LINER_SIZE) {
        links->capacity += LOCK_LINKS_LINER_SIZE;
    }
    serverAssert(links->capacity >= count);

    if (links->links == links->buf) {
        links->links = lock_malloc(sizeof(lock*)*links->capacity);
    } else {
        links->links = lock_realloc(links->links,sizeof(lock*)*links->capacity);
    }
}

static inline void lockLinksPush(lockLinks *links, void *target) {
    lockLinksMakeRoomFor(links,links->count+1);
#ifdef LOCK_DEBUG
    int64_t prev_txid = 0;
    lockLink *target_link = target;
    if (links->count > 0) prev_txid = links->links[links->count]->txid;
    serverAssert(prev_txid <= target_link->txid);
#endif
    links->links[links->count++] = target;
}

static inline void lockLinkTargetInit(lockLinkTarget *target) {
    target->linked = 0;
    target->signaled = 0;
}

static inline void lockLinkTargetLinked(lockLinkTarget *target) {
    serverAssert(target->signaled <= target->linked);
    target->linked++;
}

static inline void lockLinkTargetSignaled(lockLinkTarget *target) {
    target->signaled++;
    serverAssert(target->signaled <= target->linked);
}

static inline int lockLinkTargetReady(lockLinkTarget *target) {
    serverAssert(target->signaled <= target->linked);
    return target->signaled == target->linked;
}

void lockLinkInit(lockLink *link, int txid) {
    link->txid = txid;
    lockLinksInit(&link->links);
    lockLinkTargetInit(&link->target);
}

void lockLinkDeinit(lockLink *link) {
    link->txid = 0;
    lockLinksDeinit(&link->links);
    lockLinkTargetInit(&link->target);
}

void lockLinkLink(lockLink *from, lockLink *to) {
    serverAssert(from->txid <= to->txid);
    lockLinksPush(&from->links,to);
    lockLinkTargetLinked(&to->target);
}

void lockLinkMigrate(lockLink *left, lockLink *to) {
    for (int i = 0; i < left->links.count; i++) {
        lockLink *from = left->links.links[i];
        lockLinkLink(from,to);
    }
}

/* links has following property:
 *  target txid always increase (but not monitonic).
 *  no duplicate link (from and to are identical).  */
static void lockLinkSignal(lockLink *link, int type, linkProceed cb,
        void *pd) {
    while (link->links.signaled < link->links.count) {
        lockLink *to = link->links.links[link->links.signaled];

        serverAssert(link->txid <= to->txid);
        if (type == LINK_SIGNAL_PROCEEDED && link->txid < to->txid) {
            /* signal is stoped if txid is greater, so that proceed won't
             * trigger callback of other tx. */
            break;
        }

        lockLinkTargetSignaled(&to->target);
        if (lockLinkTargetReady(&to->target)) cb(to,pd);
        link->links.signaled++;
    }
}

void lockLinkProceed(lockLink *link, linkProceed cb, void *pd) {
    lockLinkSignal(link,LINK_SIGNAL_PROCEEDED,cb,pd);
}

void lockLinkUnlock(lockLink *link, linkProceed cb, void *pd) {
    lockLinkSignal(link,LINK_SIGNAL_UNLOCK,cb,pd);
}

dictType keyLevelLockDictType = {
    dictSdsHash,                    /* hash function */
    NULL,                           /* key dup */
    NULL,                           /* val dup */
    dictSdsKeyCompare,              /* key compare */
    dictSdsDestructor,              /* key destructor */
    NULL,                           /* val destructor */
    NULL                            /* allow to expand */
};

locks *locksCreate(int level, redisDb *db, robj *key, locks *parent) {
    locks *locks;

    locks = lock_malloc(sizeof(struct locks));
    locks->lock_list = listCreate();
    locks->level = level;
    locks->parent = parent;

    switch (level) {
    case REQUEST_LEVEL_SVR:
        serverAssert(parent == NULL);
        locks->svr.dbnum = server.dbnum;
        locks->svr.dbs = lock_malloc(server.dbnum*sizeof(struct locks));
        break;
    case REQUEST_LEVEL_DB:
        serverAssert(parent->level == REQUEST_LEVEL_SVR);
        serverAssert(db);
        locks->db.db = db;
        locks->db.keys = dictCreate(&keyLevelLockDictType, NULL);
        break;
    case REQUEST_LEVEL_KEY:
        serverAssert(parent->level == REQUEST_LEVEL_DB);
        serverAssert(db && key);
        incrRefCount(key);
        locks->key.key = key;
        dictAdd(parent->db.keys,sdsdup(key->ptr),locks);
        break;
    default:
        break;
    }

    return locks;
}

static void locksRelease(locks *locks) {
    if (!locks) return;

    serverAssert(listLength(locks->lock_list) == 0);
    listRelease(locks->lock_list);
    locks->lock_list = NULL;

    switch (locks->level) {
    case REQUEST_LEVEL_SVR:
        lock_free(locks->svr.dbs);
        break;
    case REQUEST_LEVEL_DB:
        dictRelease(locks->db.keys);
        break;
    case REQUEST_LEVEL_KEY:
        serverAssert(locks->parent->level == REQUEST_LEVEL_DB);
        dictDelete(locks->parent->db.keys,locks->key.key->ptr);
        decrRefCount(locks->key.key);
        break;
    default:
        break;
    }

    lock_free(locks);
}

const char *lockDump(lock *lock);
sds locksDump(locks *locks) {
    listIter li;
    listNode *ln;
    sds result = sdsempty();
    char *key;
    redisDb *db;

    switch (locks->level) {
    case REQUEST_LEVEL_SVR:
        db = NULL;
        key = "<svr>";
        break;
    case REQUEST_LEVEL_DB:
        db = locks->db.db;
        key = "<db>";
        break;
    case REQUEST_LEVEL_KEY:
        db = locks->parent->db.db;
        key = locks->key.key->ptr;
        break;
    default:
        db = NULL;
        key = "?";
        break;
    }
    result = sdscatprintf(result,"(level=%s,len=%ld,db=%d,key=%s):",
            requestLevelName(locks->level),
            listLength(locks->lock_list),
            db ? db->id : -1, key);

    result = sdscat(result, "[");
    listRewind(locks->lock_list,&li);
    while ((ln = listNext(&li))) {
        lock *lock = listNodeValue(ln);
        if (ln != listFirst(locks->lock_list))
            result = sdscat(result,",");
        result = sdscat(result,lockDump(lock));
    }
    result = sdscat(result, "]");
    return result;
}

static inline lock *locksLastLock(locks *locks) {
    listNode *ln = listLast(locks->lock_list);
    return ln ? listNodeValue(ln) : NULL;
}

static inline void locksLinkLock(locks *locks, lock* lock) {
    struct lock *last;
    if ((last = locksLastLock(locks))) {
        lockLinkLink(&last->link,&lock->link);
    }
}

static void dbLocksChildrenLinkLock(locks *locks, lock* lock) {
    dictEntry *de;
    dictIterator *di = dictGetIterator(locks->db.keys);
    serverAssert(locks->level == REQUEST_LEVEL_DB);
    while ((de = dictNext(di)) != NULL) {
        struct locks *keylocks = dictGetVal(de);
        locksLinkLock(keylocks,lock);
    }
    dictReleaseIterator(di);
}

static void svrLocksChildrenLinkLock(locks *locks, lock* lock) {
    serverAssert(locks->level == REQUEST_LEVEL_SVR);
    for (int i = 0; i < server.dbnum; i++) {
        struct locks *dblocks = locks->svr.dbs[i];
        locksLinkLock(dblocks,lock);
        dbLocksChildrenLinkLock(dblocks,lock);
    }
}

/* link all children of locks(not inlcuding locks) to lock */
void locksChildrenLinksLock(locks *locks, lock* lock) {
    switch (locks->level) {
    case REQUEST_LEVEL_SVR:
        svrLocksChildrenLinkLock(locks,lock);
        break;
    case REQUEST_LEVEL_DB:
        dbLocksChildrenLinkLock(locks,lock);
        break;
    case REQUEST_LEVEL_KEY:
        break;
    default:
        serverPanic("unexpected locks level");
        break;
    }
}

static inline int locksWouldBlock(locks *locks, int64_t txid) {
    lock *last;
    if (locks == NULL) return 0;
    last = locksLastLock(locks);
    if (last == NULL) return 0;
    if (!lockLinkTargetReady(&last->link.target)) return 1;
    serverAssert(txid >= last->link.txid);
    return txid != last->link.txid;
}

lock *lockNew(int64_t txid, redisDb *db, robj *key, client *c,
        lockProceedCallback proceed, void *pd, freefunc pdfree,
        void *msgs) {
    lock *lock = lock_malloc(sizeof(struct lock));

    lockLinkInit(&lock->link,txid);

    lock->locks = NULL;
    lock->locks_ln = NULL;
    lock->db = db;
    if (key) incrRefCount(lock->key);
    lock->c = c;
    lock->proceed = proceed;
    lock->pd = pd;
    lock->pdfree = pdfree;
    lock->lock_timer = 0;
    lock->conflict = 0;

    UNUSED(msgs);
#ifdef SWAP_DEBUG
    lock->msgs = msgs;
#endif

    return lock;
}

void lockFree(lock *lock) {
    serverAssert(lockLinkTargetReady(&lock->link.target));
    serverAssert(lock->link.links.signaled == lock->link.links.count);
    serverAssert(lock->locks_ln == NULL);
    serverAssert(lock->locks == NULL);

    lockLinkDeinit(&lock->link);
    if (lock->key) {
        decrRefCount(lock->key);
        lock->key = NULL;
    }
    if (lock->pdfree) {
        lock->pdfree(lock->pd);
    }
    lock->pd = NULL;
    lock->pdfree = NULL;

    lock_free(lock);
}

const char *lockDump(lock *lock) {
    static char repr[256];
    char *ptr = repr, *end = repr + sizeof(repr) - 1;
    
    ptr += snprintf(ptr,end-ptr,
            "txid=%ld,target=(signaled=%d,linked=%d),links=[",
            lock->link.txid,lock->link.target.signaled,
            lock->link.target.linked);

    for (int i = 0; i < lock->link.links.count && ptr < end; i++) {
        struct lockLink *target_link = lock->link.links.links[i];
        struct lock *target = LINK_TO_LOCK(target_link);
        ptr += snprintf(ptr,end-ptr,"(txid=%ld,db=%d,key=%s,signaled=%s),",
                target_link->txid,
                target->db ? target->db->id : -1,
                target->key ? (char*)target->key->ptr : "<nil>",
                i < lock->link.links.signaled ? "true" : "false");
    }
    if (ptr < end) snprintf(ptr, end-ptr, "]");

    return repr;
}

static void lockStatUpdateLocked(lock *lock) {
    int level = lock->locks->level;
    lockStat *stat = server.swap_lock->stat;
    lockInstantaneouStat *inst_stat = stat->instant+level;
    lockCumulativeStat *cumu_stat = &stat->cumulative;

    cumu_stat->request_count++;
    inst_stat->request_count++;
    if (lock->conflict) {
        cumu_stat->conflict_count++;
        inst_stat->conflict_count++;
    }
}

static void lockStatUpdateUnlocked(lock *lock) {
    lockCumulativeStat *cumu_stat = &server.swap_lock->stat->cumulative;
    cumu_stat->request_count--;
    if (lock->conflict) cumu_stat->conflict_count--;
}

static void lockProceed(lock *lock) {
    serverAssert(lockLinkTargetReady(&lock->link.target));
    lock->proceed(lock,lock->db,lock->key,lock->c,lock->pd);
}

void lockProceedByLink(lockLink *link, void *pd) {
    lock *lock = LINK_TO_LOCK(link);
    UNUSED(pd);
    lockProceed(lock);
}

void lockProceeded(void *lock_) {
    lock *lock = lock_;
    lockLinkProceed(&lock->link,lockProceedByLink,NULL);
}

static inline void lockAttachToLocks(lock *lock, locks* locks) {
    struct lock *last = locksLastLock(locks);
    if (last == NULL) {
        locksChildrenLinksLock(locks,lock);
    } else {
        lockLinkMigrate(&last->link,&lock->link);
    }
    listAddNodeTail(locks->lock_list,lock);
    lock->locks = locks;
    lock->locks_ln = listLast(locks->lock_list);
}

static inline void lockDetachFromLocks(lock *lock) {
    locks *locks = lock->locks;
    lock->locks = NULL;
    listDelNode(locks->lock_list,lock->locks_ln);
    lock->locks_ln = NULL;
    if (locks->level == REQUEST_LEVEL_KEY &&
            listLength(locks->lock_list) == 0) {
        locksRelease(locks);
    }
}

void lockUnlock(void *lock_) {
    lock *lock = lock_;
    lockLinkUnlock(&lock->link,lockProceedByLink,NULL);
    lockStatUpdateUnlocked(lock);
    lockDetachFromLocks(lock);
    lockFree(lock);
}

static inline void lockProceedIfReady(lock *lock) {
    if (lockLinkTargetReady(&lock->link.target)) {
        lockProceed(lock);
    } else {
        lock->conflict = 1;
    }
}

void lockLock(int64_t txid, redisDb *db, robj *key, lockProceedCallback cb,
        client *c, void *pd, freefunc pdfree, void *msgs) {
    lock *lock = lockNew(txid,db,key,c,cb,pd,pdfree,msgs);
    locks *svrlocks = server.swap_lock->svrlocks, *dblocks, *keylocks, *locks;

    locksLinkLock(svrlocks,lock);
    if (db == NULL) {
        locks = svrlocks;
        goto end;
    }

    dblocks = svrlocks->svr.dbs[db->id];
    locksLinkLock(dblocks,lock);
    if (key == NULL) {
        locks = dblocks;
        goto end;
    }

    keylocks = dictFetchValue(dblocks->db.keys,key->ptr);
    if (keylocks == NULL) {
        keylocks = locksCreate(REQUEST_LEVEL_KEY,db,key,dblocks);
    } else {
        serverAssert(locksLastLock(keylocks)!= NULL);;
    }
    locksLinkLock(keylocks,lock);
    locks = keylocks;

end:
    lockAttachToLocks(lock,locks);

#ifdef SWAP_DEBUG
    sds dump = locksDump(locks);
    DEBUG_MSGS_APPEND(msgs,"lock","locks = %s, blocked=%d",dump,blocked);
    sdsfree(dump);
#endif

    lockProceedIfReady(lock);
    lockStatUpdateLocked(lock);
}

int lockWouldBlock(int64_t txid, redisDb *db, robj *key) {
    locks *locks = server.swap_lock->svrlocks;

    if (locksWouldBlock(locks,txid)) return 1;
    if (db == NULL) return 0;

    locks = locks->svr.dbs[db->id];
    if (locksWouldBlock(locks,txid)) return 1;
    if (key == NULL) return 0;

    locks = dictFetchValue(locks->db.keys,key->ptr);
    return locksWouldBlock(locks,txid);
}

static lockInstantaneouStat *lockStatCreateInstantaneou() {
    int i, metric_offset;
    lockInstantaneouStat *inst_stats = lock_malloc(REQUEST_LEVEL_TYPES*sizeof(lockInstantaneouStat));
    for (i = 0; i < REQUEST_LEVEL_TYPES; i++) {
        metric_offset = SWAP_LOCK_STATS_METRIC_OFFSET + i * SWAP_LOCK_METRIC_SIZE;
        inst_stats[i].name = requestLevelName(i);
        inst_stats[i].request_count = 0;
        inst_stats[i].conflict_count = 0;
        inst_stats[i].stats_metric_idx_request = metric_offset+SWAP_LOCK_METRIC_REQUEST;
        inst_stats[i].stats_metric_idx_conflict = metric_offset+SWAP_LOCK_METRIC_CONFLICT;
    }
    return inst_stats;
}

static void lockStatFreeInstantaneou(lockInstantaneouStat *stat) {
    lock_free(stat);
}

static void lockStatInitCumulative(lockCumulativeStat *cumu_stat) {
    cumu_stat->request_count = 0;
    cumu_stat->conflict_count = 0;
}

void lockStatInit(lockStat *stat) {
    lockStatInitCumulative(&stat->cumulative);
    stat->instant = lockStatCreateInstantaneou();
}

void lockStatDeinit(lockStat *stat) {
    lockStatFreeInstantaneou(stat->instant);
}

void trackSwapLockInstantaneousMetrics() {
    lockInstantaneouStat *inst_stats = server.swap_lock->stat->instant;
    for (int i = 0; i < REQUEST_LEVEL_TYPES; i++) {
        long long request, conflict;
        lockInstantaneouStat *inst_stat = inst_stats + i;
        atomicGet(inst_stat->request_count,request);
        trackInstantaneousMetric(inst_stat->stats_metric_idx_request,request);
        atomicGet(inst_stat->conflict_count,conflict);
        trackInstantaneousMetric(inst_stat->stats_metric_idx_conflict,conflict);
    }
}

void resetSwapLockInstantaneousMetrics() {
    for (int i = 0; i < REQUEST_LEVEL_TYPES; i++) {
        lockInstantaneouStat *inst_stat = server.swap_lock->stat->instant+i;
        inst_stat->request_count = 0;
        inst_stat->conflict_count = 0;
    }
}

sds genSwapLockInfoString(sds info) {
    int j;

    lockCumulativeStat *cumu_stat = &server.swap_lock->stat->cumulative;
    info = sdscatprintf(info,
            "swap_lock_used_memory:%lu\r\n"
            "swap_lock_request:%ld\r\n"
            "swap_lock_conflict:%ld\r\n",
            lock_memory_used,
            cumu_stat->request_count,
            cumu_stat->conflict_count);

    for (j = 0; j < REQUEST_LEVEL_TYPES; j++) {
        long long request, conflict, rps, cps;
        lockInstantaneouStat *lock_stat = server.swap_lock->stat->instant+j;
        atomicGet(lock_stat->request_count,request);
        atomicGet(lock_stat->conflict_count,conflict);
        rps = getInstantaneousMetric(lock_stat->stats_metric_idx_request);
        cps = getInstantaneousMetric(lock_stat->stats_metric_idx_conflict);
        info = sdscatprintf(info,
                "swap_lock_%s:request=%lld,conflict=%lld,request_ps=%lld,conflict_ps=%lld\r\n",
                lock_stat->name,request,conflict,rps,cps);
    }
    return info;
}

void swapLockCreate() {
    int i;
    locks *svrlocks = locksCreate(REQUEST_LEVEL_SVR,NULL,NULL,NULL);
    for (i = 0; i < server.dbnum; i++) {
        redisDb *db = server.db + i;
        svrlocks->svr.dbs[i] = locksCreate(REQUEST_LEVEL_DB,db,NULL,svrlocks);
    }
    server.swap_lock->svrlocks = svrlocks;

    lockStat *stat = lock_malloc(sizeof(lockStat));
    lockStatInit(stat);
    server.swap_lock->stat = stat;
}

void swapLockDestroy() {
    int i;
    locks *svrlocks = server.swap_lock->svrlocks;
    for (i = 0; i < server.dbnum; i++) {
        locksRelease(svrlocks->svr.dbs[i]);
    }
    locksRelease(svrlocks);
    lock_free(svrlocks);

    lock_free(server.swap_lock->stat);
}


#ifdef REDIS_TEST

#endif
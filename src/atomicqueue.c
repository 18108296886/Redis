/* Single-producer singe-consumer (SPSC) lock-free queue for passing data
 * between two threads, based on a ring buffer and atomic variables. */

#include <stddef.h>
#include <string.h>
#include "zmalloc.h"
#include "atomicqueue.h"

#ifndef CACHE_LINE_SIZE
#if defined(__aarch64__) && defined(__APPLE__)
#define CACHE_LINE_SIZE 128
#else
#define CACHE_LINE_SIZE 64
#endif
#endif

struct atomicqueue {
    /* Start of used space, owned by consumer. */
    redisAtomic unsigned int head __attribute__((aligned(CACHE_LINE_SIZE)));
    /* Start of free space, owned by producer. */
    redisAtomic unsigned int tail __attribute__((aligned(CACHE_LINE_SIZE)));
    /* Bitmask for indices. */
    unsigned int mask __attribute__((aligned(CACHE_LINE_SIZE)));
    unsigned int elemsize; /* Size of each element in bytes. */
    char data[] __attribute__((aligned(CACHE_LINE_SIZE)));
};

/* Allocates and initializes a queue. */
atomicqueue *atomicqueueCreate(unsigned capacity, unsigned elemsize) {
    unsigned mask = 1;
    while (mask < capacity)
        mask = (mask << 1) | 1;
    atomicqueue *queue = zmalloc(sizeof(struct atomicqueue) +
                                 ((size_t)mask + 1) * elemsize);
    atomicSet(queue->head, 0);
    atomicSet(queue->tail, 0);
    queue->mask = mask;
    queue->elemsize = elemsize;
    return queue;
}

/* Adds to the end of the queue. Returns 1 on success, 0 if full. */
int atomicqueueTryPush(atomicqueue *queue, void *value) {
    unsigned int head, tail;
    tail = queue->tail;
    atomicGetWithSync(queue->head, head); /* acquire consumer's writes */
    if (((tail + 1) & queue->mask) == head)
        return 0; /* full */
    memcpy(&queue->data[tail * queue->elemsize], value, queue->elemsize);
    /* Release the writes to the consumer */
    atomicSetWithSync(queue->tail, (tail + 1) & queue->mask);
    return 1;
}

/* Pops the element first in the queue. Returns 1 on success, 0 if empty. */
int atomicqueueTryPop(atomicqueue *queue, void *value) {
    unsigned int head, tail;
    head = queue->head;
    atomicGetWithSync(queue->tail, tail); /* acquire producer's writes */
    if (head == tail)
        return 0; /* empty */
    memcpy(value, &queue->data[head * queue->elemsize], queue->elemsize);
    /* Release the writes to the producer */
    atomicSetWithSync(queue->head, (head + 1) & queue->mask);
    return 1;
}

#ifdef REDIS_TEST

#include <sys/time.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#define UNUSED(x) (void)(x)
#define TEST(name) printf("test — %s\n", name);

static long long usec(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (((long long)tv.tv_sec)*1000000)+tv.tv_usec;
}

typedef struct {
    atomicqueue *queue;
    long long iterations;
} sharedData;

void *writerThreadMain(void *arg) {
    sharedData *data = arg;
    atomicqueue *queue = data->queue;
    long long spin = 0, full = 0;
    for (long long i = data->iterations; i >= 0; i--) {
        if (!atomicqueueTryPush(queue, (void *)&i)) {
            full++;
            do {
                spin++;
                usleep(0);
            } while (!atomicqueueTryPush(queue, (void *)&i));
        }
    }
    printf("Writer thread: full=%-8lld spin=%-7lld\n", full, spin);
    return NULL;
}

int atomicqueueTest(int argc, char *argv[], int flags) {
    UNUSED(argc);
    UNUSED(argv);
    UNUSED(flags);

    pthread_t writer;
    long long iterations = 10000000;
    unsigned  capacity   = 2000;
    atomicqueue *queue = atomicqueueCreate(capacity, sizeof(long long));
    sharedData data = {queue, iterations};

    if (pthread_create(&writer, NULL, writerThreadMain, &data)) {
        fprintf(stderr, "Failed to create thread\n");
        exit(1);
    }
    usleep(100000);
    long long start = usec();

    long long spin = 0, empty = 0, i = 0, n = iterations;
    do {
        if (!atomicqueueTryPop(queue, (void *)&i)) {
            empty++;
            do {
                spin++;
                usleep(0);
            } while (!atomicqueueTryPop(queue, (void *)&i));
        }
        if (i != n--) {
            printf("Reader got unexpected value %lld expecting %lld\n", i, n);
            exit(1);
        }
    } while (i > 0);
    long long end = usec();
    pthread_join(writer, NULL);
    printf("Reader thread: empty=%-7lld spin=%-7lld\n", empty, spin);
    printf("Total: %lld elements in %lldµs (%lfµs per element)\n",
           iterations, (end - start), (end - start)/(double)iterations);
    return 0;
}

#endif

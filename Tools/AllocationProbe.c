// Test-only allocator interposition for the offline synthetic renderer benchmark.
// Never linked into the application or used while observing keyboard input.
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

static _Thread_local bool checking;
static _Thread_local uint64_t activity;
void whoa_probe_begin(void) { activity = 0; checking = true; }
uint64_t whoa_probe_end(void) { checking = false; return activity; }
static void *probe_malloc(size_t n) { if (checking) ++activity; return malloc(n); }
static void *probe_calloc(size_t n, size_t s) { if (checking) ++activity; return calloc(n, s); }
static void *probe_realloc(void *p, size_t n) { if (checking) ++activity; return realloc(p, n); }
static void probe_free(void *p) { if (checking && p) ++activity; free(p); }
static int probe_posix_memalign(void **p, size_t a, size_t n) { if (checking) ++activity; return posix_memalign(p, a, n); }
#define INTERPOSE(replacement, original) \
  __attribute__((used)) static struct { const void *new_fn; const void *old_fn; } \
  interpose_##original __attribute__((section("__DATA,__interpose"))) = \
  { (const void *)&replacement, (const void *)&original };
INTERPOSE(probe_malloc, malloc)
INTERPOSE(probe_calloc, calloc)
INTERPOSE(probe_realloc, realloc)
INTERPOSE(probe_free, free)
INTERPOSE(probe_posix_memalign, posix_memalign)

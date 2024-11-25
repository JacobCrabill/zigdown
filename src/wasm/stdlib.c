// This file implements a very simple allocator for external scanners running
// in WASM. Allocation is just bumping a static pointer and growing the heap
// as needed, and freeing is mostly a noop. But in the special case of freeing
// the last-allocated pointer, we'll reuse that pointer again.

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

extern void tree_sitter_debug_message(const char *, size_t);

#define PAGESIZE 0x10000
#define MAX_HEAP_SIZE (4 * 1024 * 1024)

// // TODO: May need a proper implementation! This is just a placeholder for now.
// bool iswspace(int wc) {
//   const int wspace_chars[] = { ' ', '\t', '\n', '\r', 0x0B, 0x0C };
//   for (size_t i = 0; i < sizeof(wspace_chars); i++) {
//     if (wc == wspace_chars[i])
//       return true;
//   }
//   return false;
// }
//
// // TODO: May need a proper implementation! This is just a placeholder for now.
// bool iswalpha(int wc) {
//   const bool is_cap = (wc >= (int)'A' && wc <= (int)'Z');
//   const bool is_lower = (wc >= (int)'a' && wc <= (int)'z');
//   return is_cap || is_lower;
// }
//
// bool iswalnum(int wc) {
//   const bool is_cap = (wc >= (int)'A' && wc <= (int)'Z');
//   const bool is_lower = (wc >= (int)'a' && wc <= (int)'z');
//   const bool is_number = (wc >= (int)'0' && wc <= (int)'9');
//   return is_cap || is_lower || is_number;
// }
//
// int strcmp(const char *s1, const char *s2) {
//     const unsigned char *p1 = ( const unsigned char * )s1;
//     const unsigned char *p2 = ( const unsigned char * )s2;
//
//     while ( *p1 && *p1 == *p2 ) {
//       ++p1; ++p2;
//     }
//
//     return *p1 - *p2;
// }
//
//
// int strncmp(const char *s1, const char *s2, size_t n) {
//     const unsigned char *p1 = ( const unsigned char * )s1;
//     const unsigned char *p2 = ( const unsigned char * )s2;
//
//     size_t i = 0;
//     while ( *p1 && i < n && *p1 == *p2 ) {
//       ++p1; ++p2; ++i;
//     }
//
//     return *p1 - *p2;
// }

int fprintf(FILE *stream, const char *format, ...) {
  // Is this even relevant for WASM?  Probably not.
  return 0;
}

// void __assert_fail() {
//   // do nothing
// }

typedef struct {
  size_t size;
  char data[0];
} Region;

static Region *heap_end = NULL;
static Region *heap_start = NULL;
static Region *next = NULL;

// Get the region metadata for the given heap pointer.
static inline Region *region_for_ptr(void *ptr) {
  return ((Region *)ptr) - 1;
}

// Get the location of the next region after the given region,
// if the given region had the given size.
static inline Region *region_after(Region *self, size_t len) {
  char *address = self->data + len;
  char *aligned = (char *)((uint32_t)(address + 3) & ~0x3);
  return (Region *)aligned;
}

static void *get_heap_end() {
  return (void *)(__builtin_wasm_memory_size(0) * PAGESIZE);
}

static int grow_heap(size_t size) {
  size_t new_page_count = ((size - 1) / PAGESIZE) + 1;
  return __builtin_wasm_memory_grow(0, new_page_count) != MAX_HEAP_SIZE; // ??? SIZE_MAX; ???
}

// Clear out the heap, and move it to the given address.
void reset_heap(void *new_heap_start) {
  heap_start = new_heap_start;
  next = new_heap_start;
  heap_end = get_heap_end();
}

void *malloc(size_t size) {
  Region *region_end = region_after(next, size);

  if (region_end > heap_end) {
    if ((char *)region_end - (char *)heap_start > MAX_HEAP_SIZE) {
      return NULL;
    }
    if (!grow_heap(size)) return NULL;
    heap_end = get_heap_end();
  }

  void *result = &next->data;
  next->size = size;
  next = region_end;

  return result;
}

void free(void *ptr) {
  if (ptr == NULL) return;

  Region *region = region_for_ptr(ptr);
  Region *region_end = region_after(region, region->size);

  // When freeing the last allocated pointer, re-use that
  // pointer for the next allocation.
  if (region_end == next) {
    next = region;
  }
}

void *calloc(size_t count, size_t size) {
  void *result = malloc(count * size);
  memset(result, 0, count * size);
  return result;
}

void *realloc(void *ptr, size_t new_size) {
  if (ptr == NULL) {
    return malloc(new_size);
  }

  Region *region = region_for_ptr(ptr);
  Region *region_end = region_after(region, region->size);

  // When reallocating the last allocated region, return
  // the same pointer, and skip copying the data.
  if (region_end == next) {
    next = region;
    return malloc(new_size);
  }

  void *result = malloc(new_size);
  memcpy(result, &region->data, region->size);
  return result;
}

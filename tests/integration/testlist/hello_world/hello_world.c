#include "hello_world.h"
#include "../../sw/include/nb_cores.h"
#include <stdint.h>
#include <stddef.h>
#include "uart.h"

// #include <stdatomic.h>
// volatile atomic_flag print_lock __attribute__((section(".cache_share_region"))) = ATOMIC_FLAG_INIT ; 
// #define printf(...) do { \
//   char text[1024]; \
//   sprintf(text, __VA_ARGS__); \
//   while (atomic_flag_test_and_set_explicit(&print_lock, memory_order_acquire)) {  } \
//   print_uart(text); \
//   atomic_flag_clear_explicit(&print_lock, memory_order_release); \
// } while (0)



#define printf(...) do { \
  char text[1024]; \
  sprintf(text, __VA_ARGS__); \
  print_uart(text); \
} while (0)

extern void exit(int);

// cachelines are 128bit long
#define uint128_t __uint128_t

volatile uint128_t data[NB_CORES] __attribute__((section(".nocache_noshare_region")));

int hello_world(int cid, int nc)
{
  printf("Hello world: Core %d!!\r\n",cid);
  return 0;
}

// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include "hello_world.h"
#include "uart.h"
#include <stdint.h>

// synchronization variable: non-cached and shared
volatile uint64_t count __attribute__((section(".nocache_share_region")));
extern void exit(int);

void thread_entry(int cid, int nc)
{
  // Initialize UART on FPGA (50 MHz system clock, 115200 baud).
  // No-op in simulation (mock UART ignores register writes).
  if (cid == 0)
    init_uart(50000000, 115200);

  // core 0 initializes the synchronization variable
  if (cid == 0)
    count = 0;
  else
    while(count != cid);

  // actual test
  hello_world(cid, nc);
  count++;

  // cores wait here
  while(cid)
    { asm volatile ("wfi"); }

  // core 0 continues after all cores have finished
  if (cid == 0) {
    while (count != nc)
      { asm volatile ("nop"); }
  }
}

int main()
{
  return 0;
}

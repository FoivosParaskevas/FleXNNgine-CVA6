// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include <stdarg.h>
#include <stdio.h>
#include <limits.h>
#include <sys/signal.h>

#include <string.h>

#include <stddef.h>
#include <stdint.h>

#include "list.h"


#ifdef __riscv
#include "encoding.h"
#endif

#define static_assert(cond) switch(0) { case 0: case !!(long)(cond): ; }

#define SYS_write 64

// Direct UART I/O for FPGA hardware (bypasses tohost/fromhost simulation mechanism).
// Enable with -DFPGA_IO=1 in the build flags.
#ifdef FPGA_IO
#define UART_BASE_ADDR 0x10000000UL
static inline void _fpga_uart_init(void) {
    volatile uint32_t* lcr = (volatile uint32_t*)(UART_BASE_ADDR + 12);
    volatile uint32_t* dll = (volatile uint32_t*)(UART_BASE_ADDR + 0);
    volatile uint32_t* dlm = (volatile uint32_t*)(UART_BASE_ADDR + 4);
    volatile uint32_t* fcr = (volatile uint32_t*)(UART_BASE_ADDR + 8);
    // freq=50MHz, baud=115200: divisor = 50000000 / (115200 * 16) = 27
    *lcr = 0x80; // set DLAB to access divisor latches
    *dll = 27;
    *dlm = 0;
    *lcr = 0x03; // 8-bit, no parity, 1 stop bit; clear DLAB
    *fcr = 0x01; // enable FIFO
}
static inline void _fpga_uart_write(const char* buf, size_t len) {
    volatile uint32_t* lsr = (volatile uint32_t*)(UART_BASE_ADDR + 20);
    volatile uint32_t* thr = (volatile uint32_t*)(UART_BASE_ADDR + 0);
    for (size_t i = 0; i < len; i++) {
        while (!(*lsr & 0x20)); // wait for THR empty (THRE bit)
        *thr = (uint8_t)buf[i];
    }
}
// Override newlib's _write so that C++ cout/cerr also reaches the UART.
// Without this, cout goes through newlib's _write stub which returns -1 or
// triggers an ecall, both of which prevent any C++ output on bare metal.
int _write(int fd, const char* buf, int nbytes) {
    (void)fd;
    _fpga_uart_write(buf, nbytes);
    return nbytes;
}
#endif

#undef strcmp

extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

static uintptr_t syscall(uintptr_t which, uint64_t arg0, uint64_t arg1, uint64_t arg2)
{
  volatile uint64_t magic_mem[8] __attribute__((aligned(64)));
  magic_mem[0] = which;
  magic_mem[1] = arg0;
  magic_mem[2] = arg1;
  magic_mem[3] = arg2;
  __sync_synchronize();

  tohost = (uintptr_t)magic_mem;
  while (fromhost == 0)
    ;
  fromhost = 0;

  __sync_synchronize();
  return magic_mem[0];
}

void __attribute__((noreturn)) tohost_exit(uintptr_t code)
{
  tohost = (code << 1) | 1;
  while (1);
}

uintptr_t __attribute__((weak)) handle_trap(uintptr_t cause, uintptr_t epc, uintptr_t regs[32])
{
  tohost_exit(1337);
}

void exit(int code)
{
  tohost_exit(code);
}

void abort()
{
  exit(128 + SIGABRT);
}

void __attribute__((weak)) thread_entry(int cid, int nc)
{
  // multi-threaded programs override this function.
  // for the case of single-threaded programs, only let core 0 proceed.
  while (cid != 0) { asm volatile ("wfi"); } // -> TODO: Naqash  
}

int __attribute__((weak)) main(int argc, char** argv)
{
  // single-threaded programs override this function.

  return -1;
}

static void init_tls()
{
  register void* thread_pointer asm("tp");
  extern char _tls_data;
  extern char _tdata_begin, _tdata_end, _tbss_end;
  size_t tdata_size = &_tdata_end - &_tdata_begin;
  memcpy(thread_pointer, &_tls_data, tdata_size);
  size_t tbss_size = &_tbss_end - &_tdata_end;
  memset(thread_pointer + tdata_size, 0, tbss_size);
}

void _init(int cid, int nc)
{
#ifdef FPGA_IO
  if (cid == 0)
    _fpga_uart_init();
#endif
  init_tls();
  thread_entry(cid, nc);

  // only single-threaded programs should ever get here.
  int ret = main(0, 0);

  exit(ret);
}

void* memcpy(void* dest, const void* src, size_t len)
{
  if (len) {
  if ((((uintptr_t)dest | (uintptr_t)src | len) & (sizeof(uintptr_t)-1)) == 0) {
    const uintptr_t* s = src;
    uintptr_t *d = dest;
    while (d < (uintptr_t*)(dest + len))
      *d++ = *s++;
  } else {
    const char* s = src;
    char *d = dest;
    while (d < (char*)(dest + len))
      *d++ = *s++;
  }
  }
  return dest;
}

void* memset(void* dest, int byte, size_t len)
{
  if (len) {
  if ((((uintptr_t)dest | len) & (sizeof(uintptr_t)-1)) == 0) {
    uintptr_t word = byte & 0xFF;
    word |= word << 8;
    word |= word << 16;
    word |= word << 16 << 16;

    uintptr_t *d = dest;
    while (d < (uintptr_t*)(dest + len))
      *d++ = word;
  } else {
    char *d = dest;
    while (d < (char*)(dest + len))
      *d++ = byte;
  }
  }
  return dest;
}

size_t strlen(const char *s)
{
  const char *p = s;
  while (*p)
    p++;
  return p - s;
}

size_t strnlen(const char *s, size_t n)
{
  const char *p = s;
  while (n-- && *p)
    p++;
  return p - s;
}

int strcmp(const char* s1, const char* s2)
{
  unsigned char c1, c2;

  do {
    c1 = *s1++;
    c2 = *s2++;
  } while (c1 != 0 && c1 == c2);

  return c1 - c2;
}

char* strcpy(char* dest, const char* src)
{
  char* d = dest;
  while ((*d++ = *src++))
    ;
  return dest;
}

long atol(const char* str)
{
  long res = 0;
  int sign = 0;

  while (*str == ' ')
    str++;

  if (*str == '-' || *str == '+') {
    sign = *str == '-';
    str++;
  }

  while (*str) {
    res *= 10;
    res += *str++ - '0';
  }

  return sign ? -res : res;
}

#define ALIGN_SIZE(sz, align) (((sz) + ((align)-1)) & ~((align)-1))
typedef struct alloc_node
{
	struct list_head node;
	size_t size;
	char* block;
} alloc_node_t;

/* allocation metadata size */
#define ALLOC_HEADER_SZ __builtin_offsetof(alloc_node_t, block)

/* minimum allocation size of 32 bytes */
#define MIN_ALLOC_SZ ALLOC_HEADER_SZ + 32

/* free list */
static LIST_HEAD(free_list);

static void coalesce_free_list(void)
{
	alloc_node_t *b, *lb = NULL, *t;

	list_for_each_entry_safe(b, t, &free_list, node)
	{
		if (lb)
		{
			/* coalesce adjacent blocks */
			if ((((uintptr_t)&lb->block) + lb->size) == (uintptr_t)b)
			{
				lb->size += sizeof(*b) + b->size;
				list_del(&b->node);
				continue;
			}
		}
		lb = b;
	}
}

void* malloc(size_t size)
{
	void* ptr = NULL;
	alloc_node_t* blk = NULL;

	if (size > 0)
	{
		/* Align the pointer */
		size = ALIGN_SIZE(size, sizeof(void*));

		/* try to find a big enough block */
		list_for_each_entry(blk, &free_list, node)
		{
			if (blk->size >= size)
			{
				ptr = &blk->block;
				break;
			}
		}

		if (ptr)
		{
			/* split block if possible */
			if ((blk->size - size) >= MIN_ALLOC_SZ)
			{
				alloc_node_t* new_blk;
				new_blk = (alloc_node_t*)((uintptr_t)(&blk->block) + size);
				new_blk->size = blk->size - size - ALLOC_HEADER_SZ;
				blk->size = size;
				list_add(&new_blk->node, &blk->node);
			}

			list_del(&blk->node);
		}

	}

	return ptr;
}

void free(void* ptr)
{
	alloc_node_t *blk, *free_blk;

	if (ptr)
	{
		blk = container_of(ptr, alloc_node_t, block);

		/* add block to free list in ascending order by pointer */
		list_for_each_entry(free_blk, &free_list, node)
		{
			if (free_blk > blk)
			{
				list_add_tail(&blk->node, &free_blk->node);
				goto blockadded;
			}
		}
		list_add_tail(&blk->node, &free_list);

	blockadded:
		coalesce_free_list();
	}
}

void _malloc_addblock(void* addr, size_t size)
{
	alloc_node_t* blk;

	/* pointer align the block */
	blk = (alloc_node_t*)ALIGN_SIZE((uintptr_t)addr, sizeof(void*));

	/* calculate usable size */
	blk->size = (uintptr_t)addr + size - (uintptr_t)blk - ALLOC_HEADER_SZ;

	/* add the block to the free list */
	list_add(&blk->node, &free_list);
}




////////////////////////////////////////////
// from link "https://github.com/openhwgroup/cva6/blob/master/verif/tests/custom/common/syscalls.c @3d00079"
#define NUM_COUNTERS 2
static uintptr_t counters[NUM_COUNTERS];
static char* counter_names[NUM_COUNTERS];

void setStats(int enable)
{
  int i = 0;
#define READ_CTR(name) do { \
    while (i >= NUM_COUNTERS) ; \
    uintptr_t csr = read_csr(name); \
    if (!enable) { csr -= counters[i]; counter_names[i] = #name; } \
    counters[i++] = csr; \
  } while (0)

  READ_CTR(mcycle);
  READ_CTR(minstret);

#undef READ_CTR
}

uintptr_t getStats(int counterid)
{
  return counters[counterid];
}

void printstr(const char* s)
{
#if !NOPRINT
  syscall(SYS_write, 1, (uintptr_t)s, strlen(s));
#endif
}

int puts(const char *s)
{
  const char *p = s;

  while (*p)
    putchar(*p++);

  putchar('\n');
  return 0;
}

#undef putchar
int putchar(int ch)
{
#if !NOPRINT
#ifdef FPGA_IO
  // On FPGA hardware, write directly to the APB UART — no tohost/fromhost.
  static char buf[64] __attribute__((aligned(64)));
  static int buflen = 0;

  buf[buflen++] = ch;

  if (ch == '\n' || buflen == (int)sizeof(buf))
  {
    _fpga_uart_write(buf, buflen);
    buflen = 0;
  }
#else
  static __thread char buf[64] __attribute__((aligned(64)));
  static __thread int buflen = 0;

  buf[buflen++] = ch;

  if (ch == '\n' || buflen == (int)sizeof(buf))
  {
    syscall(SYS_write, 1, (uintptr_t)buf, buflen);
    buflen = 0;
  }
#endif
#endif

  return 0;
}

void printhex(uint64_t x)
{
  char str[17];
  int i;
  for (i = 0; i < 16; i++)
  {
    str[15-i] = (x & 0xF) + ((x & 0xF) < 10 ? '0' : 'a'-10);
    x >>= 4;
  }
  str[16] = 0;

  printstr(str);
}

static inline void printnum(void (*putch)(int, void**), void **putdat,
                    unsigned long long num, unsigned base, int width, int padc)
{
  unsigned digs[sizeof(num)*CHAR_BIT];
  int pos = 0;

  while (1)
  {
    digs[pos++] = num % base;
    if (num < base)
      break;
    num /= base;
  }

  while (width-- > pos)
    putch(padc, putdat);

  while (pos-- > 0)
    putch(digs[pos] + (digs[pos] >= 10 ? 'a' - 10 : '0'), putdat);
}

static unsigned long long getuint(va_list *ap, int lflag)
{
  if (lflag >= 2)
    return va_arg(*ap, unsigned long long);
  else if (lflag)
    return va_arg(*ap, unsigned long);
  else
    return va_arg(*ap, unsigned int);
}

static long long getint(va_list *ap, int lflag)
{
  if (lflag >= 2)
    return va_arg(*ap, long long);
  else if (lflag)
    return va_arg(*ap, long);
  else
    return va_arg(*ap, int);
}

static void vprintfmt(void (*putch)(int, void**), void **putdat, const char *fmt, va_list ap)
{
  register const char* p;
  const char* last_fmt;
  register int ch, err;
  unsigned long long num;
  int base, lflag, width, precision, altflag;
  char padc;

  while (1) {
    while ((ch = *(unsigned char *) fmt) != '%') {
      if (ch == '\0')
        return;
      fmt++;
      putch(ch, putdat);
    }
    fmt++;

    // Process a %-escape sequence
    last_fmt = fmt;
    padc = ' ';
    width = -1;
    precision = -1;
    lflag = 0;
    altflag = 0;
  reswitch:
    switch (ch = *(unsigned char *) fmt++) {

    // flag to pad on the right
    case '-':
      padc = '-';
      goto reswitch;
      
    // flag to pad with 0's instead of spaces
    case '0':
      padc = '0';
      goto reswitch;

    // width field
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
      for (precision = 0; ; ++fmt) {
        precision = precision * 10 + ch - '0';
        ch = *fmt;
        if (ch < '0' || ch > '9')
          break;
      }
      goto process_precision;

    case '*':
      precision = va_arg(ap, int);
      goto process_precision;

    case '.':
      if (width < 0)
        width = 0;
      goto reswitch;

    case '#':
      altflag = 1;
      goto reswitch;

    process_precision:
      if (width < 0)
        width = precision, precision = -1;
      goto reswitch;

    // long flag (doubled for long long)
    case 'l':
      lflag++;
      goto reswitch;

    // character
    case 'c':
      putch(va_arg(ap, int), putdat);
      break;

    // string
    case 's':
      if ((p = va_arg(ap, char *)) == NULL)
        p = "(null)";
      if (width > 0 && padc != '-')
        for (width -= strnlen(p, precision); width > 0; width--)
          putch(padc, putdat);
      for (; (ch = *p) != '\0' && (precision < 0 || --precision >= 0); width--) {
        putch(ch, putdat);
        p++;
      }
      for (; width > 0; width--)
        putch(' ', putdat);
      break;

    // (signed) decimal
    case 'd':
      num = getint(&ap, lflag);
      if ((long long) num < 0) {
        putch('-', putdat);
        num = -(long long) num;
      }
      base = 10;
      goto signed_number;

    // unsigned decimal
    case 'u':
      base = 10;
      goto unsigned_number;

    // (unsigned) octal
    case 'o':
      // should do something with padding so it's always 3 octits
      base = 8;
      goto unsigned_number;

    // pointer
    case 'p':
      static_assert(sizeof(long) == sizeof(void*));
      lflag = 1;
      putch('0', putdat);
      putch('x', putdat);
      /* fall through to 'x' */

    // (unsigned) hexadecimal
    case 'x':
      base = 16;
    unsigned_number:
      num = getuint(&ap, lflag);
    signed_number:
      printnum(putch, putdat, num, base, width, padc);
      break;

    // escaped '%' character
    case '%':
      putch(ch, putdat);
      break;
      
    // unrecognized escape sequence - just print it literally
    default:
      putch('%', putdat);
      fmt = last_fmt;
      break;
    }
  }
}

int printf(const char* fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);

  vprintfmt((void*)putchar, 0, fmt, ap);

  va_end(ap);
  return 0; // incorrect return value, but who cares, anyway?
}

void sprintf_putch(int ch, void** data)
{
  char** pstr = (char**)data;
  **pstr = ch;
  (*pstr)++;
}

int sprintf(char* str, const char* fmt, ...)
{
  va_list ap;
  char* str0 = str;
  va_start(ap, fmt);

  vprintfmt(sprintf_putch, (void**)&str, fmt, ap);
  *str = 0;

  va_end(ap);
  return str - str0;
}

// from newlib: https://sourceware.org/git/?p=newlib-cygwin.git;a=blob_plain;f=newlib/libc/stdlib/assert.c;h=46ac92b8c90a9196763d683f7aad0bd26330cc91;hb=HEAD
#ifndef HAVE_ASSERT_FUNC
/* func can be NULL, in which case no function information is given.  */
void
__assert_func (const char *file,
  int line,
  const char *func,
  const char *failedexpr)
{
  printf("assertion \"%s\" failed: file \"%s\", line %d%s%s\n",
    failedexpr, file, line,
    func ? ", function: " : "", func ? func : "");
  abort();
  /* NOTREACHED */
}
#endif /* HAVE_ASSERT_FUNC */

///////////////////////////////////////////////////////////////

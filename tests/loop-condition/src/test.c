#include <stdio.h>

#ifndef ANGELIX_OUTPUT
#define ANGELIX_OUTPUT(type, expr, id) expr
#endif

int main(int argc, char *argv[]) {
  int n;
  n = atoi(argv[1]);
  while (n > 1) {
    n--;
    printf("%d\n", ANGELIX_OUTPUT(int, n, "n"));
  }
  return 0;
}

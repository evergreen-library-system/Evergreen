#include <stdlib.h>
#include <check.h>
#include "testsuite.h"

extern void run_tests(SRunner *sr);

int main (int argc, char **argv)
{
  SRunner *sr = srunner_create(NULL);
  run_tests(sr);
  srunner_run_all(sr, CK_NORMAL);
  int failed = srunner_ntests_failed(sr);
  srunner_free(sr);
  return (failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}

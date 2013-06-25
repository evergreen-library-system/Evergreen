#include <check.h>
#include <ctype.h>
#include <limits.h>
#include "openils/oils_utils.h"
#include "openils/oils_idl.h"

//Set up the test fixture
void setup (void) {
}

//Clean up the test fixture
void teardown (void) {
}

//Tests

START_TEST (test_oilsUtilsIsDBTrue)
{
    ck_assert_msg( ! oilsUtilsIsDBTrue("0"),  "oilsUtilIsDBTrue() should be false when passed '0'");
    ck_assert_msg(   oilsUtilsIsDBTrue("1"),  "oilsUtilIsDBTrue() should be true when passed '1'");
    ck_assert_msg(   oilsUtilsIsDBTrue("-1"), "oilsUtilIsDBTrue() should be true when passed '-1'");
    ck_assert_msg(   oilsUtilsIsDBTrue("a"),  "oilsUtilIsDBTrue() should be true when passed 'a'");
    ck_assert_msg( ! oilsUtilsIsDBTrue("f"),  "oilsUtilIsDBTrue() should be false when passed 'f'");
}
END_TEST

//END Tests

Suite *util_suite (void) {
  //Create test suite, test case, initialize fixture
  Suite *s = suite_create("util");
  TCase *tc_core = tcase_create("Core");
  tcase_add_checked_fixture(tc_core, setup, teardown);

  //Add tests to test case
  tcase_add_test(tc_core, test_oilsUtilsIsDBTrue);

  //Add test case to test suite
  suite_add_tcase(s, tc_core);

  return s;
}

void run_tests (SRunner *sr) {
  srunner_add_suite (sr, util_suite());
}

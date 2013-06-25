#include <check.h>
#include <ctype.h>
#include <limits.h>
#include "openils/oils_utils.h"
#include "openils/oils_idl.h"

osrfHash * my_idl;

//Set up the test fixture
void setup (void) {
    my_idl = oilsInitIDL("../../../examples/fm_IDL.xml");
}

//Clean up the test fixture
void teardown (void) {
    free(my_idl);
}

//Tests

START_TEST (test_loading_idl)
{
    ck_assert(my_idl);
}
END_TEST

//END Tests

Suite *idl_suite (void) {
  //Create test suite, test case, initialize fixture
  Suite *s = suite_create("idl");
  TCase *tc_core = tcase_create("Core");
  tcase_add_checked_fixture(tc_core, setup, teardown);

  //Add tests to test case
  tcase_add_test(tc_core, test_loading_idl);

  //Add test case to test suite
  suite_add_tcase(s, tc_core);

  return s;
}

void run_tests (SRunner *sr) {
  srunner_add_suite (sr, idl_suite());
}

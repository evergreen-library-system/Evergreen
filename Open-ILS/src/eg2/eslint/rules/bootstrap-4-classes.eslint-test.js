import { RuleTester } from '@angular-eslint/test-utils';
import { rule, RULE_NAME } from './bootstrap-4-classes';
import {afterAll, describe, it} from 'vitest';
import TemplateParser from '@angular-eslint/template-parser';

RuleTester.afterAll = afterAll;
RuleTester.describe = describe;
RuleTester.it = it;
const ruleTester = new RuleTester({languageOptions:{parser: TemplateParser}});
const messageId = 'bootstrap4classes';

const valid = [
  '<div class="ms-auto pe-3 py-3">I am pushed to the right!</div>'
];

const invalid = [
  {
    code: '<div class="ml-auto pr-3 py-3">I am pushed to the right!</div>',
    errors: [
      {
        messageId
      },
    ],
    output: '<div class="ms-auto pe-3 py-3">I am pushed to the right!</div>'
  },
];
ruleTester.run(RULE_NAME, rule, {
  valid,
  invalid,
});

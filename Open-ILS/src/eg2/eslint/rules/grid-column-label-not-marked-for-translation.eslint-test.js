import { RuleTester } from '@angular-eslint/test-utils';
import { rule, RULE_NAME } from './grid-column-label-not-marked-for-translation';
import {afterAll, describe, it} from 'vitest';
import TemplateParser from '@angular-eslint/template-parser';

RuleTester.afterAll = afterAll;
RuleTester.describe = describe;
RuleTester.it = it;
const ruleTester = new RuleTester({languageOptions:{parser: TemplateParser}});
const messageId = 'gridColumnLabelNotMarkedForTranslation';

const valid = [
  '<eg-grid-column label="Call number" path="call_number" i18n-label></eg-grid-column>',
  '<eg-grid-column name="title" label="Title or name" i18n-label path="target_resource_type.name"></eg-grid-column>',
  // It's a bit odd to have i18n-label without label, but it is not a violation of this rule
  '<eg-grid-column i18n-label [hidden]="true" path="unrecovered" datatype="bool"></eg-grid-column>',
  '<eg-grid-column name="audit_time" [datePlusTime]="true"></eg-grid-column>'
];

const invalid = [
  {
    code: '<eg-grid-column label="ID" path="id" name="id"></eg-grid-column>',
    errors: [
      {
        messageId
      },
    ],
    output: '<eg-grid-column label="ID" i18n-label path="id" name="id"></eg-grid-column>'
  },
];
ruleTester.run(RULE_NAME, rule, {
  valid,
  invalid,
});

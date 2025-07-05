import { RuleTester } from '@angular-eslint/test-utils';
import { rule, RULE_NAME } from './bg-info-on-modal-header';
import {afterAll, describe, it} from 'vitest';
import TemplateParser from '@angular-eslint/template-parser';

RuleTester.afterAll = afterAll;
RuleTester.describe = describe;
RuleTester.it = it;
const ruleTester = new RuleTester({languageOptions:{parser: TemplateParser}});
const messageId = 'bgInfoOnModalHeader';

const valid = [
  `
  <ng-template #dialogContent>
  <div class="modal-header">
    <h4 class="modal-title">
      <span i18n>Manage Grid Filters</span>
    </h4>
    <button type="button" class="btn-close btn-close-white"
    i18n-aria-label aria-label="Close dialog" (click)="close()">
  </button>
</div>
  `,
  `
  <div class="bg-info">Hello!</div>
  `
];

const invalid = [
  {
    code: `
    <ng-template #dialogContent>
    <div class="modal-header bg-info">
      <h4 class="modal-title">
        <span i18n>Manage Grid Filters</span>
      </h4>
      <button type="button" class="btn-close btn-close-white"
      i18n-aria-label aria-label="Close dialog" (click)="close()">
    </button>
  </div>
    `,
    errors: [
      {
        messageId
      },
    ],
    output: `
    <ng-template #dialogContent>
    <div class="modal-header">
      <h4 class="modal-title">
        <span i18n>Manage Grid Filters</span>
      </h4>
      <button type="button" class="btn-close btn-close-white"
      i18n-aria-label aria-label="Close dialog" (click)="close()">
    </button>
  </div>
    `
  },
  {
    code: '<div class="bg-info modal-header"></div>',
    errors: [
      {
        messageId
      },
    ],
    output: '<div class="modal-header"></div>'
  },
  {
    code: '<div class="bg-info mt-2 modal-header"></div>',
    errors: [
      {
        messageId
      },
    ],
    output: '<div class="mt-2 modal-header"></div>'
  },
];
ruleTester.run(RULE_NAME, rule, {
  valid,
  invalid,
});  


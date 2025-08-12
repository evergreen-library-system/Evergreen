import { getTemplateParserServices } from '@angular-eslint/utils';
import { createEslintRule } from '../utils.js';
import "core-js/full/set/index.js";

export const RULE_NAME = 'bootstrap-4-classes';

export const rule = createEslintRule({
  name: RULE_NAME,
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      bootstrap4classes: 'Please update Bootstrap 4 classes to Bootstrap 5. See https://bugs.launchpad.net/evergreen/+bug/2106421 for details.',
    },
    fixable: 'code'
  },
  defaultOptions: [],
  create: (context) => {
    const parserServices = getTemplateParserServices(context);
    
    return {
      'TextAttribute[name="class"]': (node) => {
        let elementClassStr = node.value.toString();
        
        /**
         * This map has regular expression patterns as its keys and replacement
         * patterns as its values. They will be used first to test whether the
         * element's class string as a whole has any matching pattern in the keys.
         * If it does, we'll loop through all the keys and replace them with the values.
         */
        const bs4 = new Map();
        bs4.set('-left', '-start');
        bs4.set('-right', '-end');
        bs4.set('badge-pill', 'badge rounded-pill');
        bs4.set('btn-block', 'd-grid gap-0');
        bs4.set('["| ]close["| ]', 'btn-close');
        bs4.set('font-italic', 'fst-italic');
        bs4.set('font-weight-', 'fw-');
        bs4.set('input-group-append', 'input-group-text');
        bs4.set('input-group-prepend', 'input-group-text');
        bs4.set('ml-', 'ms-');
        bs4.set('mr-', 'me-');
        bs4.set('pl-', 'ps-');
        bs4.set('pr-', 'pe-');
        bs4.set('rounded-sm', 'rounded-1');
        bs4.set('rounded-lg', 'rounded-3');
        bs4.set('sr-only', 'visually-hidden');
        bs4.set('text-monospace', 'font-monospace');
        const bs4Classes = [...bs4.keys()];

        // quick true/false test: any obsolete classes here?
        const testPatterns = new RegExp(bs4Classes.join('|'), 'gm');
        const foundBs4Classes = testPatterns.test(elementClassStr);

        if (foundBs4Classes) {
            const loc = parserServices.convertNodeSourceSpanToLoc(
                node.sourceSpan,
            );

            // replace the obsolete classes
            bs4Classes.forEach(className => {
                elementClassStr = elementClassStr.replaceAll(new RegExp(className, 'gm'), bs4.get(className));
            });
            
            context.report({
            loc,
            messageId: 'bootstrap4classes',
            fix: (fixer) => {
                return fixer.replaceTextRange(
                    [node.sourceSpan.start.offset, node.sourceSpan.end.offset],
                    `class="${elementClassStr}"`
                    )
                }
            });
        }
      },
    };
  },
});

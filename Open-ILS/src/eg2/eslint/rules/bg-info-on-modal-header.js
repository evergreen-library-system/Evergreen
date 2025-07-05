import { getTemplateParserServices } from '@angular-eslint/utils';
import { createEslintRule } from '../utils.js';

export const RULE_NAME = 'bg-info-on-modal-header';

export const rule = createEslintRule({
  name: RULE_NAME,
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      bgInfoOnModalHeader: 'Unneeded bg-info class on a modal header.  Please remove it (see https://bugs.launchpad.net/evergreen/+bug/2008918 for more info)',
    },
    fixable: 'code'
  },
  defaultOptions: [],
  create: (context) => {
    const parserServices = getTemplateParserServices(context);
    
    return {
      'TextAttribute[name="class"]': (node) => {
        const classes = node.value?.split(' ');
        if (classes?.includes('bg-info') && classes?.includes('modal-header')) {
          const loc = parserServices.convertNodeSourceSpanToLoc(
            node.sourceSpan,
          );
          
          context.report({
            loc,
            messageId: 'bgInfoOnModalHeader',
            fix: (fixer) => {
              return fixer.replaceTextRange(
                [node.sourceSpan.start.offset, node.sourceSpan.end.offset],
                `class="${classes.filter(c => c !== 'bg-info').join(' ')}"`
              )
            }
          });
        }
      },
    };
  },
});

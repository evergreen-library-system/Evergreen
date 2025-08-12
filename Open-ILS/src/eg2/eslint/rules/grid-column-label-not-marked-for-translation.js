import { getTemplateParserServices } from '@angular-eslint/utils';
import { createEslintRule } from '../utils.js';

export const RULE_NAME = 'grid-column-label-not-marked-for-translation';

export const rule = createEslintRule({
  name: RULE_NAME,
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      gridColumnLabelNotMarkedForTranslation: 'This grid column has a label that is not marked for translation.',
    },
    fixable: 'code'
  },
  defaultOptions: [],
  create: (context) => {
    const parserServices = getTemplateParserServices(context);

    return {
      'Element$1[name="eg-grid-column"]': (column) => {
        const labelCannotBeTranslated = column.attributes.some(attribute => attribute.name == 'label' && !attribute.i18n);
        if(labelCannotBeTranslated) {
          const loc = parserServices.convertNodeSourceSpanToLoc(
            column.sourceSpan,
          );

          const labelSpan = column.attributes
            .find(attribute => attribute.name == 'label' && !attribute.i18n)
            .sourceSpan;
          context.report({
            loc,
            messageId: 'gridColumnLabelNotMarkedForTranslation',
            fix: (fixer) => {
              return fixer.insertTextAfterRange(
                [labelSpan.start.offset, labelSpan.end.offset],
                ' i18n-label'
              )
            }
          });
        }
      },
    };
  },
});

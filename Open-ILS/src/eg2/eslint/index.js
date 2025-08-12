import { rule as bgInfoOnModalHeader,
    RULE_NAME as bgInfoOnModalHeaderRuleName
} from './rules/bg-info-on-modal-header.js'
import { rule as bootstrap4Classes,
    RULE_NAME as bootstrap4ClassesRuleName
} from './rules/bootstrap-4-classes.js'
import { rule as gridColumnLabelNotMarkedForTranslation,
    RULE_NAME as gridColumnLabelNotMarkedForTranslationRuleName
} from './rules/grid-column-label-not-marked-for-translation.js'

// This is our plugin of custom rules, which is then used in eg2's
// eslint config file.
export default {
    rules: {
        [bgInfoOnModalHeaderRuleName]: bgInfoOnModalHeader,
        [bootstrap4ClassesRuleName]: bootstrap4Classes,
        [gridColumnLabelNotMarkedForTranslationRuleName]: gridColumnLabelNotMarkedForTranslation,
    },
    configs: {
        recommended: {
            plugins: ['eg-custom-lint-rules'],
            rules: {
                [`eg-custom-lint-rules/${bgInfoOnModalHeaderRuleName}`]: 'error',
                [`eg-custom-lint-rules/${bootstrap4ClassesRuleName}`]: 'error',
                [`eg-custom-lint-rules/${gridColumnLabelNotMarkedForTranslationRuleName}`]: 'error',
            }
        }
    }
};

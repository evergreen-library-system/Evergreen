import { rule as bgInfoOnModalHeader,
    RULE_NAME as bgInfoOnModalHeaderRuleName
} from './rules/bg-info-on-modal-header.js'

// This is our plugin of custom rules, which is then used in eg2's
// eslint config file.
export default {
    rules: {
        [bgInfoOnModalHeaderRuleName]: bgInfoOnModalHeader,
    },
    configs: {
        recommended: {
            plugins: ['eg-custom-lint-rules'],
            rules: {
                [`eg-custom-lint-rules/${bgInfoOnModalHeaderRuleName}`]: 'error',
            }
        }
    }
};

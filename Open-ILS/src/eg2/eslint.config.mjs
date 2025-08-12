import { defineConfig, globalIgnores } from "eslint/config";
import tsParser from "@typescript-eslint/parser";
import tsEslintPlugin from "@typescript-eslint/eslint-plugin";
import angularPlugin from '@angular-eslint/eslint-plugin';
import angularTemplateParser from "@angular-eslint/template-parser";
import path from "node:path";
import { fileURLToPath } from "node:url";
import js from "@eslint/js";
import { FlatCompat } from "@eslint/eslintrc";
import rxjsX from 'eslint-plugin-rxjs-x';
import egRules from 'eg-custom-eslint-rules';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
    baseDirectory: __dirname,
    recommendedConfig: js.configs.recommended,
    allConfig: js.configs.all
});

export default defineConfig([globalIgnores(["projects/**/*"]), {
    files: ["**/*.ts"],

    plugins: {
        "@typescript-eslint": tsEslintPlugin,
        "rxjs-x": rxjsX,
    },

    extends: [...compat.extends(
        "eslint:recommended",
        "plugin:@angular-eslint/recommended",
        "plugin:@angular-eslint/template/process-inline-templates",
        ),
    ],

    languageOptions: {
        parser: tsParser,
        ecmaVersion: 5,
        sourceType: "module",

        parserOptions: {
            "project": ["tsconfig.json", "tsconfig.app.json", "tsconfig.spec.json", "e2e/tsconfig.json"],
            createDefaultProgram: true,
            projectService: true,
        },
    },

    rules: {
        "brace-style": ["error", "1tbs", {
            allowSingleLine: true,
        }],

        curly: "error",
        "eol-last": "error",
        eqeqeq: "error",
        "guard-for-in": "error",

        indent: ["error", 4, {
            SwitchCase: 1,
        }],

        "max-len": ["error", {
            code: 140,
        }],

        "no-await-in-loop": "error",
        "no-bitwise": "error",
        "no-caller": "error",
        "no-duplicate-imports": "error",
        "no-eval": "error",
        "no-var": "error",
        "no-labels": "error",

        "no-magic-numbers": ["error", {
            ignore: [-1, 0, 1, 2, 10, 24, 60, 100, 1000],
        }],

        "no-shadow": "error",
        "no-trailing-spaces": "error",
        "no-undef": "off",
        "no-undef-init": "error",
        "no-unused-expressions": "error",
        "no-unused-vars": "off",
        "prefer-const": "error",
        quotes: ["error", "single"],
        radix: "error",
        semi: "error",
        "spaced-comment": "error",

        "@angular-eslint/component-selector": ["error", {
            prefix: "eg",
            style: "kebab-case",
            type: "element",
        }],

        "@angular-eslint/directive-selector": ["error", {
            prefix: "eg",
            style: "camelCase",
            type: "attribute",
        }],

        "@typescript-eslint/member-ordering": ["error", {
            default: ["field", "signature", "method"],
        }],

        "@typescript-eslint/no-empty-interface": "error",
        "@typescript-eslint/no-inferrable-types": "error",
        "no-throw-literal": "error",
        "@typescript-eslint/no-misused-new": "error",
        "@typescript-eslint/no-non-null-assertion": "error",
        "@typescript-eslint/unified-signatures": "error",
        "rxjs-x/no-async-subscribe": "error",
        "rxjs-x/no-create": "error",
        "rxjs-x/no-ignored-notifier": "error",
        "rxjs-x/no-ignored-replay-buffer": "error",
        "rxjs-x/no-ignored-takewhile-value": "error",
        "rxjs-x/no-index": "error",
        "rxjs-x/no-internal": "error",
        "rxjs-x/no-nested-subscribe": "error",
        "rxjs-x/no-redundant-notify": "error",
        "rxjs-x/no-sharereplay": "error",
        "rxjs-x/no-subject-unsubscribe": "error",
        "rxjs-x/no-unbound-methods": "error",
        "rxjs-x/no-unsafe-subject-next": "error",
        "rxjs-x/no-unsafe-takeuntil": "error",
        "rxjs-x/prefer-root-operators": "error",
    },
}, {
    files: ["**/*.spec.*"],

    rules: {
        "no-magic-numbers": "off",
    },
}, {
    files: ["**/*.html"],
    extends: compat.extends("plugin:@angular-eslint/template/recommended"),

    languageOptions: {
        parser: angularTemplateParser,
    },
    plugins: {
            '@angular-eslint': angularPlugin,
            'eg-custom-eslint-rules': egRules
    },

    rules: {
        "@angular-eslint/template/alt-text": "error",
        "@angular-eslint/template/elements-content": "error",
        "@angular-eslint/template/interactive-supports-focus": "error",
        "@angular-eslint/template/table-scope": "error",
        "@angular-eslint/template/valid-aria": "error",
        "@angular-eslint/template/role-has-required-aria": "error",
        "@angular-eslint/template/no-positive-tabindex": "error",
        "@angular-eslint/template/no-autofocus": "error",
        "@angular-eslint/template/no-distracting-elements": "error",
        "@angular-eslint/template/click-events-have-key-events": "error",
        "@angular-eslint/template/mouse-events-have-key-events": "error",
        "@angular-eslint/template/button-has-type": "error",
        "eg-custom-eslint-rules/bg-info-on-modal-header": "error",
        "eg-custom-eslint-rules/grid-column-label-not-marked-for-translation": "error",
        "eg-custom-eslint-rules/bootstrap-4-classes": "error",
    },
}]);

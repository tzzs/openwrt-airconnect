import js from '@eslint/js';
import globals from 'globals';

export default [
  {
    ignores: [
      '**/node_modules/**',
      'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airbridge/app.js',
      'packages/luci-app-airconnect-manager/htdocs/luci-static/resources/view/**/*.js',
      'dev/**',
    ],
  },
  js.configs.recommended,
  {
    files: ['**/*.{js,jsx,mjs,cjs}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.browser,
        ...globals.node,
      },
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
    rules: {
      'no-unused-vars': 'off',
      'no-useless-assignment': 'off',
      'no-constant-binary-expression': 'off',
      'preserve-caught-error': 'off',
    },
  },
];

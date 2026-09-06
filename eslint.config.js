import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import prettier from 'eslint-config-prettier';

/**
 * Server-only modules. Nothing under app/frontend/ may reach the filesystem, a
 * database driver, a process, or the Docker API — there is no build in which that
 * would work, and the point of failing here is that the reason is stated.
 *
 * Fitness function AF-04 (M00-13) enforces the same invariant over the whole tree;
 * this rule is the fast, local half that fails while the file is still open.
 */
const SERVER_ONLY_MODULES = [
  { name: 'fs', message: 'the React tree has no filesystem' },
  { name: 'node:fs', message: 'the React tree has no filesystem' },
  { name: 'path', message: 'the React tree has no filesystem' },
  { name: 'node:path', message: 'the React tree has no filesystem' },
  { name: 'child_process', message: 'the React tree does not spawn processes' },
  { name: 'node:child_process', message: 'the React tree does not spawn processes' },
  { name: 'node:process', message: 'the React tree does not read process state' },
  { name: 'pg', message: 'the browser never talks to PostgreSQL' },
  { name: 'dockerode', message: 'only app/executors/ reaches the Docker Engine API' },
];

const SERVER_ONLY_PATTERNS = [
  {
    group: ['node:*'],
    message:
      'server-only module: nothing under app/frontend/ may import a Node built-in. ' +
      'If the value is needed in the browser, the server has to send it as a prop.',
  },
  {
    group: [
      '**/config/*',
      '**/db/*',
      '**/app/models/*',
      '**/app/executors/*',
      '**/app/providers/*',
    ],
    message:
      'server-only code: app/frontend/ must not import from the Rails tree. ' +
      'Inertia props are how the server sends data to the browser.',
  },
];

/**
 * Test selectors are semantic: roles, accessible names, and stable data-testid
 * attributes (Annex D §11.1). A CSS class is a styling decision — using one as a
 * selector couples the test to how something looks, and it breaks the next time it
 * is restyled.
 */
const CSS_CLASS_SELECTOR_MESSAGE =
  'CSS class used as a test selector. Use a role, an accessible name or a stable ' +
  'data-testid instead (Annex D §11.1): getByRole, getByLabelText, getByTestId, ' +
  'page.getByRole(...).';

const cssClassSelectorRules = [
  {
    // page.locator('.foo'), page.$('.foo'), element.querySelector('.foo')
    selector:
      'CallExpression[callee.property.name=/^(locator|querySelector|querySelectorAll|\\$|\\$\\$)$/]' +
      ' > Literal.arguments:first-child[value=/^\\s*[.#]?[\\w-]*\\.[\\w-]+/]',
    message: CSS_CLASS_SELECTOR_MESSAGE,
  },
  {
    // container.getElementsByClassName('foo')
    selector: "CallExpression[callee.property.name='getElementsByClassName']",
    message: CSS_CLASS_SELECTOR_MESSAGE,
  },
  {
    // Testing Library escape hatches that only reach a class
    selector: 'MemberExpression[property.name=/^(getByClassName|queryByClassName)$/]',
    message: CSS_CLASS_SELECTOR_MESSAGE,
  },
];

export default tseslint.config(
  {
    ignores: [
      'node_modules/**',
      'public/**',
      'vendor/**',
      'tmp/**',
      'log/**',
      'coverage/**',
      'playwright-report/**',
      'test-results/**',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  {
    files: ['app/frontend/**/*.{ts,tsx}', 'spec/frontend/**/*.{ts,tsx}', 'e2e/**/*.ts'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: { ...globals.browser },
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
      'jsx-a11y': jsxA11y,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      ...jsxA11y.flatConfigs.recommended.rules,

      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // `any` erases the reason the typecheck exists.
      '@typescript-eslint/no-explicit-any': 'error',
      'no-restricted-syntax': ['error', ...cssClassSelectorRules],
    },
  },

  {
    // The import boundary applies to the React tree itself. Test and E2E files
    // legitimately run in Node.
    files: ['app/frontend/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-imports': [
        'error',
        { paths: SERVER_ONLY_MODULES, patterns: SERVER_ONLY_PATTERNS },
      ],
    },
  },

  {
    // The component library imported in M00-05, verbatim. Rules that would
    // require rewriting it are relaxed here rather than by editing the source,
    // because M00-05 forbids redesigning an imported component's API — an edit
    // here is drift from upstream that nobody would ever reconcile.
    //
    // This list is exactly the imported tree. Adding a path to it is a way to
    // silence a rule, so it needs a Story that says why.
    //
    // Accessibility is not being waived: the runtime axe check over the rendered
    // gallery and journeys (M00-08) is the gate that actually decides WCAG 2.2 AA,
    // and a violation it finds is fixed upstream and re-imported.
    files: [
      'app/frontend/components/{ui,shared,layouts}/**/*.{ts,tsx}',
      'app/frontend/hooks/use-mobile.ts',
      'app/frontend/lib/utils.ts',
    ],
    rules: {
      'react-refresh/only-export-components': 'off',
      '@typescript-eslint/no-empty-object-type': 'off',
      'react-hooks/set-state-in-effect': 'off',
      'jsx-a11y/click-events-have-key-events': 'off',
      'jsx-a11y/no-noninteractive-element-interactions': 'off',
      'jsx-a11y/anchor-has-content': 'off',
    },
  },

  {
    files: ['vite.config.ts', 'eslint.config.js', 'playwright.config.ts', 'vitest.config.ts'],
    languageOptions: { globals: { ...globals.node } },
  },

  // Formatting belongs to Prettier; ESLint stops at correctness.
  prettier,
);

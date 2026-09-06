import '@testing-library/jest-dom/vitest';
import { afterEach, expect, vi } from 'vitest';
import { cleanup } from '@testing-library/react';

// A console error in a component test is a defect, not noise. Radix and React
// report broken accessibility trees, invalid props and bad hook usage there, and a
// suite that ignores them is not checking what it claims to check.
const consoleErrors: string[] = [];
const consoleWarnings: string[] = [];

const originalError = console.error;
const originalWarn = console.warn;

console.error = (...args: unknown[]) => {
  consoleErrors.push(args.map(String).join(' '));
  originalError(...args);
};

console.warn = (...args: unknown[]) => {
  consoleWarnings.push(args.map(String).join(' '));
  originalWarn(...args);
};

export function consoleMessages() {
  return { errors: [...consoleErrors], warnings: [...consoleWarnings] };
}

export function resetConsoleMessages() {
  consoleErrors.length = 0;
  consoleWarnings.length = 0;
}

// jsdom implements neither of these, and the imported components use both.
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

class ResizeObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
}

window.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;

if (!Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = () => {};
}

afterEach(() => {
  const errors = consoleErrors.filter(
    // React reports act() warnings for animation frames the imported components
    // schedule outside a test's control. They are not defects in the component.
    (message) => !message.includes('not wrapped in act('),
  );

  cleanup();
  resetConsoleMessages();

  expect(errors, `component test produced console errors:\n${errors.join('\n')}`).toEqual([]);
});

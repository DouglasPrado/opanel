// Brings @testing-library/jest-dom's matchers into Vitest's `expect`.
//
// The runtime half is registered in spec/frontend/setup.ts; this is the type half,
// and without it `toBeInTheDocument` typechecks as a missing property while
// passing at runtime — a gap that would let the typecheck go quietly useless over
// the test suite.
import '@testing-library/jest-dom/vitest';

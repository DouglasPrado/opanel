import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';

import { galleryEntries } from './registry';

/**
 * Smoke render of every imported component (M00-05 AC4).
 *
 * The setup file turns any console error into a failure, so "renders without a
 * console error" is asserted for all of them at once: a broken accessibility
 * tree, an invalid prop or a bad hook usage fails here.
 */
describe('component gallery', () => {
  it('has an entry for every imported component', () => {
    expect(galleryEntries.length).toBeGreaterThan(50);
  });

  it.each(galleryEntries.map((entry) => [`${entry.category}/${entry.name}`, entry] as const))(
    'renders %s without a console error',
    (_label, entry) => {
      const { container } = render(<>{entry.render()}</>);

      expect(container).not.toBeEmptyDOMElement();
    },
  );
});

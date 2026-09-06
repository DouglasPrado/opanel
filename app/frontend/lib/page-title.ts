const SUFFIX = 'Opanel';

/** Page titles are built in one place so every tab reads the same way. */
export function pageTitle(title: string): string {
  return title ? `${title} · ${SUFFIX}` : SUFFIX;
}

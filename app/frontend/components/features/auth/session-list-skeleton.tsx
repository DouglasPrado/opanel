import { createComponentSkeleton } from '@/components/ui/skeleton/skeleton-layout';

// The loading state of doc 10 §25, built from the same factory every other
// component's skeleton uses rather than a placeholder invented here.
//
// Named for the component rather than `skeleton.tsx`, which is the convention
// under `ui/`: AF-10 refuses a file under `features/` whose name matches a
// primitive, and `ui/skeleton` is one. The rule is right — a feature file called
// `skeleton` is exactly the shape of a primitive being re-created — so the file
// is named, not waived.
const SkeletonSessionList = createComponentSkeleton('SkeletonSessionList', 'list');

export { SkeletonSessionList };

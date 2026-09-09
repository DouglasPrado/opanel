import { EmptyState } from '@/components/shared/states';
import { Title } from '@/components/ui/title';
import { PanelLayout } from '@/components/layouts/panel-layout';

interface TeamProp {
  id: string;
  name: string;
  slug: string;
}

/**
 * The projects section of the panel.
 *
 * It renders the **empty** state rather than a blank page. doc 10 §25 treats an
 * empty state as a required state, and a navigation entry that leads nowhere
 * teaches the operator that the sidebar cannot be trusted — which is worse than
 * a section that says plainly what is coming.
 */
export default function Projects({ team }: { team: TeamProp }) {
  return (
    <PanelLayout section="projects">
      <Title title="Projects" subtitle={team.name} />

      <EmptyState
        title="No projects yet"
        description="A Project groups the environments and services of one application. Projects arrive with M01-07."
        className="mt-6"
      />
    </PanelLayout>
  );
}

import { EmptyState } from '@/components/shared/states';
import { Title } from '@/components/ui/title';
import { PanelLayout } from '@/components/layouts/panel-layout';

interface TeamProp {
  id: string;
  name: string;
  slug: string;
}

/**
 * The settings section of the panel.
 *
 * It renders the **empty** state rather than a blank page. doc 10 §25 treats an
 * empty state as a required state, and a navigation entry that leads nowhere
 * teaches the operator that the sidebar cannot be trusted — which is worse than
 * a section that says plainly what is coming.
 */
export default function Settings({ team }: { team: TeamProp }) {
  return (
    <PanelLayout section="settings">
      <Title title="Settings" subtitle={team.name} />

      <EmptyState
        title="Nothing to configure yet"
        description="Team settings will live here. Team settings arrive with M11."
        className="mt-6"
      />
    </PanelLayout>
  );
}

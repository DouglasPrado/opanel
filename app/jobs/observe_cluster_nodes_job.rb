# Periodic job: observe all cluster nodes in the Swarm.
#
# Scheduled by `config/recurring.yml` to run on a regular cadence. Iterates
# through all clusters and calls `ObserveClusterNodes` for each one.
#
# ## Idempotent
#
# Runs without side effects other than database writes and Docker reads. No state
# is held in process memory. Two runs produce the same state. Can be safely
# interrupted and resumed.
#
# ## Handles cluster iteration robustly
#
# If observation of one cluster fails, the job continues with the next one.
# A failure of a cluster observation does not cause the whole job to fail.
class ObserveClusterNodesJob < ApplicationJob
  queue_as Opanel::Queues::SYSTEM

  def perform
    Cluster.kept.find_each do |cluster|
      ObserveClusterNodes.call(cluster: cluster)
    rescue StandardError => error
      Rails.logger.error(event: "observe_cluster_nodes_job.failed",
        cluster_id: cluster.external_id, team_id: cluster.team.external_id,
        error: error.message, backtrace: error.backtrace.first(5))
    end

    Rails.logger.info(event: "observe_cluster_nodes_job.completed")
  end
end

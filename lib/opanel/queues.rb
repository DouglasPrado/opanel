# frozen_string_literal: true

module Opanel
  # The six logical queues of doc 07 §9.1, named once so jobs, the worker
  # configuration and the tests cannot drift apart.
  #
  # M00 defines the queues and the delivery mechanism only. They have no domain
  # consumers yet — those arrive with the Operation Engine in M01.
  #
  # The queue is a delivery mechanism, never a source of truth. If a message is
  # lost, no intent may be lost with it: the recovery sweep in M01-15 finds
  # Operations left without a valid lease in PostgreSQL and re-enqueues them. No
  # job may assume exactly-once delivery.
  module Queues
    # Build finished → release → Swarm update. High concurrency across Services,
    # serial per Service.
    DEPLOYMENTS = "deployments"

    # Scale, restart, resource update, secret binding. Serial per resource.
    RUNTIME = "runtime"

    # Node drain, promote/demote, cluster maintenance. Low concurrency; some jobs
    # are cluster-exclusive.
    CLUSTER = "cluster"

    # Issue, renew, distribute. Parallel per certificate/domain.
    CERTIFICATES = "certificates"

    # Snapshots and recovery verification. Limited by cluster and storage.
    BACKUP_DR = "backup-dr"

    # Cleanup, reconciliation sweeps, garbage collection. Scheduler-controlled.
    SYSTEM = "system"

    ALL = [ DEPLOYMENTS, RUNTIME, CLUSTER, CERTIFICATES, BACKUP_DR, SYSTEM ].freeze
  end
end

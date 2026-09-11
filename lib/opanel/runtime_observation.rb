# Normalized representation of an observed Swarm resource.
#
# ADR-0009 §2: the Swarm Executor returns runtime observations in this shape,
# extracted from Engine JSON. Every caller — diff, ownership predicate,
# reconciler — reads this instead of Engine JSON directly.
#
# ## Six fields, one contract
#
# `kind`: One of "service", "network", "node" — closed set, raises otherwise.
# `runtime_id`: The Engine's own id (ID for services/nodes, Id for networks).
# `name`: The Engine's Name field (Spec.Name for services/nodes, top-level for networks).
# `labels`: Flattened and never nil; {} when absent.
# `version`: Version.Index (CAS baseline); nil when not available.
# `attributes`: Per-kind allowlist, flat, JSON-primitive values only.
#
# ## Allowlist per kind
#
# - network: driver, scope, attachable, internal
# - service: image, replicas, mode
# - node: role, availability, state, hostname, advertise_address
#
# Nothing else reaches the domain. The executor normalizes; reconcilers,
# diffs and ownership predicates only read the normalized form.
#
module Opanel
  RuntimeObservation = Data.define(:kind, :runtime_id, :name, :labels, :version, :attributes) do
    KINDS = %w[service network node].freeze
    ALLOWLIST_BY_KIND = {
      "network" => %w[driver scope attachable internal].freeze,
      "service" => %w[image replicas mode].freeze,
      "node" => %w[role availability state hostname advertise_address].freeze
    }.freeze

    def initialize(kind:, runtime_id:, name:, labels:, version:, attributes:)
      raise ArgumentError, "invalid kind: #{kind.inspect}" unless KINDS.include?(kind)

      # Normalize labels to empty hash if nil
      labels = {} if labels.nil?

      # Freeze immutable collections
      labels = labels.to_h.freeze
      attributes = attributes.to_h.freeze

      super(
        kind: kind,
        runtime_id: runtime_id,
        name: name,
        labels: labels,
        version: version,
        attributes: attributes
      )
    end

    def inspect
      # Redacted summary: never dump the full body or secrets
      truncated_id = runtime_id.to_s[0..3]
      "#<Opanel::RuntimeObservation #{kind} #{truncated_id}… labels=#{labels.size} attrs=#{attributes.size}>"
    end

    def to_s
      inspect
    end
  end
end

# ADR-0002's identifier convention, applied to a model.
#
# Included per model rather than pushed into `ApplicationRecord`: the technical
# tables that are not domain entities — `infrastructure_checkpoints`, Solid
# Queue's own schema — keep their bigint keys, and a blanket change would either
# break them or force an exception list that says the same thing less clearly.
#
# The id is assigned **before** the insert, in the application. That is what lets
# one transaction build a whole graph — a Service with its Operation and its
# Outbox event — without a round trip per row, which is the transactional
# boundary doc 09 §24 assumes.
module UlidPrimaryKey
  extend ActiveSupport::Concern

  included do
    self.implicit_order_column = "id"

    # A callback, and deliberately one of the local, deterministic kind Annex I
    # §4.1 permits: it assigns a value to the row being written and has no
    # external effect. `||=`, so a caller that supplied an id — a fixture, an
    # import, a test — keeps it.
    before_create { self.id ||= Opanel::Identifier.generate }
  end

  # The external representation of this row: `usr_01HX…`.
  def external_id
    Opanel::Identifier.external(self.class.identifier_type, id)
  end

  class_methods do
    # The key into the prefix registry. Defaults to the model name, so a new
    # entity that forgets to register a prefix fails at its first use rather
    # than emitting a bare ULID.
    def identifier_type
      name.underscore.to_sym
    end
  end
end

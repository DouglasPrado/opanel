# frozen_string_literal: true

module RuboCop
  module Cop
    module Opanel
      # Annex C §7.3: *"Nunca buscar recurso apenas por ID e depois 'confiar' que a
      # rota está no Team correto"*.
      #
      # `TenantScope` makes obeying that rule easy; this cop makes disobeying it
      # visible. Without a check, the rule survives exactly as long as everybody
      # remembers it, and the failure is silent — an unscoped lookup returns the
      # row, so the code works, passes its tests, and leaks.
      #
      # ## Why it walks the receiver chain
      #
      # A first version matched only a bare constant receiver. It caught
      # `Team.find(id)` and missed fifteen other spellings, two of which are the
      # ones a careful author would actually write:
      #
      #   Team.kept.find(params[:id])        # `kept` is a real scope on Team
      #   Team.where(id: params[:id]).first  # the AC's words, literally
      #
      # Neither is contrived, and both leak exactly as much as the canonical form.
      # So the rule is now: **if the chain starts at a tenant-scoped model and
      # anywhere along it looks up by primary key, it is an offence** — however
      # many scopes sit in between.
      #
      # ## What it still allows, and why
      #
      #   TenantScope.for(actor, Team).find(id)  # chain starts at the boundary
      #   team.team_members.find_by(id: id)      # chain starts at an instance,
      #                                          # already scoped by the association
      #   Team.find_by(slug: slug)               # not a primary-key lookup
      #   User.find_by(id: id)                   # User is not tenant-scoped
      #
      # A model is tenant-scoped when it belongs to a Team. The list is explicit
      # rather than derived: a new model is a deliberate decision about tenancy,
      # and defaulting to "not scoped" for anything unknown would make the cop
      # quietly stop covering the entities it exists for. A spec asserts that every
      # model with `belongs_to :team` is in it.
      class UnscopedTenantQuery < Base
        MSG = "Look this up through `TenantScope`, not by id. An unscoped find " \
              "returns rows from other Teams (Annex C §7.3)."

        # Grows with the domain. M01-07 adds Project, M01-11 Environment,
        # M01-12 Service.
        TENANT_SCOPED = %i[Team TeamMember Project Cluster Environment Service].freeze

        # Lookups that are by primary key whatever their arguments.
        BY_KEY = %i[find find_by_id find_by_id!].freeze

        # Lookups that are by primary key only when `id` is among the conditions.
        # `where` is deliberately **not** here. `Team.where(id: ids)` used as a
        # relation — inside a scope, or as a subquery — is legitimate and common;
        # it becomes a lookup only when something takes a row out of it, which the
        # terminators below cover.
        BY_CONDITIONS = %i[find_by find_by! find_or_initialize_by find_or_create_by].freeze

        # A `where(id:)` is only a lookup once something takes a row out of it.
        # Kept separate so `Team.where(id: ids)` used as a relation — legitimate
        # inside a scope — is not confused with fetching one row by its key.
        TERMINATORS = %i[first last take take! first! last! find_by find_by! sole].freeze

        RESTRICT_ON_SEND = (BY_KEY + BY_CONDITIONS + TERMINATORS).uniq.freeze

        def on_send(node)
          return unless primary_key_lookup?(node)

          model = root_constant(node)
          return unless model && TENANT_SCOPED.include?(model)

          add_offense(node)
        end

        private

        # Does this call, or the chain it terminates, fetch by primary key?
        def primary_key_lookup?(node)
          return true if BY_KEY.include?(node.method_name)
          return true if BY_CONDITIONS.include?(node.method_name) && conditions_on_id?(node)

          # `.first` / `.take` and friends: a lookup only when what they terminate
          # is a `where(id: ...)`.
          TERMINATORS.include?(node.method_name) && where_on_id?(node.receiver)
        end

        def conditions_on_id?(node)
          hash = node.arguments.first
          return false unless hash&.hash_type?

          hash.keys.any? { |key| key.respond_to?(:value) && key.value.to_s == "id" }
        end

        def where_on_id?(receiver)
          return false unless receiver.respond_to?(:send_type?) && receiver.send_type?
          return true if receiver.method_name == :where && conditions_on_id?(receiver)

          where_on_id?(receiver.receiver)
        end

        # The constant the chain starts from, however many scopes are stacked on
        # it. `nil` when the chain starts at an instance or at another constant's
        # return value, both of which carry their own scope.
        def root_constant(node)
          receiver = node.receiver

          while receiver.respond_to?(:send_type?) && receiver.send_type?
            receiver = receiver.receiver
          end

          return nil unless receiver.respond_to?(:const_type?) && receiver&.const_type?

          receiver.short_name
        end
      end
    end
  end
end

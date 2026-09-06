FactoryBot.define do
  # Minimal on purpose. A factory that builds more than the object needs makes
  # every test that uses it slower and every failure harder to read, and it hides
  # which attribute the behaviour actually depended on (Annex D §22).
  #
  # Nothing here resembles real data: names are generated, and no fixture in this
  # repository may be copied from production.
  factory :infrastructure_checkpoint do
    sequence(:name) { |n| "checkpoint-#{n}" }
  end
end

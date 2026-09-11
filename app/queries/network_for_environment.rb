# Finds the Network for a given Environment (AC1, M01-17).
#
# ## Tenancy
#
# The query is scoped by the Environment, which is already tenant-scoped.
# No additional tenancy check is needed; the caller has already verified
# access to the Environment.
#
class NetworkForEnvironment
  def self.call(actor:, environment:)
    new(actor: actor, environment: environment).call
  end

  def initialize(actor:, environment:)
    @actor = actor
    @environment = environment
  end

  def call
    @environment.network
  end
end

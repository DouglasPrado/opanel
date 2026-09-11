# Reads the current state of a resource lock (M01-15).
#
# Used to check if a lock is held, who holds it, and whether it has expired.
# Always reads from the database; never assumes state from memory.
#
class ResourceLockState
  def self.for(team:, scope_key:)
    new(team: team, scope_key: scope_key).result
  end

  def initialize(team:, scope_key:)
    @team = team
    @scope_key = scope_key
  end

  def result
    ResourceLock.where(team_id: team.id, scope_key: scope_key).first
  end

  private

  attr_reader :team, :scope_key
end

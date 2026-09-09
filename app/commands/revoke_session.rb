# Ends one session immediately (doc 04 §8.2, AC4).
#
# The lookup is **scoped to the owner in the query**, not fetched by id and then
# checked: Annex C §7.3 is explicit that a resource must never be loaded by
# identifier and the route then trusted for tenancy. A session belonging to
# somebody else therefore answers NOT_FOUND rather than FORBIDDEN — FORBIDDEN
# would confirm that the identifier exists, which is a disclosure by itself.
#
# There is no Policy here and there should not be one yet. RBAC arrives with
# M01-04; the only rule this Story has is "the owner of the session", and it is
# enforced by the scope. A `SessionPolicy` with one caller, written ahead of the
# Story that owns the concept, is an abstraction invented for a gate rather than
# for the problem.
class RevokeSession
  NOT_FOUND_MESSAGE = "That session no longer exists."
  INVALID_MESSAGE = "That is not a valid session identifier."

  def self.call(actor:, session_id:)
    new(actor: actor, session_id: session_id).call
  end

  def initialize(actor:, session_id:)
    @actor = actor
    @session_id = session_id
  end

  def call
    id = Opanel::Identifier.parse(:session, session_id)
    session = actor.sessions.find_by(id: id)

    return Opanel::Result.failure(code: "NOT_FOUND", message: NOT_FOUND_MESSAGE) if session.nil?

    # Idempotent: a second revocation is a no-op that still succeeds, so a
    # retried request and a double-clicked button behave the same.
    already_revoked = session.revoked?

    # One transaction around the revocation and its record (AC11). A session
    # revoked with no trail is the case an operator investigating "who signed me
    # out" cannot answer, and there is no reason to accept it: both writes are to
    # the same database and neither calls out.
    ApplicationRecord.transaction do
      session.revoke!

      unless already_revoked
        AuditTrail.record(action: :session_revoked, actor: actor, resource: session,
          before: { "revoked_at" => nil }, after: session.attributes.slice("revoked_at"))
      end
    end

    unless already_revoked
      Rails.logger.info(event: "auth.session.revoked", session_id: session.external_id,
        revoked_by: "self")
    end

    Opanel::Result.success(session)
  rescue Opanel::Identifier::InvalidIdentifier => error
    # ADR-0002 §4: the wrong type of identifier is a validation failure, never a
    # NOT_FOUND. The code comes from the error so the two cannot drift apart.
    Opanel::Result.failure(code: error.code, message: INVALID_MESSAGE)
  end

  private

  attr_reader :actor, :session_id
end

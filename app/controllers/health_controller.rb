# `GET /up` — the Control Plane's own health and readiness.
#
# Three things are reported separately, because they fail separately and an
# operator responds to each differently: the application booted, PostgreSQL is
# reachable, and the queue can be read. Collapsing them into one boolean throws
# away the only information that makes the endpoint useful.
#
# **A degraded dependency is reported as degraded.** The application never claims
# to be healthy while the database it needs is unreachable (Annex B §20) — the
# response is `503` so a load balancer stops sending traffic, and it names the
# classified cause so RB-01 and RB-02 start in the right place.
#
# **It reveals nothing else.** No version, no hostname, no connection string, no
# resource counts. This endpoint is reachable by anything that can reach the
# panel, and a health check is a favourite reconnaissance target (Annex C §17).
# Inherits ActionController::Base rather than ApplicationController on purpose: a
# health check needs no CSRF token, no Inertia shared props and no browser
# gating, and a load balancer's checker must never be refused for not looking
# like a browser.
class HealthController < ActionController::Base
  def show
    checks = {
      application: { status: "ok" },
      database: database_check,
      queue: queue_check
    }

    ready = checks.values.all? { |check| check[:status] == "ok" }

    render json: { status: ready ? "ok" : "unavailable", checks: checks },
      status: ready ? :ok : :service_unavailable
  end

  private

  def database_check
    result = Opanel::DatabaseConnection.check

    return { status: "ok" } if result.available?

    # The cause, never the detail: the detail carries the adapter's message, which
    # can name a host or a role.
    { status: "unavailable", cause: result.cause.to_s }
  end

  # The queue is a delivery mechanism, so "can it be read" is the question — not
  # "is a worker running", which is a different signal and belongs to M09.
  def queue_check
    SolidQueue::Job.where(finished_at: nil).limit(1).pluck(:id)
    { status: "ok" }
  rescue ActiveRecord::ActiveRecordError => error
    # Deliberately not StandardError: the only failure this check can report on is
    # the queue being unreadable. A NoMethodError in the code above is a defect,
    # and reporting it as "the queue is unavailable" would send an operator to
    # look at the wrong thing — and would be the silent rescue Annex I §7.1
    # forbids. It escapes and becomes a 500.
    { status: "unavailable", cause: Opanel::DatabaseConnection.classify(error).cause.to_s }
  end
end

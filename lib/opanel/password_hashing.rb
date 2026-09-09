# frozen_string_literal: true

require "argon2"
require "securerandom"

module Opanel
  # The only place in the application that names a hashing algorithm.
  #
  # Annex B §13 requires a GPU-resistant hash, preferably Argon2id, with
  # versioned parameters; Annex C §7.1 requires the parameters to be updatable
  # and forbids reversible encryption. There is therefore no `decrypt` here and
  # there must never be one: the only operation on a stored digest is a
  # comparison that answers a boolean.
  #
  # **The parameters are versioned by the digest itself.** A PHC string carries
  # its own `v`, `m`, `t` and `p`:
  #
  #   $argon2id$v=19$m=65536,t=3,p=1$<salt>$<hash>
  #
  # so raising the cost later cannot invalidate an account created under the old
  # one — `verify` reads the parameters out of the row, and `needs_rehash?` tells
  # the login path to upgrade it in place. That is why no
  # `password_params_version` column exists, and why one must not be added.
  module PasswordHashing
    # OWASP's second recommended Argon2id configuration: 64 MiB, three passes,
    # one lane. `m_cost` is the base-2 logarithm, so 16 means 2**16 KiB.
    #
    # Cost is a running expense, not only a security setting: each concurrent
    # verification holds 64 MiB and takes roughly 50–100 ms. Raising it is a
    # capacity decision as much as a hardening one.
    PARAMETERS = { m_cost: 16, t_cost: 3, p_cost: 1 }.freeze

    IDENTIFIER = "$argon2id$"
    HEADER = /\A\$argon2id\$v=\d+\$m=(\d+),t=(\d+),p=(\d+)\$/

    module_function

    def create(candidate)
      Argon2::Password.new(**PARAMETERS).create(candidate.to_s)
    end

    # False for a wrong value **and** for a digest that cannot be read.
    #
    # A truncated or corrupted column must fail the login rather than raise: an
    # exception here reaches the user as a 500 that names the algorithm, and
    # tells an attacker which rows are malformed.
    def verify(digest, candidate)
      return false if digest.nil? || candidate.nil?
      return false unless digest.to_s.start_with?(IDENTIFIER)

      Argon2::Password.verify_password(candidate.to_s, digest.to_s)
    rescue Argon2::ArgonHashFail, ArgumentError, TypeError
      false
    end

    # Whether the stored digest was produced with weaker parameters than the
    # current ones — read from the digest, never from a column.
    def needs_rehash?(digest)
      match = HEADER.match(digest.to_s)
      return true if match.nil?

      memory, time, parallelism = match.captures.map(&:to_i)

      memory < 2**PARAMETERS.fetch(:m_cost) ||
        time < PARAMETERS.fetch(:t_cost) ||
        parallelism < PARAMETERS.fetch(:p_cost)
    end

    # The work the unknown-address branch of a login must still do.
    #
    # Without it, "no such account" returns in microseconds while "wrong
    # password" takes ~60 ms, and the difference answers the question the
    # response refuses to answer (AC6). The digest is a constant, computed once
    # when this file loads, so the cost is paid on the branch rather than on
    # every boot of every process that never authenticates anybody.
    def verify_dummy(candidate)
      verify(DUMMY_DIGEST, candidate)
    end

    # Deliberately a value nothing can supply: this digest must never verify.
    DUMMY_DIGEST = create(SecureRandom.urlsafe_base64(48)).freeze
  end
end

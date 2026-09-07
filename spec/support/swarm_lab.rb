require Rails.root.join("lib/gates/swarm_lab")

# Test helpers for the disposable Swarm lab.
#
# Every resource carries a suffix unique to this run, so two runs cannot collide
# and a leaked resource says what created it. Cleanup is idempotent, because a
# crashed example leaves resources behind and the *next* run has to cope with
# that — a harness that only cleans up on the happy path poisons every run after
# the first failure.
#
# Marked `:swarm`. When Docker is unavailable those examples are **skipped
# explicitly** and never reported as passing (Annex D §7): a green suite that
# silently tested nothing is worse than a red one.
module SwarmLabHelpers
  LAB = Opanel::Gates::SwarmLab

  def lab_label = LAB.label(Rails.root.to_s)
  def lab_prefix = LAB.resource_prefix(Rails.root.to_s)

  # `opanel-lab-<pid>-<n>` — the pid ties a leak to the run that made it.
  def lab_name(kind)
    @lab_name_counter = (@lab_name_counter || 0) + 1
    "#{lab_prefix}-#{kind}-#{Process.pid}-#{@lab_name_counter}"
  end

  def created_resources
    @created_resources ||= []
  end

  def lab_image = LAB.image(Rails.root.to_s)

  def create_lab_service(name: lab_name("svc"), image: lab_image, command: %w[sleep 3600])
    LAB.assert_lab!(Rails.root.to_s)

    LAB.docker!(
      "service", "create", "--detach",
      "--name", name,
      "--label", "#{lab_label}=true",
      "--replicas", "1",
      image, *command
    )

    created_resources << [ "service", name ]
    name
  end

  def create_lab_network(name: lab_name("net"))
    LAB.assert_lab!(Rails.root.to_s)

    LAB.docker!("network", "create", "--driver", "overlay", "--label", "#{lab_label}=true", name)
    created_resources << [ "network", name ]
    name
  end

  # M00-17 declares four resource kinds. Only two were here, and the lab's own
  # `status` and `reset` already looked for orphaned secrets and configs — which
  # nothing could ever create, so that half of the cleanup path was never once
  # exercised.
  #
  # The value goes in over stdin: a Swarm secret loaded from a file is a secret
  # on somebody's disk, which is the thing it exists to avoid.
  def create_lab_secret(name: lab_name("secret"), value: "lab-value-#{SecureRandom.hex(4)}")
    LAB.assert_lab!(Rails.root.to_s)

    _stdout, stderr, status = LAB.docker_input(
      "secret", "create", "--label", "#{lab_label}=true", name, "-", input: value
    )
    raise "could not create the lab secret #{name}: #{stderr.strip}" unless status.success?

    created_resources << [ "secret", name ]
    name
  end

  def create_lab_config(name: lab_name("config"), content: "lab = true\n")
    LAB.assert_lab!(Rails.root.to_s)

    _stdout, stderr, status = LAB.docker_input(
      "config", "create", "--label", "#{lab_label}=true", name, "-", input: content
    )
    raise "could not create the lab config #{name}: #{stderr.strip}" unless status.success?

    created_resources << [ "config", name ]
    name
  end

  def lab_resource_exists?(kind, name)
    LAB.docker!(kind, "ls", "--filter", "name=#{name}", "--format", "{{.Name}}")
      .split("\n").include?(name)
  end

  def lab_service_tasks(name)
    LAB.docker!("service", "ps", name, "--format", "{{.Name}} {{.CurrentState}}")
      .split("\n").reject(&:empty?)
  end

  def lab_service_exists?(name)
    LAB.lab_services(Rails.root.to_s).include?(name)
  end

  # Idempotent by construction: removing what is already gone is not an error.
  # Called from an `after` hook, and safe to call again on the next run.
  #
  # A removal that fails for any *other* reason is an error, and used to be
  # invisible: the exit code was discarded, so a Service that refused to go away
  # became the next run's inherited state and the run that leaked it reported
  # green. Every resource is still attempted before anything is raised — one
  # stuck resource must not strand the rest.
  def cleanup_lab_resources(resources = created_resources)
    failures = resources.filter_map { |kind, name| LAB.remove(kind, name) }
    resources.clear

    return if failures.empty?

    raise "the lab could not be cleaned up:\n  #{failures.join("\n  ")}\n" \
          "Run `bin/swarm-lab reset` — no test may inherit this state."
  end

  def wait_for(description, timeout: 60, interval: 1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      result = yield
      return result if result

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "timed out after #{timeout}s waiting for: #{description}"
      end

      sleep interval
    end
  end
end

RSpec.configure do |config|
  config.include SwarmLabHelpers, :swarm

  config.before(:each, :swarm) do
    unless Opanel::Gates::SwarmLab.available?
      skip "the Docker daemon is not reachable — run `bin/swarm-lab up`. " \
           "This suite is skipped, never reported as passing (Annex D §7)."
    end

    unless Opanel::Gates::SwarmLab.lab_daemon?(Rails.root.to_s)
      skip "this Docker daemon is not the Opanel lab — run `bin/swarm-lab up`."
    end

    unless Opanel::Gates::SwarmLab.image_available?(Rails.root.to_s)
      image = Opanel::Gates::SwarmLab.image(Rails.root.to_s)
      skip "the lab image #{image} is not present on this node. " \
           "Run `docker pull #{image}`, or set OPANEL_LAB_IMAGE to one that is. " \
           "Skipped, never reported as passing."
    end
  end

  config.after(:each, :swarm) { cleanup_lab_resources }
end

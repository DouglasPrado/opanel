# Development seeds.
#
# **Synthetic only.** No production data, no PII, nothing copied from anywhere
# real (Annex D §22). M00 has no domain to seed — the only table that exists is
# the technical marker table — so this is deliberately small. It exists to prove
# the seeding path works and stays idempotent, before there is anything at stake.
#
# Idempotent by construction: `bin/setup` runs it on every invocation, and a seed
# file that cannot be run twice is a seed file nobody dares run once.

checkpoints = {
  "dev-bootstrap" => "written by bin/setup so a fresh clone has something to look at",
  "dev-reconcile-sweep" => "stands in for the periodic sweep M01-15 will own",
  "dev-drift-detector" => "stands in for the drift detection M02 will own"
}.freeze

checkpoints.each_key do |name|
  InfrastructureCheckpoint.converge!(name)
end

puts "Seeded #{checkpoints.size} infrastructure checkpoint(s). " \
     "Total: #{InfrastructureCheckpoint.count}."

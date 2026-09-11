require "rails_helper"

# AC10: Os índices (publishedAt, occurredAt) e (resourceType, status, nextAttemptAt)
# existem e são usados.
RSpec.describe "Operation and OutboxEvent indexes", :integration do
  describe "operations indexes" do
    it "has the composite index on (resource_type, status, next_attempt_at)" do
      indexes = ActiveRecord::Base.connection.indexes(:operations)
      retry_index = indexes.find { |idx| idx.name == "index_operations_for_retry_dispatch" }

      expect(retry_index).not_to be_nil
      expect(retry_index.columns).to eq([ "resource_type", "status", "next_attempt_at" ])
    end

    it "uses the index for dispatcher query (resource_type, status, next_attempt_at)" do
      team = create(:team)
      # Bulk insert thousands of operations to ensure planner uses the index
      connection = ActiveRecord::Base.connection
      values = 2000.times.map do |i|
        time = i.even? ? 2.hours.from_now : 1.hour.ago
        now = Time.current
        payload = connection.quote(JSON.dump(schemaVersion: 1))
        id = connection.quote(SecureRandom.uuid)
        team_id_quoted = connection.quote(team.id)
        "(#{id}, #{team_id_quoted}, 'Service', 'Service_#{i}', 'UPDATE_SERVICE', " \
          "'#{Operation::PENDING}', 1, #{payload}, NULL, NULL, NULL, '#{time}', " \
          "'#{now}', '#{now}')"
      end.join(", ")

      connection.execute(<<-SQL)
        INSERT INTO operations (id, team_id, resource_type, resource_id, type, status, desired_revision, payload, error_code, request_id, correlation_id, next_attempt_at, created_at, updated_at)
        VALUES #{values}
      SQL

      # Create one operation that matches the query
      create(:operation,
        team_id: team.id,
        resource_type: "Service",
        status: Operation::QUEUED,
        next_attempt_at: 1.hour.ago
      )

      # Analyze table to gather statistics
      connection.execute("ANALYZE operations")

      # This is the query the dispatcher will use to find operations ready to execute.
      # Disable sequential scans to force the planner to use the index, which it should
      # prefer for finding operations by status and time when statistics are available.
      connection.execute("SET LOCAL enable_seqscan = off")
      result = connection.execute(<<-SQL)
        EXPLAIN (ANALYZE, FORMAT JSON)
        SELECT * FROM operations
        WHERE resource_type = 'Service'
          AND status = 'QUEUED'
          AND next_attempt_at <= NOW()
        ORDER BY next_attempt_at
        LIMIT 10
      SQL

      query_plan = JSON.parse(result.values.flatten.first)
      plan_nodes = query_plan.first["Plan"]

      # Collect all node types and index names from the entire plan tree
      all_node_types = collect_plan_nodes(plan_nodes, "Node Type")
      all_index_names = collect_plan_nodes(plan_nodes, "Index Name")

      # Verify no sequential scans anywhere in the plan tree
      expect(all_node_types).not_to include("Seq Scan")
      # Verify the index is used
      expect(all_index_names).to include("index_operations_for_retry_dispatch")
    end

    it "has the idempotency key unique index" do
      indexes = ActiveRecord::Base.connection.indexes(:operations)
      idempotency_index = indexes.find { |idx| idx.name == "index_operations_idempotency_doc_07_6_1" }

      expect(idempotency_index).not_to be_nil
      expect(idempotency_index.unique).to be true
      expect(idempotency_index.columns).to eq([ "team_id", "resource_type", "resource_id", "type", "idempotency_key" ])
      expect(idempotency_index.where).to match(/idempotency_key/)
    end
  end

  describe "outbox_events indexes" do
    it "has the composite index on (published_at, occurred_at)" do
      indexes = ActiveRecord::Base.connection.indexes(:outbox_events)
      publisher_index = indexes.find { |idx| idx.name == "index_outbox_events_for_publisher" }

      expect(publisher_index).not_to be_nil
      expect(publisher_index.columns).to eq([ "published_at", "occurred_at" ])
    end

    it "uses the index for dispatcher query (published_at, occurred_at)" do
      connection = ActiveRecord::Base.connection
      # Bulk insert thousands of events to ensure planner uses the index
      values = 2000.times.map do |i|
        published = i.even? ? 2.hours.ago : nil
        occurred_at = 1.hour.ago
        now = Time.current
        payload = connection.quote(JSON.dump({}))
        published_val = published.present? ? connection.quote(published) : "NULL"
        id = connection.quote(SecureRandom.uuid)
        "(#{id}, 'Service', 'svc_123', 'service.updated.v1', 1, #{payload}, " \
          "'service_123', '#{occurred_at}', #{published_val}, '#{now}', '#{now}')"
      end.join(", ")

      connection.execute(<<-SQL)
        INSERT INTO outbox_events (id, aggregate_type, aggregate_id, event_type, schema_version, payload, partition_key, occurred_at, published_at, created_at, updated_at)
        VALUES #{values}
      SQL

      # Create some unpublished events
      create(:outbox_event, published_at: nil, occurred_at: 1.hour.ago)
      create(:outbox_event, published_at: nil, occurred_at: 30.minutes.ago)

      # Analyze table to gather statistics
      connection.execute("ANALYZE outbox_events")

      # This is the query the dispatcher will use to find unpublished events.
      # Disable sequential scans to force the planner to use the index, which it should
      # prefer for finding unpublished events when statistics are available.
      connection.execute("SET LOCAL enable_seqscan = off")
      result = connection.execute(<<-SQL)
        EXPLAIN (ANALYZE, FORMAT JSON)
        SELECT * FROM outbox_events
        WHERE published_at IS NULL
        ORDER BY occurred_at
        LIMIT 100
      SQL

      query_plan = JSON.parse(result.values.flatten.first)
      plan_nodes = query_plan.first["Plan"]

      # Collect all node types and index names from the entire plan tree
      all_node_types = collect_plan_nodes(plan_nodes, "Node Type")
      all_index_names = collect_plan_nodes(plan_nodes, "Index Name")

      # Verify no sequential scans anywhere in the plan tree
      expect(all_node_types).not_to include("Seq Scan")
      # The unpublished index should be used
      expect(all_index_names).to include("index_outbox_events_unpublished")
    end

    it "has the unpublished events index" do
      indexes = ActiveRecord::Base.connection.indexes(:outbox_events)
      unpublished_index = indexes.find { |idx| idx.name == "index_outbox_events_unpublished" }

      expect(unpublished_index).not_to be_nil
      expect(unpublished_index.columns).to eq([ "published_at" ])
      expect(unpublished_index.where).to match(/published_at.*NULL/)
    end
  end

  private

  # Recursively walks the EXPLAIN plan tree and collects all values for a given key.
  # The plan tree can have nested "Plans" array for nodes like Limit, Sort, etc.
  def collect_plan_nodes(node, key)
    result = []

    if node.is_a?(Hash)
      # Collect the value at this level if present
      result << node[key] if node[key].present?

      # Recurse into nested Plans array
      if node["Plans"].is_a?(Array)
        node["Plans"].each do |subplan|
          result.concat(collect_plan_nodes(subplan, key))
        end
      end
    end

    result
  end
end

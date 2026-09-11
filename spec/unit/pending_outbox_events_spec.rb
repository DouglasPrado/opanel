# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PendingOutboxEvents query", type: :unit do
  let(:team) { create(:team) }
  let(:project) { create(:project, team: team) }
  let(:environment) { create(:environment, project: project) }
  let(:service) { create(:service, environment: environment) }

  # Create multiple outbox events: some published, some not
  it "returns only unpublished events ordered by occurred_at" do
    published_event = create(:outbox_event, aggregate_id: service.id, occurred_at: 2.minutes.ago,
published_at: 1.minute.ago)
    unpublished_1 = create(:outbox_event, aggregate_id: service.id, occurred_at: 3.minutes.ago, published_at: nil)
    unpublished_2 = create(:outbox_event, aggregate_id: service.id, occurred_at: 1.minute.ago, published_at: nil)

    query = PendingOutboxEvents.new
    results = query.call

    expect(results.pluck(:id)).to eq([ unpublished_1.id, unpublished_2.id ])
  end

  it "returns empty result when all events are published" do
    create(:outbox_event, aggregate_id: service.id, published_at: 1.minute.ago)
    create(:outbox_event, aggregate_id: service.id, published_at: 2.minutes.ago)

    query = PendingOutboxEvents.new
    results = query.call

    expect(results).to be_empty
  end

  it "respects batch size limit" do
    10.times do |i|
      create(:outbox_event, aggregate_id: service.id, occurred_at: (10 - i).minutes.ago, published_at: nil)
    end

    query = PendingOutboxEvents.new(batch_size: 3)
    results = query.call

    expect(results.count).to eq(3)
  end

  it "orders by occurred_at then created_at for stable ordering" do
    same_time = 5.minutes.ago
    event1 = create(:outbox_event, aggregate_id: service.id, occurred_at: same_time)
    event2 = create(:outbox_event, aggregate_id: service.id, occurred_at: same_time)

    query = PendingOutboxEvents.new
    results = query.call.pluck(:id)

    expect(results).to eq([ event1.id, event2.id ])
  end
end

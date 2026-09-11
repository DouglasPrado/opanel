# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Outbox dispatcher: broker unavailable (AC2)" do
  let(:team) { create(:team) }
  let(:service) { create(:service, team: team) }

  it "does not lose events when broker is down" do
    # Create unpublished events
    event1 = create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 5.minutes.ago)
    event2 = create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 3.minutes.ago)

    # Stub SolidQueue::Job.create! to fail (broker unavailable)
    allow(SolidQueue::Job).to receive(:create!).and_raise(RuntimeError.new("Connection refused"))

    # Run the dispatcher
    PublishPendingOutboxEvents.new.call

    # Events should remain unpublished in the database
    expect(event1.reload.published_at).to be_nil
    expect(event2.reload.published_at).to be_nil
    expect(OutboxEvent.unpublished.count).to eq(2)
  end

  it "age of oldest unpublished event is observable" do
    # Create events at different times
    oldest = create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 10.minutes.ago)
    create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 5.minutes.ago)
    create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 2.minutes.ago)

    # Query the health of the outbox
    health = OutboxHealth.new.call

    # Age should be approximately 10 minutes
    expect(health[:oldest_event_age_seconds]).to be_within(5).of(10.minutes.to_i)
    expect(health[:oldest_event_id]).to eq(oldest.id)
    expect(health[:unpublished_count]).to eq(3)
  end

  it "age continues to rise while broker is down" do
    event = create(:outbox_event, aggregate_id: service.id, published_at: nil, occurred_at: 5.minutes.ago)

    health_1 = OutboxHealth.new.call
    age_1 = health_1[:oldest_event_age_seconds]

    # Simulate time passing
    travel 2.minutes

    health_2 = OutboxHealth.new.call
    age_2 = health_2[:oldest_event_age_seconds]

    # Age should increase
    expect(age_2).to be > age_1
    expect(age_2).to be_within(5).of(age_1 + 120)
  end
end

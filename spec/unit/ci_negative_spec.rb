# frozen_string_literal: true

RSpec.describe "CI negative" do
  it "falha de proposito para o pipeline bloquear" do
    expect(1).to eq(2)
  end
end

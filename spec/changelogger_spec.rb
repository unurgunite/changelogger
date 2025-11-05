# frozen_string_literal: true

RSpec.describe Changelogger do
  it "has a version number" do
    expect(Changelogger::VERSION).not_to be nil
  end
end

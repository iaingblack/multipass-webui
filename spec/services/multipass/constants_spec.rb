# frozen_string_literal: true

require "rails_helper"

RSpec.describe Multipass::NameValidator, type: :service do
  describe ".valid_vm_name?" do
    it "accepts valid VM names" do
      %w[a my-vm VM-abcd test-01 Ubuntu-24-04].each do |name|
        expect(described_class.valid_vm_name?(name)).to be true
      end
    end

    it "rejects flag-injection attempts" do
      %w[--all -name].each do |name|
        expect(described_class.valid_vm_name?(name)).to be false
      end
    end

    it "rejects empty / slash / path-traversal / space / null bytes" do
      bad = [
        "",                # empty
        "foo/bar",         # slash
        "foo..bar",        # path traversal fragment
        "foo bar",         # space
        "foo\x00b",        # null byte
        "a" * 100          # too long
      ]
      bad.each do |name|
        expect(described_class.valid_vm_name?(name)).to be false
      end
    end

    it "raises via validate_vm_name! for invalid names" do
      expect { described_class.validate_vm_name!("--all") }
        .to raise_error(Multipass::NameValidator::ValidationError)
    end
  end

  describe ".valid_group_name?" do
    it "accepts group names with spaces" do
      expect(described_class.valid_group_name?("my group")).to be true
    end

    it "rejects --all" do
      expect(described_class.valid_group_name?("--all")).to be false
    end
  end

  describe ".valid_profile_id?" do
    it "accepts a valid profile id" do
      expect(described_class.valid_profile_id?("dev_server-01")).to be true
    end

    it "rejects --all" do
      expect(described_class.valid_profile_id?("--all")).to be false
    end

    it "rejects empty" do
      expect(described_class.valid_profile_id?("")).to be false
    end
  end

  describe ".valid_playbook_filename?" do
    it "accepts .yml and .yaml" do
      expect(described_class.valid_playbook_filename?("deploy.yml")).to be true
      expect(described_class.valid_playbook_filename?("deploy.yaml")).to be true
    end

    it "rejects missing extension" do
      expect(described_class.valid_playbook_filename?("deploy")).to be false
    end

    it "rejects path traversal" do
      expect(described_class.valid_playbook_filename?("../evil.yml")).to be false
    end
  end
end

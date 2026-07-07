# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Multipass::Playbooks, type: :service do
  describe ".sanitize_playbook_name! rejects" do
    %w[ play ../evil.yml a/b.yml a\\b.yml ..yml bad$.yml ].each do |name|
      it "rejects #{name.inspect}" do
        Dir.mktmpdir do |base|
          expect { described_class.sanitize_playbook_name!(base, name) }
            .to raise_error(ArgumentError)
        end
      end
    end
  end

  describe ".sanitize_playbook_name! accepts" do
    %w[deploy.yml setup.yaml my-play_01.yml].each do |name|
      it "accepts #{name.inspect}" do
        Dir.mktmpdir do |base|
          expect(described_class.sanitize_playbook_name!(base, name)).to start_with(base)
        end
      end
    end
  end

  describe "round-trip write → read → delete" do
    it "persists content exactly" do
      Dir.mktmpdir do |base|
        name = "site.yml"
        content = "- hosts: all\n  tasks:\n    - debug: msg=hi\n"

        described_class.write_playbook(base, name, content)
        expect(File).to exist(File.join(base, name))

        got = described_class.read_playbook(base, name)
        expect(got).to eq(content)

        described_class.delete_playbook(base, name)
        expect(File).not_to exist(File.join(base, name))
      end
    end
  end

  describe ".list_playbooks filters and sorts" do
    it "returns only .yml/.yaml files, alphabetically" do
      Dir.mktmpdir do |base|
        %w[zebra.yml alpha.yaml readme.txt beta.YML config.json].each do |f|
          File.write(File.join(base, f), "x")
        end
        Dir.mkdir(File.join(base, "subdir")) # must be skipped

        got = described_class.list_playbooks(base)
        expect(got).to eq(%w[alpha.yaml beta.YML zebra.yml])
      end
    end

    it "returns [] for a missing directory" do
      got = described_class.list_playbooks("/no/such/dir/exists/here")
      expect(got).to eq([])
    end
  end

  describe ".delete_playbook on missing file" do
    it "raises" do
      Dir.mktmpdir do |base|
        expect { described_class.delete_playbook(base, "missing.yml") }
          .to raise_error(ArgumentError, /not found/)
      end
    end
  end
end

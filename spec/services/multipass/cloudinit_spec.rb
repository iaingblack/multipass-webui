# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Multipass::Cloudinit, type: :service do
  let(:logger) { discard_logger }

  def build_client
    Multipass::Client.new(logger:, runner: no_call_runner)
  end

  describe ".sanitize_template_name! rejects" do
    bad = [
      "",                  # empty
      "foo",               # no extension
      "../evil.yml",       # traversal
      "foo/bar.yml",       # slash
      "foo\\bar.yml",      # backslash
      "..yml",             # traversal substring + invalid
      "foo.yml\x00evil",   # null byte
      "foo bar.yml",       # space
      "foo$.yml"           # special char
    ]
    bad.each do |name|
      it "rejects #{name.inspect}" do
        Dir.mktmpdir do |base|
          expect { described_class.sanitize_template_name!(base, name) }
            .to raise_error(ArgumentError)
        end
      end
    end
  end

  describe ".sanitize_template_name! accepts" do
    %w[a.yml deploy.yaml my-template.yml with_under.yml Name01.YML].each do |name|
      it "accepts #{name.inspect} and stays inside base" do
        Dir.mktmpdir do |base|
          path = described_class.sanitize_template_name!(base, name)
          expect(path).to start_with(base)
        end
      end
    end
  end

  describe "write → read → delete round trip" do
    it "persists content exactly to the expected path" do
      Dir.mktmpdir do |base|
        name = "deploy.yml"
        content = "#cloud-config\nruncmd:\n  - echo hi\n"

        client = build_client
        client.write_cloud_init_template(base, name, content)

        # File lives at the expected path inside base.
        expect(File).to exist(File.join(base, name))

        got = client.read_cloud_init_template(base, name)
        expect(got).to eq(content)

        client.delete_cloud_init_template(base, name)
        expect(File).not_to exist(File.join(base, name))
      end
    end
  end

  describe ".delete_cloud_init_template on missing file" do
    it "raises" do
      Dir.mktmpdir do |base|
        expect { build_client.delete_cloud_init_template(base, "missing.yml") }
          .to raise_error(ArgumentError, /not found/)
      end
    end
  end

  describe ".read_cloud_init_template rejects traversal" do
    it "blocks reads outside base_dir" do
      Dir.mktmpdir do |base|
        outside = File.join(File.dirname(base), "secret.yml")
        File.write(outside, "nope")
        begin
          expect { build_client.read_cloud_init_template(base, "../secret.yml") }
            .to raise_error(ArgumentError)
        ensure
          File.delete(outside)
        end
      end
    end
  end

  describe ".write_cloud_init_template rejects traversal" do
    it "blocks writes outside base_dir" do
      Dir.mktmpdir do |base|
        expect { build_client.write_cloud_init_template(base, "../evil.yml", "x") }
          .to raise_error(ArgumentError)
      end
    end
  end

  describe ".validate_cloud_init_yaml!" do
    it "accepts valid cloud-config" do
      valid = "#cloud-config\npackages:\n  - nginx\n"
      expect(described_class.validate_cloud_init_yaml!(valid)).to be_nil
    end

    it "rejects malformed YAML" do
      invalid = "not: valid: yaml: at: all"
      expect { described_class.validate_cloud_init_yaml!(invalid) }
        .to raise_error(ArgumentError)
    end
  end

  describe "#scan_cloud_init_templates filters by content" do
    it "includes only files with the #cloud-config header" do
      Dir.mktmpdir do |base|
        File.write(File.join(base, "good.yml"),    "#cloud-config\n")
        File.write(File.join(base, "plain.yml"),   "just: yaml\n")
        File.write(File.join(base, "readme.txt"),  "text")

        opts = build_client.scan_cloud_init_templates([ base ])
        labels = opts.map(&:label).sort
        expect(labels).to eq(%w[good.yml])
      end
    end
  end
end

# frozen_string_literal: true

namespace :db do
  desc "Migrate from Go version's ~/.passgo-web/config.json + events.jsonl"
  task :migrate_from_go_config, %i[path] => :environment do |_task, args|
    path = args[:path] || File.expand_path("~/.passgo-web/config.json")

    unless File.exist?(path)
      abort "config.json not found at #{path}. Pass a path: " \
            "rails db:migrate_from_go_config[/path/to/config.json]"
    end

    cfg = JSON.parse(File.read(path))
    puts "→ Importing config from #{path}..."

    ActiveRecord::Base.transaction do
      # Settings (singleton row)
      setting = Setting.current
      setting.update!(
        username: cfg["username"] || "admin",
        # Bcrypt hashes are portable between Go and Ruby — copy verbatim.
        # has_secure_password will accept the $2b$... format.
        password_digest: cfg["password"]
      )
      setting.install_bcrypt_hash!(cfg["password"]) if cfg["password"].to_s.start_with?("$2")

      setting.update!(
        cloud_init_dir: cfg["cloud_init_dir"] || "",
        cloud_init_repo: cfg["cloud_init_repo"] || "",
        playbooks_dir: cfg["playbooks_dir"] || "",
        trust_proxy: cfg["trust_proxy"] || false
      )

      # VM defaults
      if cfg["vm_defaults"]
        vm_defaults = VmDefault.current
        vm_defaults.update!(
          cpus: cfg["vm_defaults"]["cpus"] || 2,
          memory_mb: cfg["vm_defaults"]["memory_mb"] || 1024,
          disk_gb: cfg["vm_defaults"]["disk_gb"] || 8,
          ssh_public_key: cfg["vm_defaults"]["ssh_public_key"],
          ssh_private_key: cfg["vm_defaults"]["ssh_private_key"]
        )
      end

      # Groups + VM assignments
      cfg["groups"]&.each_with_index do |name, i|
        Group.find_or_create_by!(name:) { |g| g.position = i }
      end
      cfg["vm_groups"]&.each do |vm_name, group_name|
        group = Group.find_by(name: group_name)
        VmAssignment.find_or_create_by!(vm_name:) { |a| a.group = group }
      end
      cfg["vm_templates"]&.each do |vm_name, _|
        VmAssignment.find_or_create_by!(vm_name:) { |a| a.is_template = true }
      end

      # Profiles
      cfg["profiles"]&.each do |p|
        Profile.find_or_create_by!(id_slug: p["id"]) do |profile|
          profile.name = p["name"]
          profile.release = p["release"]
          profile.cpus = p["cpus"]
          profile.memory_mb = p["memory_mb"]
          profile.disk_gb = p["disk_gb"]
          profile.cloud_init = p["cloud_init"]
          profile.network = p["network"]
          profile.playbook = p["playbook"]
          profile.group_name = p["group"]
        end
      end

      # Schedules
      cfg["schedules"]&.each do |s|
        Schedule.find_or_create_by!(id_slug: s["id"]) do |sched|
          sched.name = s["name"]
          sched.enabled = s["enabled"]
          sched.action = s["action"]
          sched.time = s["time"]
          sched.days = s["days"]
          sched.target_mode = s["group"].present? ? "group" : "vms"
          sched.vm_names = s["vms"]
          sched.group_name = s["group"]
          sched.playbook = s["playbook"]
        end
      end

      # API tokens
      cfg["api_tokens"]&.each do |t|
        ApiToken.find_or_create_by!(id_slug: t["id"]) do |token|
          token.name = t["name"]
          token.prefix = t["prefix"]
          # Go stores SHA-256 hex in "hash" field; copy directly to sha256_digest
          token.sha256_digest = t["hash"]
          token.created_at = t["created_at"]
        end
      end

      # Webhooks
      cfg["webhooks"]&.each do |w|
        Webhook.find_or_create_by!(id_slug: w["id"]) do |hook|
          hook.name = w["name"]
          hook.url = w["url"]
          hook.enabled = w["enabled"]
          hook.categories = w["categories"]
          hook.results = w["results"]
          hook.secret = w["secret"]
          hook.created_at = w["created_at"]
        end
      end

      # LLM config (Phase 5)
      if cfg["llm"]
        # TODO Phase 5: store in encrypted LlmSetting table
      end
    end

    # Events from JSONL (separate file)
    events_path = File.join(File.dirname(path), "events.jsonl")
    if File.exist?(events_path)
      puts "→ Importing events from #{events_path}..."
      imported = 0
      File.foreach(events_path) do |line|
        next if line.strip.empty?
        begin
          ev = JSON.parse(line)
          Event.find_or_create_by!(id: ev["id"]) do |e|
            e.category = ev["category"]
            e.action = ev["action"]
            e.actor = ev["actor"]
            e.resource = ev["resource"]
            e.result = ev["result"]
            e.detail = ev["detail"]
            e.endpoint = ev["endpoint"]
            e.payload = ev["payload"]
            e.created_at = ev["timestamp"]
          end
          imported += 1
        rescue JSON::ParserError, ActiveRecord::RecordInvalid => e
          warn "skip: #{e.message}"
        end
      end
      puts "  imported #{imported} events"
    end

    puts ""
    puts "✓ Migration complete."
    puts "  Username: #{Setting.current.username}"
    puts "  Groups:   #{Group.count}"
    puts "  VM assignments: #{VmAssignment.count}"
    puts "  Profiles: #{Profile.count}"
    puts "  Schedules: #{Schedule.count}"
    puts "  Tokens:   #{ApiToken.count}"
    puts "  Webhooks: #{Webhook.count}"
    puts "  Events:   #{Event.count}"
  end
end

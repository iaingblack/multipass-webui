# frozen_string_literal: true

require "rails_helper"

RSpec.describe SchedulerTickJob, type: :job do
  let(:client) { instance_double(Multipass::Client) }

  before do
    allow(Multipass::Client).to receive(:new).and_return(client)
  end

  describe "#perform" do
    it "does nothing when no schedules exist" do
      expect { described_class.perform_now }.not_to raise_error
    end

    context "with a schedule that should fire" do
      let!(:schedule) do
        Schedule.create!(
          id_slug: "test-1",
          name: "Test",
          action: "start",
          time: Time.current.strftime("%H:%M"),
          days: [ Time.current.wday ],
          target_mode: "vms",
          vm_names: %w[vm-a vm-b]
        )
      end

      it "starts each target VM" do
        expect(client).to receive(:start_vm).with("vm-a")
        expect(client).to receive(:start_vm).with("vm-b")
        described_class.perform_now
      end

      it "updates last_fired_at to prevent double-fire" do
        allow(client).to receive(:start_vm).twice
        described_class.perform_now
        expect(schedule.reload.last_fired_at).to be_within(2.seconds).of(Time.current)
      end

      it "emits an event for the action" do
        expect(client).to receive(:start_vm).twice
        expect { described_class.perform_now }.to change(Event, :count).by(1)
      end
    end

    context "with a schedule that already fired this minute" do
      let!(:schedule) do
        Schedule.create!(
          id_slug: "test-2",
          name: "Already fired",
          action: "start",
          time: Time.current.strftime("%H:%M"),
          days: [ Time.current.wday ],
          target_mode: "vms",
          vm_names: %w[vm-a],
          last_fired_at: Time.current
        )
      end

      it "does not fire again" do
        expect(client).not_to receive(:start_vm)
        described_class.perform_now
      end
    end

    context "with a start schedule that fails on one VM" do
      let!(:schedule) do
        Schedule.create!(
          id_slug: "test-3",
          name: "Partial fail",
          action: "start",
          time: Time.current.strftime("%H:%M"),
          days: [ Time.current.wday ],
          target_mode: "vms",
          vm_names: %w[good-vm bad-vm]
        )
      end

      it "classifies the result as 'partial'" do
        allow(client).to receive(:start_vm).with("good-vm")
        allow(client).to receive(:start_vm).with("bad-vm").and_raise(Multipass::Client::CommandError.new(%w[start bad-vm], double(success?: false, exitstatus: 1), "", "vm not found"))
        described_class.perform_now
        event = Event.where(action: "start", resource: "Partial fail").last
        expect(event.result).to eq("partial")
      end
    end
  end
end

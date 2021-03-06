require 'rails_helper'

RSpec.describe TestTrack::IdentitySessionDiscriminator do
  let(:identity) { Clown.new(id: 1234) }

  subject { TestTrack::IdentitySessionDiscriminator.new(identity) }

  describe "#with_visitor" do
    it "raises without a provided block" do
      expect { subject.with_visitor }.to raise_exception /must provide block to `with_visitor`/
    end

    context "within a web context" do
      let(:test_track_session) { instance_double(TestTrack::Session) }
      let(:visitor_dsl) { instance_double(TestTrack::VisitorDSL) }

      before do
        allow(RequestStore).to receive(:[]).with(:test_track_session).and_return(test_track_session)
        allow(test_track_session).to receive(:has_matching_identity?).and_return(has_matching_identity)
        allow(test_track_session).to receive(:visitor_dsl).and_return(visitor_dsl)
      end

      context "when the session has a matching identity" do
        let(:has_matching_identity) { true }

        it "yields the session's visitor dsl" do
          subject.with_visitor do |visitor|
            expect(visitor).to eq visitor_dsl
          end

          expect(test_track_session).to have_received(:has_matching_identity?).with(identity)
        end
      end

      context "when the session does not have a matching identity" do
        let(:has_matching_identity) { false }
        let(:visitor_dsl) { instance_double(TestTrack::VisitorDSL) }

        before do
          allow(TestTrack::OfflineSession).to receive(:with_visitor_for).and_yield(visitor_dsl)
        end

        it "creates an offline session and yields its visitor" do
          subject.with_visitor do |visitor|
            expect(visitor).to eq visitor_dsl
          end

          expect(TestTrack::OfflineSession).to have_received(:with_visitor_for).with("clown_id", 1234)
        end
      end
    end

    context "outside of a web context" do
      let(:visitor_dsl) { instance_double(TestTrack::VisitorDSL) }

      before do
        allow(TestTrack::OfflineSession).to receive(:with_visitor_for).and_yield(visitor_dsl)
      end

      it "creates an offline session and yields its visitor" do
        subject.with_visitor do |visitor|
          expect(visitor).to eq visitor_dsl
        end

        expect(TestTrack::OfflineSession).to have_received(:with_visitor_for).with("clown_id", 1234)
      end
    end
  end

  describe "#with_session" do
    it "raises without a provided block" do
      expect { subject.with_session }.to raise_exception /must provide block to `with_session`/
    end

    context "within a web context" do
      let(:test_track_session) { instance_double(TestTrack::Session) }

      before do
        allow(RequestStore).to receive(:[]).with(:test_track_session).and_return(test_track_session)
      end

      it "yields the session" do
        subject.with_session do |session|
          expect(session).to eq test_track_session
        end
      end
    end

    context "outside of a web context" do
      it "raises" do
        expect { subject.with_session {} }.to raise_exception /#with_session called outside of web context/
      end
    end
  end
end

class Tt::Api::V1::VisitorDetailsController < Tt::Api::ApplicationController
  def show
    render json: TestTrack::FakeServer.visitor_details
  end
end

class TestTrack::FakeServer
  class << self
    def split_registry
      TestTrack::Fake::SplitRegistry.instance.splits
    end

    def split_details(name)
      TestTrack::Fake::SplitDetail.new(name).details
    end

    def visitor
      TestTrack::Fake::Visitor.instance
    end

    def visitor_details
      TestTrack::Fake::VisitorDetail.instance
    end

    def assignments
      TestTrack::Fake::Visitor.instance.assignments
    end

    def reset!(seed)
      TestTrack::Fake::Visitor.reset!
      @seed = Integer(seed)
    end

    def seed
      @seed || raise('TestTrack::FakeServer seed not set. Call TestTrack::FakeServer.reset!(seed) to set seed.')
    end
  end
end

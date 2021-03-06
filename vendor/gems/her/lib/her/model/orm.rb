# coding: utf-8
module Her
  module Model
    # This module adds ORM-like capabilities to the model
    module ORM
      extend ActiveSupport::Concern

      # Return `true` if a resource was not saved yet
      def new?
        id.nil?
      end
      alias new_record? new?

      # Return `true` if a resource is not `#new?`
      def persisted?
        !new?
      end

      # Return whether the object has been destroyed
      def destroyed?
        @destroyed == true
      end

      # Save a resource and return `false` if the response is not a successful one or
      # if there are errors in the resource. Otherwise, return the newly updated resource
      #
      # @example Save a resource after fetching it
      #   @user = User.find(1)
      #   # Fetched via GET "/users/1"
      #   @user.fullname = "Tobias Fünke"
      #   @user.save
      #   # Called via PUT "/users/1"
      #
      # @example Save a new resource by creating it
      #   @user = User.new({ :fullname => "Tobias Fünke" })
      #   @user.save
      #   # Called via POST "/users"
      def save
        if valid?
          callback = new? ? :create : :update
          method = self.class.method_for(callback)

          run_callbacks callback do
            run_callbacks :save do
              params = to_params
              self.class.request(to_params.merge(:_method => method, :_path => request_path, :_headers => request_headers, :_options => request_options)) do |parsed_data, response|
                assign_attributes(self.class.parse(parsed_data[:data])) if parsed_data[:data].any?
                @metadata = parsed_data[:metadata]
                @response_errors = parsed_data[:errors]
                self.assign_attributes(status_code: response.status)

                return false if !response.success? || @response_errors.any?
                if self.changed_attributes.present?
                  @previously_changed = self.changed_attributes.clone
                  self.changed_attributes.clear
                end
              end
            end
          end
          true
        else
          false
        end
      end

      # Similar to save(), except that ResourceInvalid is raised if the save fails
      def save!
        if self.save
          true
        elsif response_errors.present?
          raise Her::Errors::ResponseError.for(status_code), "Remote validation of #{self.class.name} failed with a #{status_code}: #{full_error_messages}"
        elsif errors.present?
          raise Her::Errors::RecordInvalid, "Local validation of #{self.class.name} failed: #{errors.full_messages}"
        else
          raise 'unreachable'
        end
      end

      # Destroy a resource
      #
      # @example
      #   @user = User.find(1)
      #   @user.destroy
      #   # Called via DELETE "/users/1"
      def destroy(params = {})
        method = self.class.method_for(:destroy)
        run_callbacks :destroy do
          self.class.request(params.merge(:_method => method, :_path => request_path, :_headers => request_headers, :_options => request_options)) do |parsed_data, response|
            raise Her::Errors::ResponseError.for(response.status).new("Request against #{self.class} returned a #{response.status}") if response.status >= 400
            assign_attributes(self.class.parse(parsed_data[:data])) if parsed_data[:data].any?
            @metadata = parsed_data[:metadata]
            @response_errors = parsed_data[:errors]
            @destroyed = response.success?
          end
        end
        self
      end

      def full_error_messages
        self.response_errors.map do |field, messages|
          "#{field} #{messages.join(', ')}"
        end.join('. ')
      end

      module ClassMethods
        # Create a new chainable scope
        #
        # @example
        #   class User
        #     include Her::Model
        #
        #     scope :admins, lambda { where(:admin => 1) }
        #     scope :page, lambda { |page| where(:page => page) }
        #   enc
        #
        #   User.admins # Called via GET "/users?admin=1"
        #   User.page(2).all # Called via GET "/users?page=2"
        def scope(name, code)
          # Add the scope method to the class
          (class << self; self end).send(:define_method, name) do |*args|
            instance_exec(*args, &code)
          end

          # Add the scope method to the Relation class
          Relation.instance_eval do
            define_method(name) { |*args| instance_exec(*args, &code) }
          end
        end

        # @private
        def scoped
          @_her_default_scope || blank_relation
        end

        # Define the default scope for the model
        #
        # @example
        #   class User
        #     include Her::Model
        #
        #     default_scope lambda { where(:admin => 1) }
        #   enc
        #
        #   User.all # Called via GET "/users?admin=1"
        #   User.new.admin # => 1
        def default_scope(block=nil)
          @_her_default_scope ||= (!respond_to?(:default_scope) && superclass.respond_to?(:default_scope)) ? superclass.default_scope : scoped
          @_her_default_scope = @_her_default_scope.instance_exec(&block) unless block.nil?
          @_her_default_scope
        end

        # Delegate the following methods to `scoped`
        [:all, :where, :create, :create!, :build, :find, :find_by, :first, :first_or_create, :first_or_initialize].each do |method|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{method}(*params)
              scoped.send(#{method.to_sym.inspect}, *params)
            end
          RUBY
        end

        delegate :with_request_headers, :request_headers, :with_request_options, :request_options, to: :scoped

        # Save an existing resource and return it
        #
        # @example
        #   @user = User.save_existing(1, { :fullname => "Tobias Fünke" })
        #   # Called via PUT "/users/1"
        def save_existing(id, params, headers = {}, options = {})
          resource = new(params.merge(primary_key => id))
          resource.request_headers = headers
          resource.request_options = options
          resource.save
          resource
        end

        # Destroy an existing resource
        #
        # @example
        #   User.destroy_existing(1)
        #   # Called via DELETE "/users/1"
        def destroy_existing(id, params = {}, headers = {}, options = {})
          request(params.merge(:_method => method_for(:destroy), :_headers => headers, :_options => options, :_path => build_request_path(params.merge(primary_key => id)))) do |parsed_data, response|
            raise Her::Errors::ResponseError.for(response.status).new("Request against #{name} returned a #{response.status}") if response.status >= 400
            data = parse(parsed_data[:data])
            metadata = parsed_data[:metadata]
            response_errors = parsed_data[:errors]
            new(data.merge(:_destroyed => response.success?, :metadata => metadata, :response_errors => response_errors))
          end
        end

        # Return or change the HTTP method used to create or update records
        #
        # @param [Symbol, String] action The behavior in question (`:create` or `:update`)
        # @param [Symbol, String] method The HTTP method to use (`'PUT'`, `:post`, etc.)
        def method_for(action = nil, method = nil)
          @method_for ||= (superclass.respond_to?(:method_for) ? superclass.method_for : {})
          return @method_for if action.nil?

          action = action.to_s.downcase.to_sym

          return @method_for[action] if method.nil?
          @method_for[action] = method.to_s.downcase.to_sym
        end

        # Build a new resource with the given attributes.
        # If the request_new_object_on_build flag is set, the new object is requested via API.
        def build(attributes = {})
          params = attributes
          return self.new(params) unless self.request_new_object_on_build?

          path = self.build_request_path(params.merge(self.primary_key => 'new'))
          method = self.method_for(:new)

          resource = nil
          self.request(params.merge(:_method => method, :_path => path, :_headers => request_headers)) do |parsed_data, response|
            if response.success?
              resource = self.new_from_parsed_data(parsed_data)
            end
          end
          resource
        end

        private
        # @private
        def blank_relation
          @blank_relation ||= Relation.new(self)
        end
      end
    end
  end
end

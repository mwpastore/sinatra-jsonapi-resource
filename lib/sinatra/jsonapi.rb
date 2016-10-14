# frozen_string_literal: true
require 'json'
require 'jsonapi-serializers'
require 'sinatra/base'

module Sinatra
  module JSONAPI
    MIME_TYPE = 'application/vnd.api+json'

    module RequestHelpers
      def deserialize_request_body
        return {} unless request.body.respond_to?(:size) && request.body.size > 0

        request.body.rewind
        JSON.parse(request.body.read, :symbolize_names=>true)
      rescue JSON::ParserError
        halt 400, 'Malformed JSON in the request body'
      end
    end

    module ResponseHelpers
      def serialize_response_body
        JSON.generate(response.body)
      rescue JSON::GeneratorError
        halt 400, 'Unserializable entities in the response body'
      end

      def normalized_error
        return body if body.is_a?(Hash)

        if not_found? && detail = [*body].first
          title = 'Not Found'
          detail = nil if detail == '<h1>Not Found</h1>'
        elsif env.key?('sinatra.error')
          title = 'Unknown Error'
          detail = env['sinatra.error'].message
        elsif detail = [*body].first
        end

        { title: title, detail: detail }
      end

      def error_hash(title: nil, detail: nil, source: nil)
        { id: SecureRandom.uuid }.tap do |hash|
          hash[:title] = title if title
          hash[:detail] = detail if detail
          hash[:status] = status.to_s if status
          hash[:source] = source if source
        end
      end
    end

    def self.registered(app)
      app.disable :protection # TODO
      app.disable :static

      app.set :show_exceptions, :after_handler
      app.set :progname, 'jsonapi'

      app.mime_type :api_json, MIME_TYPE

      app.helpers RequestHelpers, ResponseHelpers

      app.error 400...600, nil do
        hash = error_hash(normalized_error)
        logger.error(settings.progname) { hash }
        content_type :api_json
        JSON.fast_generate ::JSONAPI::Serializer.serialize_errors [hash]
      end

      app.before do
        halt 406 unless request.preferred_type.entry == MIME_TYPE
        halt 415 unless request.media_type == MIME_TYPE
        halt 415 if request.media_type_params.keys.any? { |k| k != 'charset' }
      end
    end

    def self.extended(base)
      def base.route(*, **opts)
        opts[:provides] ||= :api_json

        super
      end
    end
  end

  register JSONAPI
end

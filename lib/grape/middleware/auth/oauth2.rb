module Grape::Middleware::Auth
  # OAuth 2.0 authorization for Grape APIs.
  class OAuth2 < Grape::Middleware::Base
    def default_options
      {
        token_class: defined?(Doorkeeper) ? 'Doorkeeper::AccessToken' : 'AccessToken',
        realm: 'OAuth API',
        parameter: %w(bearer_token oauth_token),
        accepted_headers: %w(HTTP_AUTHORIZATION X_HTTP_AUTHORIZATION X-HTTP_AUTHORIZATION REDIRECT_X_HTTP_AUTHORIZATION),
        header: [/Bearer (.*)/i, /OAuth (.*)/i],
      }
    end

    def before
      verify_token(token_parameter || token_header)
    end

    def token_parameter
      Array(options[:parameter]).each do |p|
        return request[p] if request[p]
      end
      nil
    end

    def token_header
      return false unless authorization_header
      Array(options[:header]).each do |regexp|
        return $1 if authorization_header =~ regexp
      end
      nil
    end

    def authorization_header
      options[:accepted_headers].each do |head|
        return env[head] if env[head]
      end
      nil
    end

    def token_class      
      @klass ||= (options[:token_class].class == Class) ? options[:token_class] : eval(options[:token_class]) # rubocop:disable Eval
    end

    def verify_token(token_string)      
      token = nil
      token = token_class.verify(token_string) if token_class.respond_to?(:verify)
      token = token_class.authenticate(token_string) if !token && token_class.respond_to?(:authenticate)
      token = token_class.locate(token_string) if !token && token_class.respond_to?(:locate)
          
      if token
        if token.respond_to?(:expired?) && token.expired?
          error_out(401, 'expired_token')
        else
                         
          if defined?(Doorkeeper)
            @scopes = Doorkeeper.configuration.default_scopes
            @scopes = options[:scope].is_a?(Array) ? options[:scope] : [options[:scope]] if options[:scope]
            
            env['api.token'] = token if token.scopes.any? { |scope| @scopes.include? scope}
          else
            env['api.token'] = token if !token.respond_to?(:permission_for?) || token.permission_for?(env)
          end
          
          error_out(403, 'insufficient_scope') unless env['api.token']          
        end
      else
        error_out(401, 'invalid_token')
      end
    end

    def error_out(status, error)
      throw :error,
            message: error,
            status: status,
            headers: {
              'WWW-Authenticate' => "OAuth realm='#{options[:realm]}', error='#{error}'"
            }
    end
  end
end

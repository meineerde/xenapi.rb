# ===========================================================================
# Copyright (c) 2010 Holger Just
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# ===========================================================================
#
# This library is based on
# {XenAPI.py}[http://community.citrix.com/download/attachments/38633496/XenAPI.py]
# by XenSource Inc., licensed under the LGPL.
# ---------------------------------------------------------------------------

require 'uri'
require 'xmlrpc/client'

module XenAPI
  API_VERSION_1_1 = '1.1'
  API_VERSION_1_2 = '1.2'

  RETRY_COUNT = 3

  class SessionInvalidError < Exception; end
  class Failure < Exception
    def initialize(details = [])
      if details.is_a? Array
        @error_type = details[0]
        @error_details = details[1..-1] || []
      else
        @error_details = []
      end
    end

    def to_s
      details = case @error_details.length
        when 0 then ""
        when 1 then @error_details[0]
        else @error_details.inspect
      end

      "#{@error_type.to_s}: #{details}"
    end

    attr_reader :error_type, :error_details
  end

  class Session < ::XMLRPC::Client
    def initialize(uri, proxy_host=nil, proxy_port=nil)
      # uri can be one of:
      #  * "http://server.name/path"
      #  * "https://server.name/path"
      #  * "socket:///var/xapi/xapi"
      # proxy_host and proxy_port can be used to specify an HTTP proxy
      @uri = URI.parse(uri)

      case @uri.scheme.downcase
      when 'http', 'https'
        super(
          @uri.host,
          @uri.path.empty? ? "/" : @uri.path,
          @uri.port,
          proxy_host,
          proxy_port,
          nil, # user
          nil, # password
          (@uri.scheme.downcase == "https")
        )
      when 'socket'
        raise NotImplementedError.new("Sockets are not supported yet. Sorry")
      else
        raise ArgumentError.new("Unknown scheme")
      end

      @api_version = API_VERSION_1_1
      @session = ""
    end

    attr_reader :uri, :api_version
    def session_id
      @session
    end

    LOGIN_METHODS = %w(login_with_password slave_local_login_with_password)
    LOGIN_METHODS.each do |method|
      class_eval <<-"END_EVAL", __FILE__, __LINE__
        def #{method}(*args)
          begin
            result = self.session.#{method}(*args)
          rescue SessionInvalidError
            raise ::XMLRPC::FaultException.new(500,
              'Received SESSION_INVALID when logging in')
          end

          @session = result
          @last_login_method = :#{method}
          @last_login_params = args
          @api_version = _api_version
        end
      END_EVAL
    end

    def logout
      # preferred method to logout the session
      if @last_login_method.to_s.start_with?("slave_local")
        self.session.local_logout
      else
        self.session.logout
      end
    end

    def proxy(prefix=nil, *args)
      # Overrides base method to use our custom Proxy class
      XenAPIProxy.new(self, prefix, args, :call)
    end

    def proxy2(prefix=nil, *args)
      # Overrides base method to use our custom Proxy class
      XenAPIProxy.new(self, prefix, args, :call2)
    end

    def method_missing(sym, *args)
      self.proxy(sym.to_s, *args)
    end

  private
    def _api_version()
      pool = self.pool.get_all()[0]
      host = self.pool.get_master(pool)
      major = self.host.get_API_version_major(host)
      minor = self.host.get_API_version_minor(host)
      "#{major}.#{minor}"
    end

    def _logout
      # called from proxy object to release all session state
      @session = ""
      @last_login_method = nil
      @last_login_params = nil
      @api_version = API_VERSION_1_1
    end
  end

  class XenAPIProxy < ::XMLRPC::Client::Proxy
    def method_missing(method, *args, &block)
      begin
        if (@prefix == 'session.') && (Session::LOGIN_METHODS.include? method.to_s)
          parse_result super(method, *args, &block)
        else
          retry_count = 0
          while (retry_count < RETRY_COUNT)
            session_args = [server(:session)] + args
            begin
              return parse_result super(method, *session_args, &block)
            rescue SessionInvalidError
              retry_count += 1
              if server(:last_login_method)
                @server.send(server(:last_login_method), *server(:last_login_params))
              else
                raise XMLRPC::FaultException.new(401, "You must log in")
              end
            end
          end

          raise ::XMLRPC::FaultException.new(500,
            "Tried #{RETRY_COUNT} times to get a valid session, but failed")
        end
      ensure
        # ensure we clear the global state on logout
        @server.send(:_logout) if (@prefix == 'session.') && (method == :logout)
      end
    end

    # method name clash between built-in clone and the method to clone a VM
    def clone(*args)
      args.length > 0 ? method_missing(:clone, *args) : super
    end

  private
    def server(arg)
      # returns an instance variable of the server
      @server.instance_variable_get("@#{arg.to_s}")
    end

    def parse_result(result)
      unless result.is_a?(Hash) && result.include?('Status')
        raise XMLRPCClientError.new('Missing Status in response from server: ' + result.inspect)
      end

      if result['Status'] == 'Success'
        if result.include? 'Value'
          result['Value']
        else
          raise ::XMLRPC::FaultException.new('Missing Value in response from server')
        end
      else
        if result.include? 'ErrorDescription'
          if result['ErrorDescription'][0] == 'SESSION_INVALID'
            raise SessionInvalidError
          else
            raise Failure.new(result['ErrorDescription'])
          end
        else
          raise ::XMLRPC::FaultException.new('Missing ErrorDescription in response from server')
        end
      end
    end
  end
end

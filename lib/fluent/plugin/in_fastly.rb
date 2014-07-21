#
# Fluent
#
# Copyright (C) 2011 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module Fluent
  class FastlyInput < Input
    Plugin.register_input('fastly', self)

    #FASTLY_REGEXP = /^\<(?<pri>[0-9]+)\>(?<time>[^ ]+)\s(?<fastly_host>[^ ]+)\s(?<tag>[^\[]\[\d+\]\:)\s+(?<message>.*)$/
    FASTLY_REGEXP = /^\<(?<pri>[0-9]+)\>(?<time>[^ ]+)\s(?<fastly_host>[^ ]+)\s(?<tag>[^\[]+)\[\d+\]:\s(?<message>.*)$/
    FASTLY_TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

    #{"method="}%t {"code"}%>s {"request"}%r

    def initialize
      super
      require 'cool.io'
      require 'fluent/plugin/socket_util'
      require 'cgi'
      require 'useragent'
    end

    config_param :port, :integer, :default => 5140
    config_param :bind, :string, :default => '0.0.0.0'
    config_param :tag, :string
    config_param :protocol_type, :default => :udp do |val|
      case val.downcase
      when 'tcp'
        :tcp
      when 'udp'
        :udp
      else
        raise ConfigError, "syslog input protocol type should be 'tcp' or 'udp'"
      end
    end

    def configure(conf)
      super
      @parser  = TextParser::RegexpParser.new(FASTLY_REGEXP, {'time_format' => FASTLY_TIME_FORMAT})
    end

    def start
      callback = method(:receive_data)

      @loop = Coolio::Loop.new
      @handler = listen(callback)
      @loop.attach(@handler)

      @thread = Thread.new(&method(:run))
    end

    def shutdown
      @loop.watchers.each {|w| w.detach }
      @loop.stop
      @handler.close
      @thread.join
    end

    def run
      @loop.run
    rescue
      log.error "unexpected error", :error=>$!.to_s
      log.error_backtrace
    end

    protected

    def receive_data(data, addr)

      @parser.call(data) { |time, record|
        unless time && record
          log.warn "invalid syslog message", :data => data
          return
        end

        pri = record.delete('pri').to_i

        tag = record.delete('tag')

        message = JSON.parse(record.delete('message'))

        ## copy message params into message, skipping null items
        message.each do |k,v|
          record[k] = v unless v == "(null)"
        end

        ## parse url
        record = parse_url(message['url']).merge(record) if message['url']

        record = parse_url(message['referer'], prefix: 'referer_', no_params: true).merge(record) if message['referer']

        record = parse_user_agent(message['user_agent']).merge(record) if message['user_agent']







        emit(tag, time, record)
      }
    rescue => e
      log.error data.dump, :error => e.to_s
      log.error_backtrace
    end

    private

    def listen(callback)
      log.debug "listening syslog socket on #{@bind}:#{@port} with #{@protocol_type}"
      if @protocol_type == :udp
        @usock = SocketUtil.create_udp_socket(@bind)
        @usock.bind(@bind, @port)
        SocketUtil::UdpHandler.new(@usock, log, 2048, callback)
      else
        # syslog family add "\n" to each message and this seems only way to split messages in tcp stream
        Coolio::TCPServer.new(@bind, @port, SocketUtil::TcpHandler, log, "\n", callback)
      end
    end

    def emit(tag, time, record)
      Engine.emit(tag, time, record)
    rescue => e
      log.error "fastly failed to emit", :error => e.to_s, :error_class => e.class.to_s, :tag => tag, :record => Yajl.dump(record)
    end

    def parse_url(url, options = {})

      out = {}
      uri = URI.parse(url)

      key_prefix = options[:prefix] || ""
      no_params = options[:no_params] || false


      out[key_prefix + 'scheme'] = uri.scheme if uri.scheme
      out[key_prefix + 'host'] = uri.host if uri.host
      out[key_prefix + 'path'] = uri.path if uri.path
      #out[key_prefix + 'fragment'] = uri.fragment if uri.fragment



      # emit query params
      unless no_params || uri.query.nil? || uri.query == ""


        CGI::parse(uri.query).each do |k,v|

          prefix_key = key_prefix + k

          if out[prefix_key].nil?

            if v.count > 1
              out[prefix_key] = v
            elsif v.count == 1
              out[prefix_key] = v.first
            else
              out[prefix_key] = true
            end
          end
        end
      end

      out
    rescue => e
      log.error "url parse error", :error => e.to_s
      out
    end

    def parse_user_agent(ua)
      out = {}

      p = UserAgent.parse(ua)

      out["user_agent_browser"] = p.browser
      out["user_agent_platform"] = p.platform
      out["user_agent_version"] = p.version.to_s
      out["user_agent_type"] = p.mobile? ? "mobile" : (p.bot? ? "bot" : "desktop")

      out
    rescue => e
      log.error "user agent parse error", :error => e.to_s
      out
    end

  end
end

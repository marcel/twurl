module Twurl
  class CLI
    SUPPORTED_COMMANDS     = %w(authorize accounts alias set)
    DEFAULT_COMMAND        = 'request'
    PATH_PATTERN           = /^\/\w+/
    README                 = File.dirname(__FILE__) + '/../../README'
    @output              ||= STDOUT

    class << self
      attr_accessor :output

      def run(args)
        options = parse_options(args)
        dispatch(options)
      end

      def dispatch(options)
        client     = OAuthClient.load_from_options(options)
        controller = case options.command
                     when 'authorize'
                       AuthorizationController
                     when 'accounts'
                       AccountInformationController
                     when 'alias'
                       AliasesController
                     when 'set'
                       ConfigurationController
                     when 'request'
                       RequestController
                     end
        controller.dispatch(client, options)
      rescue Twurl::Exception => exception
        abort(exception.message)
      end

      def parse_options(args)
        arguments = args.dup

        Twurl.options         = Options.new
        Twurl.options.trace   = false
        Twurl.options.data    = {}
        Twurl.options.headers = {}

        option_parser = OptionParser.new do |o|
          o.extend AvailableOptions

          o.banner = "Usage: twurl authorize -u username -p password --consumer-key HQsAGcVm5MQT3n6j7qVJw --consumer-secret asdfasd223sd2\n" +
                     "       twurl [options] /statuses/home_timeline.xml\n"                                                                  +
                     "\n"                                                                                                                    +
                     "Supported Commands:\n#{SUPPORTED_COMMANDS.sort.join(', ')}"

          o.section "Getting started:" do
            tutorial
          end

          o.section "Authorization options:" do
            username
            password
            consumer_key
            consumer_secret
            access_token
            token_secret
          end

          o.section "Common options:" do
            trace
            data
            headers
            host
            quiet
            disable_ssl
            request_method
            help
            version
            proxy
          end
        end

        arguments                 = option_parser.parse!(args)
        Twurl.options.command     = extract_command!(arguments)
        Twurl.options.path        = extract_path!(arguments)
        Twurl.options.subcommands = arguments
        Twurl.options
      end

      def output
        if Twurl.options && Twurl.options.output
          Twurl.options.output
        else
          @output
        end
      end

      def print(*args, &block)
        output.print(*args, &block)
        output.flush if output.respond_to?(:flush)
      end

      def puts(*args, &block)
        output.puts(*args, &block)
        output.flush if output.respond_to?(:flush)
      end

      def prompt_for(label)
        system "stty -echo"
        CLI.print "#{label}: "
        result = STDIN.gets.chomp
        CLI.puts
        result
      rescue Interrupt
        exit
      ensure
        system "stty echo"
      end

      private
        def extract_command!(arguments)
          if SUPPORTED_COMMANDS.include?(arguments.first)
            arguments.shift
          else
            DEFAULT_COMMAND
          end
        end

        def extract_path!(arguments)
          path = nil
          arguments.each_with_index do |argument, index|
            if argument[PATH_PATTERN]
              path = arguments.slice!(index)
              break
            end
          end
          path
        end
    end

    module AvailableOptions
      def options
        Twurl.options
      end

      def section(heading, &block)
        separator ""
        separator heading

        instance_eval(&block)
      end

      def tutorial
        on('-T', '--tutorial', "Narrative overview of how to get started using Twurl") do
          CLI.puts IO.read(README)
          exit
        end
      end

      def consumer_key
        on('-c', '--consumer-key [key]', "Your consumer key (required)") do |key|
          options.consumer_key = key ? key : CLI.prompt_for('Consumer key')
        end
      end

      def consumer_secret
        on('-s', '--consumer-secret [secret]', "Your consumer secret (required)") do |secret|
          options.consumer_secret = secret ? secret : CLI.prompt_for('Consumer secret')
        end
      end

      def access_token
        on('-a', '--access-token [token]', 'Your access token') do |token|
          options.access_token = token
        end
      end

      def token_secret
        on('-S', '--token-secret', "Your token secret") do |secret|
          options.token_secret = secret
        end
      end

      def username
        on('-u', '--username [username]', 'Username of account to authorize (required)') do |username|
          options.username = username
        end
      end

      def password
        on('-p', '--password [password]', 'Password of account to authorize (required)') do |password|
          options.password = password ? password : CLI.prompt_for('Password')
        end
      end

      def trace
        on('-t', '--[no-]trace', 'Trace request/response traffic (default: --no-trace)') do |trace|
          options.trace = trace
        end
      end

      def data
        on('-d', '--data [data]', 'Sends the specified data in a POST request to the HTTP server.') do |data|
          data.split('&').each do |pair|
            key, value = pair.split('=', 2)
            options.data[key] = value
          end
        end
      end

      def headers
        on('-A', '--header [header]', 'Adds the specified header to the request to the HTTP server.') do |header|
          key, value = header.split(': ')
          options.headers[key] = value
        end
      end

      def host
        on('-H', '--host [host]', 'Specify host to make requests to (default: api.twitter.com)') do |host|
          options.host = host
        end
      end

      def quiet
        on('-q', '--quiet', 'Suppress all output (default: output is printed to STDOUT)') do |quiet|
          options.output = StringIO.new
        end
      end

      def disable_ssl
        on('-U', '--no-ssl', 'Disable SSL (default: SSL is enabled)') do |use_ssl|
          options.protocol = 'http'
        end
      end

      def request_method
        on('-X', '--request-method [method]', 'Request method (default: GET)') do |request_method|
          options.request_method = request_method.downcase
        end
      end

      def help
        on_tail("-h", "--help", "Show this message") do
          CLI.puts self
          exit
        end
      end

      def version
        on_tail("-v", "--version", "Show version") do
          CLI.puts Version
          exit
        end
      end

      def proxy
        on('-P', '--proxy [proxy]', 'Specify HTTP proxy to forward requests to (default: No proxy)') do |proxy|
          options.proxy = proxy
        end
      end
    end
  end

  class Options < OpenStruct
    DEFAULT_REQUEST_METHOD = 'get'
    DEFAULT_HOST           = 'api.twitter.com'
    DEFAULT_PROTOCOL       = 'https'

    def oauth_client_options
      OAuthClient::OAUTH_CLIENT_OPTIONS.inject({}) do |options, option|
        options[option] = send(option)
        options
      end
    end

    def base_url
      "#{protocol}://#{host}"
    end

    def ssl?
      protocol == 'https'
    end

    def debug_output_io
      super || STDERR
    end

    def request_method
      super || (data.empty? ? DEFAULT_REQUEST_METHOD : 'post')
    end

    def protocol
      super || DEFAULT_PROTOCOL
    end

    def host
      super || DEFAULT_HOST
    end

    def proxy
      super || nil
    end
  end
end

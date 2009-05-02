
require 'optparse'

module Commander
  class Command
    
    attr_accessor :name, :examples, :syntax, :description, :version
    attr_accessor :summary, :proxy_options, :options, :default_command
    attr_reader   :parent
    
    ##
    # Options struct.

    class Options
      include Blank
      
      def initialize
        @table = {}
      end
      
      def __hash__
        @table
      end
      
      def method_missing meth, *args, &block
        meth.to_s =~ /=$/ ? @table[meth.to_s.chop.to_sym] = args.first : @table[meth]
      end
      
      def default defaults = {}
        @table = defaults.merge! @table
      end
      
      def inspect
        "<Commander::Command::Options #{ __hash__.map { |k,v| "#{k}=#{v.inspect}" }.join(', ') }>"
      end
    end
        
    ##
    # Initialize new command with specified _name_.
    
    def initialize parent, name = ''
      @parent = parent
      @name, @examples, @when_called = name.to_s, [], []
      @options, @proxy_options = [], []
      @commands, @aliases, @help = {}, {}, {}
    end

    ##
    # Array of options.

    attr_reader :options

    ##
    # Hash of commands.
    
    attr_reader :commands

    ##
    # Hash of aliases
    
    attr_reader :aliases

    ##
    # Hashe help entries
    
    attr_reader :help

   
    ##
    # Creates and yields a command instance when a block is passed.
    # Otherwise attempts to return the command, raising InvalidCommandError when
    # it does not exist.
    #
    # === Examples
    #    
    #   command :my_command do |c|
    #     c.when_called do |args|
    #       # Code
    #     end
    #   end
    #
    
    def command name, &block
      yield add_command(Commander::Command.new(self, name)) if block
      @commands[name.to_s]
    end

    ##
    # Alias command _name_ with _alias_name_. Optionally _args_ may be passed
    # as if they were being passed straight to the original command via the command-line.
    
    def alias_command alias_name, name, *args
      @commands[alias_name.to_s] = command name
      @aliases[alias_name.to_s] = args
    end
    
    ##
    # Add a command object to this runner.
    
    def add_command command
      @commands[command.name] = command
    end
    
    ##
    # Check if command _name_ is an alias.
    
    def alias? name
      @aliases.include? name.to_s
    end
    
    ##
    # Check if a command _name_ exists.
    
    def command_exists? name
      @commands[name.to_s]
    end

    ##
    # Add a usage example for this command.
    #
    # Usage examples are later displayed in help documentation
    # created by the help formatters.
    #
    # === Examples
    #    
    #   command :something do |c|
    #     c.example "Should do something", "my_command something"
    #   end
    #
    
    def example description, command 
      @examples << [description, command]
    end
    
    ##
    # Add an option.
    #
    # Options are parsed via OptionParser so view it
    # for additional usage documentation. A block may optionally be
    # passed to handle the option, otherwise the _options_ struct seen below 
    # contains the results of this option. This handles common formats such as:
    #
    #   -h, --help          options.help           # => bool
    #   --[no-]feature      options.feature        # => bool
    #   --large-switch      options.large_switch   # => bool
    #   --file FILE         options.file           # => file passed
    #   --list WORDS        options.list           # => array
    #   --date [DATE]       options.date           # => date or nil when optional argument not set
    #
    # === Examples
    #    
    #   command :something do |c|
    #     c.option '--recursive', 'Do something recursively'
    #     c.option '--file FILE', 'Specify a file'
    #     c.option('--info', 'Display info') { puts "handle with block" }
    #     c.option '--[no-]feature', 'With or without feature'
    #     c.option '--list FILES', Array, 'List the files specified'
    #   
    #     c.when_called do |args, options|
    #       do_something_recursively if options.recursive
    #       do_something_with_file options.file if options.file
    #     end 
    #   end
    #
    # === Help Formatters
    #
    # This method also parses the arguments passed in order to determine
    # which were switches, and which were descriptions for the
    # option which can later be used within help formatters
    # using option[:switches] and option[:description].
    #
    # === Input Parsing
    #
    # Since Commander utilizes OptionParser you can pre-parse and evaluate
    # option arguments. Simply require 'optparse/time', or 'optparse/date', as these
    # objects must respond to #parse.
    #
    #   c.option '--time TIME', Time
    #   c.option '--date [DATE]', Date
    #
    
    def option *args, &block
      switches, description = Runner.separate_switches_from_description *args
      proc = block || option_proc(switches)
      @options << {
        :args => args,
        :proc => proc,
        :switches => switches,
        :description => description,
      }
    end
    
    ##
    # Handle execution of command. The handler may be a class, 
    # object, or block (see examples below).
    #
    # === Examples
    #    
    #   # Simple block handling
    #   c.when_called do |args, options|
    #      # do something
    #   end 
    #   
    #   # Create inst of Something and pass args / options
    #   c.when_called MyLib::Command::Something
    #   
    #   # Create inst of Something and use arbitrary method
    #    c.when_called MyLib::Command::Something, :some_method
    #   
    #   # Pass an object to handle callback (requires method symbol)
    #   c.when_called SomeObject, :some_method
    #
    
    def when_called *args, &block
      raise ArgumentError, 'must pass an object, class, or block.' if args.empty? and !block
      @when_called = block ? [block] : args
    end
    
    ##
    # Run the command with _args_.
    #
    # * parses options, call option blocks
    # * invokes when_called proc
    #
    
    def run *args
      call parse_options_and_call_procs(*args)
    end
    
    ##
    # Parses options and calls associated procs, 
    # returning the arguments remaining.
    
    def parse_options_and_call_procs *args
      return args if args.empty?
      @options.inject OptionParser.new do |opts, option| 
        opts.on *option[:args], &option[:proc]
        opts
      end.parse! args
    end
    
    ##
    # Call the commands when_called block with _args_.
    
    def call args = []
      object = @when_called.shift
      meth = @when_called.shift || :call
      options = proxy_option_struct
      case object
      when Proc  ; object.call(args, options)
      when Class ; meth != :call ? object.new.send(meth, args, options) : object.new(args, options)
      else         object.send(meth, args, options) if object
      end 
    end
    
    ##
    # Creates an Options instance populated with the option values
    # collected by the #option_proc.
    
    def proxy_option_struct
      proxy_options.inject Options.new do |options, (option, value)|
        options.__send__ :"#{option}=", value
        options
      end
    end
    
    ##
    # Option proxy proc used when a block is not explicitly passed
    # via the #option method. This allows commander to auto-populate
    # and work with option values.
    
    def option_proc switches
      lambda { |value| proxy_options << [Runner.switch_to_sym(switches.last), value] } 
    end
    
    def inspect #:nodoc:
      "<Commander::Command:#{name}>"
    end

    extend Forwardable
    def_delegators :parent, :say, :color    
  end
end
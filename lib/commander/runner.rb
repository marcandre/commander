
require 'optparse'

module Commander
  class Runner
    
    #--
    # Exceptions
    #++

    class CommandError < StandardError; end
    class InvalidCommandError < CommandError; end
      

    ##
    # Initialize a new command runner. Optionally
    # supplying _args_ for mocking, or arbitrary usage.
    
    def initialize args = ARGV
      @main = Command.new(self, File.basename($0))
      @args = args
      self.help_formatter = :default
      create_default_commands
    end
    
    ##
    # Return singleton Runner instance.
    
    def self.instance
      @singleton ||= new
    end
    
    ##
    # Run command parsing and execution process.
    
    def run!
      trace = false
      require_program :version, :description
      trap('INT') { abort(int_message || "\nProcess interrupted") }
      global_option('-h', '--help', 'Display help documentation') { command(:help).run *@args[1..-1]; return }
      global_option('-v', '--version', 'Display version information') { say version; return } 
      global_option('-t', '--trace', 'Display backtrace when an error occurs') { trace = true }
      parse_global_options
      remove_global_options options, @args
      unless trace
        begin
          run_active_command
        rescue InvalidCommandError => e
          abort "#{e}. Use --help for more information"
        rescue \
          OptionParser::InvalidOption, 
          OptionParser::InvalidArgument,
          OptionParser::MissingArgument => e
          abort e
        rescue => e
          abort "error: #{e}. Use --trace to view backtrace"
        end
      else
        run_active_command
      end
    end
    
    ##
    # Return program version.
    
    def version
      '%s %s' % [program(:name), program(:version)]
    end
    
    ##
    # Run the active command.
    
    def run_active_command
      require_valid_command
      if alias? command_name_from_args
        active_command.run *(aliases[command_name_from_args.to_s] + args_without_command_name)
      else
        active_command.run *args_without_command_name
      end      
    end
    
    ##
    # Assign program information.
    #
    # === Examples
    #    
    #   # Set data
    #   program :name, 'Commander'
    #   program :version, Commander::VERSION
    #   program :description, 'Commander utility program.'
    #   program :help, 'Copyright', '2008 TJ Holowaychuk'
    #   program :help, 'Anything', 'You want'
    #   program :int_message 'Bye bye!'
    #   program :help_formatter, :compact
    #   program :help_formatter, Commander::HelpFormatter::TerminalCompact
    #   
    #   # Get data
    #   program :name # => 'Commander'
    #
    # === Keys
    #
    #   :version         (required) Program version triple, ex: '0.0.1'
    #   :description     (required) Program description
    #   :name            Program name, defaults to basename of executable
    #   :help_formatter  Defaults to Commander::HelpFormatter::Terminal
    #   :help            Allows addition of arbitrary global help blocks
    #   :int_message     Message to display when interrupted (CTRL + C)
    #
    
    HELP_FORMATTER_ALIASES = {
      :default => HelpFormatter::Terminal,
      :compact => HelpFormatter::TerminalCompact
    }.freeze
    
    attr_reader :help_formatter
    def help_formatter=(formatter)
      @help_formatter = HELP_FORMATTER_ALIASES[formatter] || formatter
    end
    
    def program key, *args
      dest = key == :help_formatter ? self : main
      case args.size
      when 0
        dest.send key
      when 1
        dest.send(:"#{key}=", *args)
      when 2
        dest.send(key).send(:[]=, *args)
      end
    rescue
      p "Failed to set #{key} with #{args.inspect}; #{dest.send(key).inspect}"
    end
    
    ##
    # Get active command within arguments passed to this runner.
    
    def active_command
      @__active_command ||= command(command_name_from_args)
    end
    
    ##
    # Attempts to locate a command name from within the arguments.
    # Supports multi-word commands, using the largest possible match.
    
    def command_name_from_args
      @__command_name_from_args ||= (valid_command_names_from(*@args.dup).sort.last || main.default_command)
    end
    
    ##
    # Returns array of valid command names found within _args_.
    
    def valid_command_names_from *args
      arg_string = args.delete_if { |value| value =~ /^-/ }.join ' '
      main.commands.keys.find_all { |n| n if /^#{n}/.match arg_string }
    end
    
    ##
    # Help formatter instance.
    
    def help_formatter_instance
      @__help_formatter ||= help_formatter.new self
    end
    
    ##
    # Return arguments without the command name.
    
    def args_without_command_name
      removed = []
      parts = command_name_from_args.split rescue []
      @args.dup.delete_if do |arg|
        removed << arg if parts.include?(arg) and not removed.include?(arg)
      end
    end
    
    ##
    # Creates default commands such as 'help' which is 
    # essentially the same as using the --help switch.
    
    def create_default_commands
      command :help do |c|
        c.syntax = 'commander help [command]'
        c.description = 'Display global or [command] help documentation.'
        c.example 'Display global help', 'command help'
        c.example "Display help for 'foo'", 'command help foo'
        c.when_called do |args, options|
          enable_paging
          if args.empty?
            say help_formatter_instance.render 
          else
            command = command args.join(' ')
            require_valid_command command
            say help_formatter_instance.render_command(command)
          end
        end
      end
    end
    
    ##
    # Raises InvalidCommandError when a _command_ is not found.
    
    def require_valid_command command = active_command
      raise InvalidCommandError, 'invalid command', caller if command.nil?
    end
    
    ##
    # Removes global _options_ from _args_. This prevents an invalid
    # option error from occurring when options are parsed
    # again for the command.
    
    def remove_global_options options, args
      # TODO: refactor with flipflop, please TJ ! have time to refactor me !
      options.each do |option|
        switches = option[:switches]
        past_switch, arg_removed = false, false
        args.delete_if do |arg|
          # TODO: clean this up, no rescuing ;)
          if switches.any? { |switch| switch.match(/^#{arg}/) rescue false }
            past_switch, arg_removed = true, false
            true
          elsif past_switch && !arg_removed && arg !~ /^-/ 
            arg_removed = true
          else
            arg_removed = true
            false
          end
        end
      end
    end
            
    ##
    # Parse global command options.
    
    def parse_global_options
      options.inject OptionParser.new do |options, option|
        options.on *option[:args], &global_option_proc(option[:switches], &option[:proc])
      end.parse! @args.dup
    rescue OptionParser::InvalidOption
      # Ignore invalid options since options will be further 
      # parsed by our sub commands.
    end
    
    ##
    # Returns a proc allowing for commands to inherit global options.
    # This functionality works whether a block is present for the global
    # option or not, so simple switches such as --verbose can be used
    # without a block, and used throughout all commands.
    
    def global_option_proc switches, &block
      lambda do |value|
        unless active_command.nil?
          active_command.proxy_options << [Runner.switch_to_sym(switches.last), value]
        end
        yield value if block and !value.nil?
      end
    end
    
    ##
    # Raises a CommandError when the program any of the _keys_ are not present, or empty.
        
    def require_program *keys
      keys.each do |key|
        raise CommandError, "program #{key} required" if program(key).nil? or program(key).empty?
      end
    end
    
    ##
    # Return switches and description separated from the _args_ passed.

    def self.separate_switches_from_description *args
      switches = args.find_all { |arg| arg.to_s =~ /^-/ } 
      description = args.last unless !args.last.is_a? String or args.last.match(/^-/)
      return switches, description
    end
    
    ##
    # Attempts to generate a method name symbol from +switch+.
    # For example:
    # 
    #   -h                 # => :h
    #   --trace            # => :trace
    #   --some-switch      # => :some_switch
    #   --[no-]feature     # => :feature
    #   --file FILE        # => :file
    #   --list of,things   # => :list
    #
    
    def self.switch_to_sym switch
      switch.scan(/[\-\]](\w+)/).join('_').to_sym rescue nil
    end
    
    extend Forwardable
    def_delegators :$terminal, :say, :color    

    ##
    # Add a global option; follows the same syntax as Command#option
    # This would be used for switches such as --version, --trace, etc.
    
    def default_command *args
      program :default_command, *args
    end
    
    attr_accessor :int_message, :main
    def_delegator :main, :option, :global_option
    def_delegators :main, :command, :alias_command, :name, :options, :commands, :alias?, :aliases
  end
end

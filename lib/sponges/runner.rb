# encoding: utf-8
module Sponges
  # This class concern is to create a Supervisor, set some signals handlers and
  # watch over the supervisor.
  #
  class Runner
    def initialize(name, options = {}, block)
      @name, @block = name, block
      @options = default_options.merge options
      @redis = Nest.new('sponges', Configuration.redis || Redis.new)
      if running?
        Sponges.logger.error "Runner #{@name} already started."
        exit
      end
      @redis[:hostnames].sadd Socket.gethostname
    end

    def start
      if daemonize?
        Sponges.logger.info "Supervisor daemonized."
        Process.daemon
      end
      Sponges.logger.info "Runner #{@name} start message received."
      @supervisor = fork_supervisor
      trap_signals
      Sponges.logger.info "Supervisor started with #{@supervisor} pid."
      Process.waitpid(@supervisor) unless daemonize?
    end

    private

    def running?
      if pid = @redis[Socket.gethostname][:worker][@name][:supervisor].get
        begin
          Process.kill 0, pid.to_i
          true
        rescue Errno::ESRCH => e
          @redis[Socket.gethostname][:worker][@name][:supervisor].del
          false
        end
      else
        false
      end
    end

    def trap_signals
      Sponges::SIGNALS.each do |signal|
        trap(signal) {|signal| kill_supervisor(signal) }
      end
    end

    def kill_supervisor(signal)
      Sponges.logger.info "Supervisor receive a #{signal} signal."
      Process.kill :USR1, @supervisor
    end

    def default_options
      {
        size: Machine::Info::Cpu.cores_size
      }
    end

    def fork_supervisor
      fork do
        $PROGRAM_NAME = "#{@name}_supervisor"
        Supervisor.new(@name, @options, @block).start
      end
    end

    def daemonize?
      !!@options[:daemonize]
    end
  end
end

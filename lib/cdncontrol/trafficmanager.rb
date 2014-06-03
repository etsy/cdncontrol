require 'app_conf'
require 'json'
require 'dynect_rest'
require 'socket'

module CDNControl
  class TrafficManager

    # The initialize method for the TrafficManager Class.
    # Expects:
    #   config: Valid config in YAML format
    #   target: The target from the config which this instance is to be used with (String)
    #   verbose (optional): Whether or not to log verbosely (Boolean)
    # Returns:
    #   nothing
    def initialize(config,target, verbose=false)
      @config=config
      @zone    = target['zone']
      @nodes   = target['nodes']
      @verbose = verbose
      @weights = Hash.new
      @user = nil

      if @config['eventinator_server']
        require 'eventinator-client'
      end

      # connect to API
      puts "** connecting to dynect API"
      @dyn     = DynectRest.new(@config['organization'], @config['username'], @config['password'], @zone)
      @weights = fetch_weights
    end

    def eventinate(msg)
      if @config['eventinator_server']
        client = EventinatorClient.new @config['eventinator_server']

        if !@user.nil?
          user = @user
        else
          user = ENV['SUDO_USER'] || ENV['USER']
        end

        puts "User: #{user}"
        payload = {
            :status => msg,
            :username   => user,
            :tag    => "cdncontrol"
        }

        begin
          client.create_oneshot(payload)
        rescue
          puts "** Couldn't reach the eventinator server, not eventinating"
        end
      end
    end

    # Same as we do for eventinator, and for say spork, tell IRC when we
    # change things. All this brutally stolen from knife-spork's irccat
    # plugin. It just seemed a shame not to use it.
    def ircinate(msg)
      if @config['irccat']
        irccat = @config['irccat']

        if !@user.nil?
          msg += " by #{@user}"
        else
          user = ENV['SUDO_USER'] || ENV['USER']
          msg += " by #{user}"
        end


        port = 12345
        port = irccat.port if irccat.port

        channels = [ irccat.channel || irccat.channels ].flatten
        channels.each do |channel|
          begin
            # Write the message using a TCP Socket
            socket = TCPSocket.open(irccat.server, port)
            socket.write("#{channel} #{msg}")
          rescue Exception => e
            ui.error 'Failed to post message with irccat.'
            ui.error e.to_s
          ensure
            socket.close unless socket.nil?
          end
        end

      end
    end

    # Mutator method for the @user global
    # Expects:
    #   user: Username to set (String)
    # Returns:
    #   nothing
    def set_user(user)
      @user = user
    end

    # Method to get a list of CDN providers from Dyn
    # Expects:
    #   nothing
    # Returns:
    #   Array of strings
    def get_providers
      @weights.map{|k,v|v.keys}.flatten.uniq
    end

    # Accessor method for the @weights global
    # Expects:
    #   nothing
    # Returns:
    #   Hash of {string,int}
    def get_weights
      @weights
    end

    # Get list of nodes configured for this target
    # Expects:
    #   nothing
    # Returns:
    #   Array of strings
    def get_nodes
      @weights.keys
    end

    # Method to get weights from Dyn's API
    # Expects:
    #   nothing
    # Returns:
    #   Hash of {string,int}
    def fetch_weights
      weights = {}

      print "** fetching node details "
      nodes_queue = Queue.new
      @nodes.each do |node|
        weights[node] = {}
        nodes_queue << node
      end

      threads = []
      nodes_queue.size.times do |i|
        threads << Thread.new do
          node = nodes_queue.pop
          path = "GSLBRegionPoolEntry/#{@zone}/#{node}/global"

          if @verbose
            puts "** fetching #{path}"
          else
            print "."
          end

          # Make a thread-local connection to dyn, so that we open many
          # connections at once.
          dyn_conn = DynectRest.new(@config['organization'], @config['username'], @config['password'], @zone)
          pool = dyn_conn.get(path)

          pool.each do |address|
            address.gsub!("\/REST\/", "")

            if @verbose
              puts "  ** fetching #{address}"
            else
              print "."
            end

            address_detail = dyn_conn.get(address)
            label = address_detail['label']
            weights[node][label] = address_detail
          end
        end
      end
      threads.each(&:join)
      print "done!\n" unless @verbose

      @weu
      weights
    end

    # Method to show current balance
    # Expects:
    #   nothing
    # Returns:
    #   nothing (prints to screen)
    def show_balance(header = "NODE BALANCE")

      puts "\n#{header}"
      puts "=" * header.length

      @weights.each do |node,providers|
        puts "#{node}"
        providers.each do |label,detail|
          printf "  %-12s weight = %2d | serve_mode = %-8s | status = %-4s | address = %s\n",
                 label, detail['weight'], detail['serve_mode'], detail['status'], detail['address']
        end
      end

      puts ""
    end

    # Method to set weight for a provider
    # Expects:
    #   provider: Provider to set weight for (String)
    #   weight: Weight to set provider to (Int)
    #   safe: Whether or not to prompt to confirmation (Boolean, default to true)
    # Returns:
    #   nothing
    def set_weight(provider, weight, safe=true)
      get_yn("You're about to modify the weight of #{provider} to #{weight} are you sure (Y|N)?") unless safe == false
      # do it
      @nodes.each do |node|
        old_weight = @weights[node][provider]['weight']
        address    = @weights[node][provider]['address']

        if weight == old_weight
          puts "** node #{node} weight is already #{old_weight} no change made"
        else
          path = "GSLBRegionPoolEntry/#{@zone}/#{node}/global/#{address}"
          puts "** setting weight = #{weight} on #{path}"
          @dyn.put(path, { "weight" => weight })

          eventinate("modified weight of #{provider} to #{weight} for '#{node}'")
          ircinate("modified weight of #{provider} to #{weight} for '#{node}'")
        end
      end

      puts ""

      # fetch the updated values from dyn
      @weights = fetch_weights
    end

    # Method to set mode for a provider
    # Expects:
    #   provider: Provider to set weight for (String)
    #   mode: Mode to set provider to (String)
    #   safe: Whether or not to prompt to confirmation (Boolean, default to true)
    # Returns:
    #   nothing
    def set_serve_mode(provider, mode, safe=true)
      get_yn("You're about to change the serving mode for #{provider} to '#{mode}' are you sure (Y|N)?") unless safe == false

      # do it
      @nodes.each do |node|
        old_mode = @weights[node][provider]['serve_mode']
        address  = @weights[node][provider]['address']

        if mode == old_mode
          puts "** node #{node} serve mode is already set to '#{old_mode}'"
        else
          path = "GSLBRegionPoolEntry/#{@zone}/#{node}/global/#{address}"
          puts "** setting serve_mode = #{mode} on #{path}"
          @dyn.put(path, { "serve_mode" => mode })

          eventinate("modified serve_mode of #{provider} from '#{old_mode}' to '#{mode}' on #{node}")
          ircinate("modified serve_mode of #{provider} from '#{old_mode}' to '#{mode}' on #{node}")
        end
      end

      # fetch the updated values from dyn
      @weights = fetch_weights
    end

    # Method to set dump current weights to JSON
    # Expects:
    #   target: Target of which to dump weights (String)
    #   output_path: File path to dump JSON files to
    # Returns:
    #   nothing
    def dump_weights(target,output_path)
      ## jankiest thing that will work development approach

      summary = {}

      # assetion here is every node in the target group has same weight (should be true)
      key = @weights.keys.first
      @weights[key].each do |provider, config|
        enabled = config["serve_mode"] != "no" ? true : false
        weight  = config["weight"]
        summary[provider] = { :enabled => enabled, :weight => weight }
      end

      total_weight = 0
      # calculate percentages
      summary.each do |provider,config|
        if config[:enabled]
          total_weight += config[:weight]
        end
      end

      summary.each do |provider,config|
        if config[:enabled]
          pct = (config[:weight].to_f / total_weight) * 100
        else
          pct = 0
        end
        summary[provider][:pct] = pct
      end

      fn = "#{output_path}/cdn_#{target}.json"

      begin
        File.open(fn, 'w') {|f| f.write(summary.to_json) }
      rescue Exception => e
        puts "** WARNING: was unable to update JSON (#{e.message}), dashboards will be inconsistent"
      else
        puts "** Updated details in #{fn}"
      end
    end

    # Helper method to get y/n response
    # Expects:
    #   message: Message for y/n prompt (String)
    # Returns:
    #   nothing
    def get_yn(message)
      while true
        print "#{message} "
        case STDIN.gets.strip
          when 'N', 'n'
            puts "Aborting!"
            exit
          when 'Y', 'y'
            puts ""
            break
        end
      end
    end

  end
end

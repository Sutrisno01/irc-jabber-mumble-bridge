require 'rubygems'
require 'IRC'
require_relative '../lib/module_base'
require_relative '../lib/db_manager'
require 'logger'

$logger = Logger.new(File.dirname(__FILE__) + '/irc.log')

class IRCBridge < ModuleBase
  def startServers
    @db = DbManager.new
    servers = @db.loadServers("irc")
    $logger.debug servers
    servers.each do |server|
      Thread.new do
        begin
          receive(server["ID"], server["server_url"], server["server_port"], server["user_name"])
        rescue StandardError => e
          $logger.debug "IRC crashed. Stacktrace follows."
          $logger.debug e
        end
      end
    end
    loop do
      sleep 0.1
    end
  end
  def receive(serverID, server_url, server_port, server_username)
    @my_name = 'irc'
    @my_short = 'I'

    @channels = @db.loadChannels(serverID)
    @channels_invert = @channels.invert
    $logger.debug @channels_invert
    $logger.debug "Starting Server. Credentials: #{server_url}, #{server_port}, #{server_username}"

    #TODO: Hier muss noch die Logik für mehrere Server umgesetzt werden
    @bot = IRC.new(server_username, server_url, server_port, server_username)
    IRCEvent.add_callback('endofmotd') { |event| joinChannels }
    IRCEvent.add_callback('privmsg') { |event| handleMessage(event) }
    IRCEvent.add_callback('join') { |event| joinMessage event }
    IRCEvent.add_callback('part') { |event| partMessage event }
    IRCEvent.add_callback('quit') { |event| quitMessage event }

    subscribe(@my_name)
    Thread.new do
      loop do
        sleep 0.1
        msg_in = @messages.pop
        #$logger.info "State of message array: #{msg_in.nil?}"
        if !msg_in.nil?
          $logger.info msg_in
          @bot.send_message(@channels_invert[msg_in["user_id"]], "[#{msg_in["source_network_type"]}][#{msg_in["nick"]}]#{msg_in["message"]}")
        end
      end
    end

    @bot.connect
  end

  def handleMessage(message)
    $logger.info "handleMessage wurde aufgerufen"
    if /^\x01ACTION (.)+\x01$/.match(message.message)
      self.publish(source_network_type: @my_short,
                   message: " * [#{message.from}] #{message.message.gsub(/^\x01ACTION |\x01$/, '')}",
                   chat_id: '-145447289')
    else
      self.publish(source_network_type: @my_short, source_network: @my_name,
                   nick: message.from, message: message.message, user_id: @channels[message.channel])
    end
    $logger.info message.message
  end

  def joinMessage(event)
    if event.from != @conf[:nick]
      self.publish(source_network_type: @my_short, message: "#{event.from} kam in den Channel.")
    end
  end

  def partMessage(event)
    if event.from != @conf[:nick]
      self.publish(source_network_type: @my_short, message: "#{event.from} hat den Channel verlassen")
    end
  end

  def quitMessage(event)
    if event.from != @conf[:nick]
      self.publish(source_network_type: @my_short, message: "#{event.from} hat den Server verlassen")
    end
  end

  def command(user, command)
    if command == 'version'
      ver = `uname -a`
      @bot.send_message(@conf[:channel], "Version? Oh... ich hab sowas nicht nicht :'(")
      @bot.send_message(@conf[:channel], "Aber hey ich hab das hier! Mein OS: #{ver}")
    end
    if @conf[:master] == user
      if command == 'ge wek'
        abort
      end
    end
  end

  def joinChannels
    $logger.info "Got motd. Joining Channels."
    @channels.each_key { | key |
      $logger.info "Channel gejoint!"
      @bot.add_channel(key)
    }
  end
end

irc = IRCBridge.new
irc.startServers
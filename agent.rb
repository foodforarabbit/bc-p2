require 'eventmachine'
require 'json'

class UDPHandler < EM::Connection
  DEBUG = FALSE

  ALIVE = 0
  DEAD = 1

  PING = 0
  PING2 = 1
  PING_REQ = 2
  ACK = 3
  ACK2 = 4

  PERIOD_INTERVAL = 5
  WORST_CASE_MESSAGE_RTT = 0.015
  K_RANDOM_MEMBERS = 3
  def initialize(params, config)
    @pr = 0
    @waiting = nil
    @ping_req = []
    @id = params[:id]
    @ip = params[:ip]
    @port = params[:port]
    @config = config.select{|agent| agent[:id] != @id}
    @peers = @config.map{|agent| agent[:id]}
    @addresses = @config.inject({}) do |addresses, config|
      addresses[config[:id]] = config
      addresses
    end
    @status = @peers.inject({}) do |status, agent_id|
      status[agent_id] = ALIVE
      status
    end
    print_debug "\n\n\n\n\n\n\ninitialize"
    new_period
  end

  def new_period
    @pr += 1
    print_debug "\nnew_period"
    peers = [].concat @peers
    @waiting = peers.sample # random id here
    peers -= [@waiting]
    @ping_req = []
    ping_packet = [PING, @pr, @id, @waiting]
    send_datagram_target ping_packet, @waiting
    rtt_started = false
    rtt_timer = EventMachine::PeriodicTimer.new(WORST_CASE_MESSAGE_RTT) do
      print_debug "rtt_timer #{rtt_started}"
      unless rtt_started
        rtt_started = true
      else
        unless @waiting.nil?
          peer_counter = K_RANDOM_MEMBERS
          chosen_peers = []
          while peer_counter > 0 && peers.count > 0
            peer_counter -= 1
            peer = peers.sample
            chosen_peers.push(peer)
            peers -= [peer]
          end
          ping_req_packet = [PING_REQ, @pr, @id, @waiting]
          peers.each do |peer_id|
            send_datagram_target ping_packet, peer_id
          end
        end
        rtt_timer.cancel
      end
    end
    timer_started = false
    timer = EventMachine::PeriodicTimer.new(PERIOD_INTERVAL) do
      print_debug "timer #{timer}"
      unless timer_started
        timer_started = true
      else
        unless @waiting.nil?
          @status[@waiting] = DEAD
        end
        print_message "\n\nPR: #{@pr} ID: #{@id}--------\n#{status_message}"
        timer.cancel
        new_period
      end
    end
  end

  def status_message
    @status.map{|id, status| "   #{id}: #{status == 0 ? 'ALIVE' : 'DEAD'}"}.join("\n")
  end

  def send_datagram_target data, id
    print_debug "send_datagram_target #{data} #{id}"
    unless @addresses[id].nil?
      send_datagram(data.to_json, @addresses[id][:ip], @addresses[id][:port])
    end
  end

  def receive_data(command)
    print_debug "receive_data #{command}"
    command.chomp!
    data = JSON.parse(command)
    print_debug "COMMAND #{data[0]}"
    print_debug "PR #{data[1]} #{@pr}"
    case data[0]
    when PING
      print_debug "PING #{data[3]} #{data[3] == @id} #{@id}"
      if data[3] == @id
        data[0] = ACK
        send_datagram_target data, data[2]
      end
    when PING2
      if data[3] == @id
        data[0] = ACK2
        send_datagram_target data, data[2]
      end
    when PING_REQ
      if data[3] != @id
        send_datagram_target [PING2, data[1], @id, data[3], data[2]], data[3]
        @ping_req.push(data[2])
      end
    when ACK
      return unless data[1] == @pr
      if @waiting == data[3] && data[2] == @id
        @waiting = nil
      end
    when ACK2
      return unless data[1] == @pr
      if @ping_req.include? data[4] && data[2] == @id
        send_datagram_target [ACK, data[1], data[4], data[3]], data[4]
        @ping_req -= [data[4]]
      end
    else
      print_debug "error: #{data}"
    end
  end

  def self.ping_command pr, mi, mj
    [PING, pr, mi, mj]
  end

  def self.ping2_command pr, mi, mj, mm
    [PING2, pr, mi, mj, mm]
  end

  def self.ping_req_command pr, mm, mj
    [PING_REQ, pr, mm, mj]
  end

  def self.ack_command pr, mm, mj
    [ACK, pr, mm, mj]
  end

  def self.ack2_command pr, mm, mi, ml
    [ACK2, pr, mm, mi, ml]
  end


private

  def print_debug msg
    if DEBUG && @id != nil
      print_message msg
      print_message ("\n")
    else
      File.open("debug", 'a') do |file|
        file.write(msg)
        file.write("\n")
      end
    end
  end

  def print_message msg
    if @id.nil?
      print_debug msg
    else
      File.open("status#{@id}", 'a') do |file|
        file.write(msg)
      end
    end
  end
end

class Agent
  def initialize(params, config)
    @ip = params[:ip]
    @port = params[:port]
    EM.run do
      EM.open_datagram_socket(@ip, @port, UDPHandler, params, config)
    end
  end
end

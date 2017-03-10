require_relative './config.rb'
require_relative './agent.rb'

class Bootstrap
  @@pids = []

  def self.boot
    @@pids ||= []
    File.open('debug', 'a') do |file|
      file.write("\n\n\n--------- DEBUG ---------\n")
    end

    CONFIG.each do |agent|
      pid = fork {
        iAgent = Agent.new(agent, CONFIG)
        iAgent.perform
      }
      @@pids.push(pid)
    end
  end

  def self.kill_random
    pid = @@pids.sample
    Process.kill 9, pid
    Process.wait pid
    @@pids -= [pid]
  end

  def self.stop
    puts @@pids.count
    killed = []
    @@pids.each do |pid|
      Process.kill 9, pid
      Process.wait pid
      killed.push(pid)
    end
    @@pids -= killed
    File.open('debug', 'a') do |file|
      file.write("\n\n\n--------- STOPPING #{killed.count} ---------\n")
    end
  end
end

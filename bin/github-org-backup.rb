#!/usr/bin/env ruby
#
#

require 'pp'
require 'rubygems'
require 'json'
require 'yaml'
require 'open-uri'

begin
  API = 'https://api.github.com'
  config_file = ARGV.shift || File.basename($0).gsub(File.extname($0), '.yaml')

  DEBUG = nil

  @@config = YAML.load(open(config_file))
  @backup_dir = @@config[:backup_dir] or raise ":backup_dir not defined"

  # create if it exists
  File.directory?(@backup_dir) or ( Dir.mkdir(@backup_dir) and puts "Creating #{@backup_dir}" )

  # change working dir to backup dir
  Dir.chdir(@backup_dir)

  class Hash
    def fetch_forks
      if self['forks_count'] > 0
        fork_dir = self['full_name'] + '/forks'
        unless File.directory?(fork_dir)
          puts "Creating forks dir #{fork_dir} (#{Dir.pwd})"
          Dir.mkdir(fork_dir)
        end
        api_call("/repos/#{self['full_name']}/forks").map do |fork|
          fork.clone(self['owner']['login'])
        end
      end
    end

    def clone(org)
      if self['fork']
        target = "#{org}/#{self['name']}/forks/#{self['owner']['login']}-#{self['name']}"
      else
        target = "#{self['full_name']}/repo/"
      end
      if File.directory?(target)
        Dir.chdir(target) do
          if File.directory?('.git')
            # already cloned, do an pull
            system "git pull" or raise
          else
            # dir exists but not a repo -- problem
            puts "not a repo!! " + Dir.pwd
          end
        end
      else
        system "git clone --bare #{self['ssh_url']} #{target}" or raise
      end
    end

    def process_repo(org)
      puts "\tProcessing Repo: #{self['full_name']}"
      Dir.mkdir(self['full_name']) unless File.exists?(self['full_name'])
      self.clone(org)
      self.fetch_forks
    end
  end

  def api_call(uri)
    uri = uri =~ /^\// ? API + uri : API + '/' + uri
    puts "fetching #{uri}" if DEBUG
    return JSON.load(open(uri, :http_basic_authentication => [@@api_user, @@api_pass])) or raise
  end

  # each repository in org
  @@config[:orgs].each_key do |org|
    puts "Processing Org: #{org}"
    @@api_user = @@config[:orgs][org][:user]
    @@api_pass = @@config[:orgs][org][:pass]
    Dir.mkdir(org.to_s) unless File.exists?(org.to_s)
    api_call("/orgs/#{org}/repos").map do |repository|
      if @@config[:orgs][org][:included_repos]
        if @@config[:orgs][org][:included_repos].include?(repository['name'])
          repository.process_repo(org)
        end
      else
        if @@config[:orgs][org][:excluded_repos].nil?
          repository.process_repo(org)
        else
          if !@@config[:orgs][org][:excluded_repos].include?(repository['name'])
            repository.process_repo(org)
          end
        end
      end
    end
  end

rescue => e
  puts e.message
end

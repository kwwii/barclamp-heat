# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class HeatService < ServiceObject

  def initialize(thelogger)
    @bc_name = "heat"
    @logger = thelogger
  end

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["heat"]["rabbitmq_instance"] }
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["heat"]["keystone_instance"] }
    answer << { "barclamp" => "database", "inst" => role.default_attributes["heat"]["database_instance"] }
    if role.default_attributes["heat"]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes["heat"]["git_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Heat create_proposal: entering")
    base = super

    base["attributes"][@bc_name]["git_instance"] = ""
    begin
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1]
      if gits.empty?
        # No actives, look for proposals
        gits = gitService.proposals[1]
      end
      unless gits.empty?
        base["attributes"][@bc_name]["git_instance"] = gits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no git found")
    end

    base["attributes"][@bc_name]["database_instance"] = ""
    begin
      databaseService = DatabaseService.new(@logger)
      databases = databaseService.list_active[1]
      if databases.empty?
        # No actives, look for proposals
        databases = databaseService.proposals[1]
      end
      if !databases.empty?
        base["attributes"][@bc_name]["database_instance"] = databases[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no database found")
    end

    base["attributes"][@bc_name]["keystone_instance"] = ""
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals[1]
      end
      if !keystones.empty?
        base["attributes"][@bc_name]["keystone_instance"] = keystones[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no keystone found")
    end

    if base["attributes"][@bc_name]["keystone_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "keystone"))
    end

    base["attributes"][@bc_name]["rabbitmq_instance"] = ""
    begin
      rabbitmqService = RabbitmqService.new(@logger)
      rabbits = rabbitmqService.list_active[1]
      if rabbits.empty?
        # No actives, look for proposals
        rabbits = rabbitmqService.proposals[1]
      end
      unless rabbits.empty?
        base["attributes"][@bc_name]["rabbitmq_instance"] = rabbits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no rabbitmq found")
    end

    if base["attributes"][@bc_name]["rabbitmq_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "rabbitmq"))
    end

    agent_nodes = NodeObject.find("roles:nova-multi-compute-kvm") +
      NodeObject.find("roles:nova-multi-compute-qemu") +
      NodeObject.find("roles:nova-multi-compute-xen") +
      NodeObject.find("roles:nova-multi-compute-esxi")

    server_nodes = NodeObject.find("roles:nova-multi-controller")

    base["deployment"]["heat"]["elements"] = {
        "heat-server" =>  server_nodes.map { |x| x.name }
    } unless agent_nodes.nil? or server_nodes.nil?

    base["attributes"]["heat"]["keystone_service_password"] = '%012d' % rand(1e12)

    @logger.debug("Heat create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Heat apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    net_svc = NetworkService.new @logger
    tnodes = role.override_attributes["heat"]["elements"]["heat-server"]
    tnodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end unless tnodes.nil?

    @logger.debug("Heat apply_role_pre_chef_call: leaving")
  end

end

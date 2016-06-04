#
# Cookbook Name:: hawk
# Recipe:: webui
#
# Copyright 2014, SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

bash "probe_watchdog" do
  user "root"
  cwd "/"
  code "modprobe softdog"
end

template "/etc/modules-load.d/softdog.conf" do
  source "softdog.conf"
  owner "root"
  group "root"
  mode 0644
end

case node["platform_family"]
when "suse"
  include_recipe "zypper"

  zypper_repository node["hawk"]["zypper"]["alias"] do
    uri node["hawk"]["zypper"]["repo"]
    key node["hawk"]["zypper"]["key"]
    title node["hawk"]["zypper"]["title"]

    action [:add, :refresh]

    only_if do
      node["hawk"]["zypper"]["enabled"]
    end
  end
end

node["hawk"]["webui"]["packages"].each do |name|
  package name do
    action :install
  end
end

node["hawk"]["webui"]["targets"].each do |name|
  bash "hawk_make_#{name.gsub("/", "_")}" do
    user "root"
    cwd "/vagrant"

    code <<-EOH
      make WITHIN_VAGRANT=1 WWW_BASE=/vagrant #{name}
    EOH
  end
end

bash "hawk_init" do
  user "root"
  cwd "/vagrant"

  code node["hawk"]["webui"]["init_command"]

  only_if do
    Mixlib::ShellOut.new(
      node["hawk"]["webui"]["init_check"]
    ).run_command.error?
  end
end

bash "increase_numslots_ocfs2" do
  user "root"

  code <<-EOH
if [ "$(tunefs.ocfs2 -Q "%N" /dev/sdb2)" != "4" ]; then
  crm -w resource stop c-clusterfs
  tunefs.ocfs2 -N 4 /dev/sdb2
  crm -w resource start c-clusterfs
fi
EOH
end


group "haclient" do
  members %w(vagrant)
  append true

  action :manage
end

template node["hawk"]["webui"]["haproxy_cfg"] do
  source "haproxy.cfg.erb"
  owner "root"
  group "root"
  mode 0644

  variables(
    node["hawk"]["webui"]
  )

  not_if do
    node["hawk"]["webui"]["haproxy_cfg"].empty?
  end
end

template node["hawk"]["webui"]["apache_index"] do
  source "index.html.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
    :hostname => node[:hostname]
  )
end

bash "apache_port" do
  user "root"
  cwd "/etc/apache2"

  code node["hawk"]["webui"]["apache_port"]
end


template node["hawk"]["webui"]["initial_cib"] do
  source "crm-initial.conf.erb"
  owner "root"
  group "root"
  mode 0600
end

execute "crm initial configuration" do
  user "root"
  command "crm configure load update #{node["hawk"]["webui"]["initial_cib"]}"
end

template "/etc/systemd/system/hawk-development.service" do
   source "systemd.service.erb"
   owner "root"
   group "root"
   mode 0644
end

file '/home/vagrant/.profile' do
  content <<-EOF
    test -z "$PROFILEREAD" && . /etc/profile || true
    export PATH=/vagrant/hawk/bin:$PATH
  EOF
end

service "hawk-development" do
  action [:enable, :start]
end

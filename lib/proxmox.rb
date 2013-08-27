require "proxmox/version"
require 'rest_client'
require 'json'

module Proxmox
  class Proxmox
    attr_reader :status

    def initialize(pve_cluster, node, username, password, realm)
      @pve_cluster = pve_cluster
      @node = node
      @username = username
      @password = password
      @realm = realm
      @status = "error"
      @site = RestClient::Resource.new(@pve_cluster)
      @auth_params ||= begin
        ticket = nil
        csrf_prevention_token = nil
        post_param = { :username=>@username, :realm=>@realm, :password=>@password }
        @site['access/ticket'].post post_param do |response, request, result, &block|
          if response.code == 200
            data = JSON.parse(response.body)
            ticket = data['data']['ticket']
            csrf_prevention_token = data['data']['CSRFPreventionToken']
            if !ticket.nil?
              token = 'PVEAuthCookie=' + ticket.gsub!(/:/,'%3A').gsub!(/=/,'%3D')
            end
            @status = "connected"
            {
              :CSRFPreventionToken => csrf_prevention_token,
              :cookie => token
            }
          elsif response.code == 200
            @status = "error"
          end
        end
      end
    end

    def openvz_get
      @site["nodes/#{@node}/openvz"].get @auth_params do |response, request, result, &block|
        ve_list = Hash.new
        JSON.parse(response.body)['data'].each do |ve|
          ve_list[ve['vmid']] = ve
        end
        ve_list
      end
    end

    def openvz_post(ostemplate, vmid)
      config = Array.new
      config.push "vmid=#{vmid}"
      config.push "ostemplate=local%3Avztmpl%2F#{ostemplate}.tar.gz"
      vm_definition = config.join '&'

      @site["nodes/#{@node}/openvz"].post "#{vm_definition}", @auth_params do |response, request, result, &block|
        if (response.code == 200) then
          result = "OK"
        else
          result = "NOK: error code = " + response.code.to_s
        end
        JSON.parse(response.body)['data']
      end
    end

    def task_status(upid)
      @site["nodes/#{@node}/task/#{upid}/status"].get @auth_params do |response, request, result, &block|
        exitstatus = JSON.parse(response.body)['data']['exitstatus']
        status = JSON.parse(response.body)['data']['status']
        "#{exitstatus}:#{status}"
      end
    end

    def templates
      @site["nodes/#{@node}/storage/local/content"].get @auth_params do |response, request, result, &block|
        template_list = Hash.new
        JSON.parse(response.body)['data'].each do |ve|
          name = ve['volid'].gsub(/^local:vztmpl\/(.*).tar.gz$/, '\1')
          template_list[name] = ve
        end
        template_list
      end
    end
  end
end

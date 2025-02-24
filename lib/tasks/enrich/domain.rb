module Intrigue
module Task
module Enrich
class Domain < Intrigue::Task::BaseTask

  include Intrigue::Task::Dns

  def self.metadata
    {
      :name => "enrich/domain",
      :pretty_name => "Enrich Domain",
      :authors => ["jcran"],
      :description => "Fills in details for a Domain",
      :references => [],
      :allowed_types => ["Domain"],
      :type => "enrichment",
      :passive => true,
      :example_entities => [
        {"type" => "Domain", "details" => {"name" => "intrigue.io"}}],
      :allowed_options => [],
      :created_types => []
    }
  end

  def run

    lookup_name = _get_entity_name

    # Do a lookup, skip if we already have it (TLD case)
    unless _get_entity_detail("resolutions")

      results = resolve(lookup_name)
      #_create_aliases results

      resolutions = collect_resolutions(results)
      _set_entity_detail("resolutions", resolutions )
      resolutions.each do |r|
        # create unscoped domains for all CNAMEs
        if r["response_type"] == "CNAME"
          check_and_create_unscoped_domain r["response_data"]
        end
      end

      # grab any / all SOA record
      _log "Grabbing SOA"
      soa_details = collect_soa_details(lookup_name)
      _set_entity_detail("soa_record", soa_details)
      check_and_create_unscoped_domain(soa_details["primary_name_server"]) if soa_details

      # grab whois info & all nameservers
      if soa_details
        out = whois(lookup_name)
        if out
          _set_entity_detail("whois_full_text", out["whois_full_text"])
          _set_entity_detail("nameservers", out["nameservers"])
          _set_entity_detail("contacts", out["contacts"])

          # create domains from each of the nameservers
          if out["nameservers"]
            out["nameservers"].each do |n|
              check_and_create_unscoped_domain(n)
            end
          end
        end
      end

      # grab any / all MX records (useful to see who accepts mail)
      _log "Grabbing MX"
      mx_records = collect_mx_records(lookup_name)
      _set_entity_detail("mx_records", mx_records)
      mx_records.each{|mx| check_and_create_unscoped_domain(mx["host"]) }

      # collect TXT records (useful for random things)
      _set_entity_detail("txt_records", collect_txt_records(lookup_name))
      # TODO ... parse these into domains too

      # grab any / all SPF records (useful to see who accepts mail)
      spf_details = collect_spf_details(lookup_name)
      _set_entity_detail("spf_record", spf_details)
      spf_details.each do |record|
        record.split(" ").each do |spf|
          next unless spf =~ /^include:/
          domain_name = spf.split("include:").last
          _log "Found Associated SPF Domain: #{domain_name}"
          check_and_create_unscoped_domain(domain_name)
        end
      end
    end

  end

  def _create_aliases(results)
    ####
    ### Create aliased entities
    ####
    results.each do |result|
      next if @entity.name == result["name"]
      _log "Creating entity for... #{result}"
      if "#{result["name"]}".is_ip_address?
        _create_entity("IpAddress", { "name" => result["name"] }, @entity)
      else
        _create_entity("Domain", { "name" => result["name"] }, @entity)
      end
    end
  end

end
end
end
end
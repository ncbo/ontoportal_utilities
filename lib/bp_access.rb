require_relative 'config'

module BPAccess

  def self.bp_ontologies(acronyms = [])
    params = { no_links: true, no_context: true }
    ex_msg = "Unable to query BioPortal #{Global.config.bp_ontologies_endpoint} endpoint on #{Global.config.bp_base_rest_url}"

    begin
      response_raw = RestClient.get(Global.config.bp_base_rest_url + Global.config.bp_ontologies_endpoint, self.bp_api_headers(params))
      raise StandardError, "#{ex_msg}. Response code: #{response_raw.code}." unless response_raw.code == RESPONSE_OK
    rescue StandardError => e
      e.message = "#{ex_msg}. Exception: #{e.message}"
      raise e
    end
    response = MultiJson.load(response_raw)
    bp_ontologies = {}
    response.each { |ont| bp_ontologies[ont['acronym']] = ont if acronyms.empty? || acronyms.include?(ont['acronym']) }
    not_found = acronyms - bp_ontologies.keys
    not_found.each { |acr| bp_ontologies[acr] = { 'error' => "Ontology #{acr} not found on #{Global.config.bp_base_rest_url}" } }
    bp_ontologies
  end

  def self.bp_latest_submission(base_rest_url, ontology_acronym)
    bp_latest = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, submission: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'all' }
    endpoint_url = base_rest_url + Global.config.bp_latest_submission_endpoint  % { ontology_acronym: ontology_acronym }

    begin
      response_raw = RestClient.get(endpoint_url, self.bp_api_headers(params))
      raise StandardError, "Unable to query BioPortal #{endpoint_url} endpoint. Response code: #{response_raw.code}." unless response_raw.code == RESPONSE_OK

      response = MultiJson.load(response_raw)
      bp_latest[:submission_id] = response['submissionId'].to_i
      bp_latest[:submission] = response
    rescue RestClient::NotFound
      bp_latest[:error] = "No submissions found for ontology #{ontology_acronym} on server #{base_rest_url}"
    rescue RestClient::Forbidden
      bp_latest[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{Global.config.bp_api_key}"
    rescue RestClient::Exceptions::ReadTimeout => e
      e.message = "#{e.message}: #{endpoint_url}"
      raise e
    end
    bp_latest
  end

  def self.bp_ontology_classes(base_rest_url, ontology_acronym, how_many = DEF_TEST_NUM_CLASSES_PER_ONTOLOGY)
    bp_classes = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, total_count: 0, classes: {}, error: '' }
    params = { no_links: true, no_context: true, pagesize: how_many, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym }

    begin
      response_raw = RestClient.get(endpoint_url, self.bp_api_headers(params))
      raise StandardError, "Unable to query BioPortal #{endpoint_url} endpoint. Response code: #{response_raw.code}." unless response_raw.code == RESPONSE_OK

      response = MultiJson.load(response_raw)

      if response['collection']&.is_a?(Array) && !response['collection'].empty?
        bp_classes[:submission_id] = self.id_or_acronym_from_uri(response['collection'][0]['submission']).to_i
        bp_classes[:total_count] = response['totalCount'].to_i
        response['collection'].each {|cls| bp_classes[:classes][cls['@id']] = cls}
      end
    rescue RestClient::NotFound
      bp_classes[:error] = "No submissions found for ontology #{ontology_acronym} on server #{base_rest_url}"
    rescue RestClient::Forbidden
      bp_classes[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{Global.config.bp_api_key}"
    rescue RestClient::Exceptions::ReadTimeout => e
      e.message = "#{e.message}: #{endpoint_url}"
      raise e
    end
    bp_classes
  end

  def self.bp_ontology_class(base_rest_url, ontology_acronym, class_id)
    bp_class = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, class: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym } + '/' + CGI.escape(class_id)

    begin
      response_raw = RestClient.get(endpoint_url, self.bp_api_headers(params))
      raise StandardError, "Unable to query BioPortal #{Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym }} endpoint. Response code: #{response_raw.code}." unless response_raw.code == RESPONSE_OK

      response = MultiJson.load(response_raw)
      bp_class[:submission_id] = self.id_or_acronym_from_uri(response['submission']).to_i
      bp_class[:class] = response
    rescue RestClient::NotFound
      bp_class[:error] = "Class #{class_id} not found for ontology #{ontology_acronym} on server #{base_rest_url}\n#{endpoint_url}"
    end
    bp_class
  end

  def self.find_class_in_bioportal(class_id)
    params = { q: class_id, require_exact_match: true, no_context: true }
    response_raw = RestClient.get(Global.config.bp_base_rest_url + Global.config.bp_search_endpoint, self.bp_api_headers(params))
    raise StandardError, "Unable to query BioPortal #{Global.config.bp_search_endpoint} endpoint. Response code: #{response_raw.code}." unless response_raw.code == RESPONSE_OK

    response = MultiJson.load(response_raw)
    response['totalCount'].to_i > 0 ? response['collection'][0] : false
  end

  def self.bp_api_headers(params)
    { Authorization: "apikey token=#{Global.config.bp_api_key}", params: params }
  end

  def self.id_or_acronym_from_uri(uri)
    uri.to_s.split('/')[-1]
  end

end
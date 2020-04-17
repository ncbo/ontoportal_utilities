require_relative 'config'

module BPAccess

  RESPONSE_OK = 200

  def self.bp_ontologies(base_rest_url, acronyms = [])
    bp_ontologies = {}
    params = { no_links: true, no_context: true }
    endpoint_url = base_rest_url + Global.config.bp_ontologies_endpoint
    response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
    raise_std_error_message(response_raw, endpoint_url)
    response = MultiJson.load(response_raw)
    response.each { |ont| bp_ontologies[ont['acronym']] = ont if acronyms.empty? || acronyms.include?(ont['acronym']) }
    not_found = acronyms - bp_ontologies.keys

    not_found.each do |acr|
      latest = bp_latest_submission(base_rest_url, acr)
      bp_ontologies[acr] = { 'error' => latest[:error] || "Ontology #{acr} NOT FOUND on #{base_rest_url}" }
    end
    bp_ontologies
  end

  def self.bp_latest_submission(base_rest_url, ontology_acronym)
    bp_latest = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, submission: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'all' }
    endpoint_url = base_rest_url + Global.config.bp_latest_submission_endpoint  % { ontology_acronym: ontology_acronym }

    begin
      response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)
      raise RestClient::NotFound if response.empty?

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

  def self.bp_ontology_roots(base_rest_url, ontology_acronym)
    bp_roots = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, classes: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_roots_endpoint  % { ontology_acronym: ontology_acronym }

    begin
      response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)

      if response.empty?
        bp_roots[:error] = "No root classes found for ontology #{ontology_acronym} on server #{base_rest_url}"
      else
        bp_roots[:submission_id] = id_or_acronym_from_uri(response[0]['submission']).to_i unless response.empty?
        response.each { |cls| bp_roots[:classes][cls['@id']] = cls }
      end
    rescue RestClient::NotFound
      bp_roots[:error] = "No submissions found for ontology #{ontology_acronym} on server #{base_rest_url}"
    rescue RestClient::Forbidden
      bp_roots[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{Global.config.bp_api_key}"
    rescue RestClient::Exceptions::ReadTimeout => e
      e.message = "#{e.message}: #{endpoint_url}"
      raise e
    end
    bp_roots
  end

  def self.bp_ontology_classes(base_rest_url, ontology_acronym, how_many)
    bp_classes = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, total_count: 0, classes: {}, error: '' }
    params = { no_links: true, no_context: true, pagesize: how_many, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym }

    begin
      response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)

      if response['collection']&.is_a?(Array) && !response['collection'].empty?
        bp_classes[:submission_id] = id_or_acronym_from_uri(response['collection'][0]['submission']).to_i
        bp_classes[:total_count] = response['totalCount'].to_i
        response['collection'].each { |cls| bp_classes[:classes][cls['@id']] = cls }
      else
        bp_classes[:error] = "No classes found for ontology #{ontology_acronym} on server #{base_rest_url}"
      end
    rescue RestClient::NotFound
      bp_classes[:error] = "No submissions found for ontology #{ontology_acronym} on server #{base_rest_url}"
    rescue RestClient::Forbidden
      bp_classes[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{Global.config.bp_api_key}"
    rescue RestClient::InternalServerError
      bp_classes[:error] = "The classes endpoint on #{base_rest_url} returned an Internal Server Error response for ontology #{ontology_acronym}. Endpoint URL: #{endpoint_url}"
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
      response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)
      bp_class[:submission_id] = id_or_acronym_from_uri(response['submission']).to_i
      bp_class[:class] = response
    rescue RestClient::NotFound
      bp_class[:error] = "Class #{class_id} NOT FOUND for ontology #{ontology_acronym} on server #{base_rest_url}\n#{endpoint_url}"
    rescue RestClient::Forbidden
      bp_classes[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{Global.config.bp_api_key}"
    rescue RestClient::Exceptions::ReadTimeout => e
      e.message = "#{e.message}: #{endpoint_url}"
      raise e
    end
    bp_class
  end

  def self.find_class_in_bioportal(base_rest_url, class_id)
    params = { q: class_id, require_exact_match: true, no_context: true }
    endpoint_url = base_rest_url + Global.config.bp_search_endpoint
    response_raw = RestClient.get(endpoint_url, bp_api_headers(params))
    raise_std_error_message(response_raw, endpoint_url)
    response = MultiJson.load(response_raw)
    response['totalCount'].to_i > 0 ? response['collection'][0] : false
  end

  def self.bp_api_headers(params)
    { Authorization: "apikey token=#{Global.config.bp_api_key}", params: params }
  end

  def self.raise_std_error_message(response, endpoint)
    raise StandardError, "Unable to query BioPortal #{endpoint} endpoint. Response code: #{response.code}." unless response.code == RESPONSE_OK
  end

  def self.id_or_acronym_from_uri(uri)
    uri.to_s.split('/')[-1]
  end

end
require_relative 'config'

module BPAccess

  RESPONSE_OK = 200

  def self.bp_ontologies(base_rest_url, acronyms = [])
    bp_ontologies = {}
    params = { no_links: true, no_context: true }
    endpoint_url = base_rest_url + Global.config.bp_ontologies_endpoint

    handle_bp_request(bp_ontologies, '', endpoint_url, '') do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)
      response.each { |ont| bp_ontologies[ont['acronym']] = ont if acronyms.empty? || acronyms.include?(ont['acronym']) }
      not_found = acronyms - bp_ontologies.keys

      not_found.each do |acr|
        latest = bp_latest_submission(base_rest_url, acr)
        bp_ontologies[acr] = { 'error' => latest[:error] || "Ontology #{acr} NOT FOUND on #{base_rest_url}" }
      end
    end
    bp_ontologies
  end

  def self.bp_latest_submission(base_rest_url, ontology_acronym)
    bp_latest = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, submission: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'all' }
    endpoint_url = base_rest_url + Global.config.bp_latest_submission_endpoint  % { ontology_acronym: ontology_acronym }

    handle_bp_request(bp_latest, ontology_acronym, endpoint_url, 'Submissions NOT FOUND') do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)
      raise RestClient::NotFound if response.empty?

      bp_latest[:submission_id] = response['submissionId'].to_i
      bp_latest[:submission] = response
    end
    bp_latest
  end

  def self.bp_ontology_metrics(base_rest_url, ontology_acronym)
    bp_metrics = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, metrics: {}, error: '' }
    params = { no_links: true, no_context: true }
    endpoint_url = base_rest_url + Global.config.bp_ontology_metrics_endpoint  % { ontology_acronym: ontology_acronym }

    handle_bp_request(bp_metrics, ontology_acronym, endpoint_url, 'Ontology (or Submission) NOT FOUND') do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)

      if response.empty?
        bp_metrics[:error] = "No metrics found for ontology #{ontology_acronym} on server #{base_rest_url}"
      else
        bp_metrics[:submission_id] = id_or_acronym_from_uri(response['submission'][0]).to_i if response['submission'] && !response['submission'].empty?
        bp_metrics[:metrics] = response
      end
    end
    bp_metrics
  end

  def self.bp_ontology_roots(base_rest_url, ontology_acronym)
    bp_roots = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, classes: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_roots_endpoint  % { ontology_acronym: ontology_acronym }

    handle_bp_request(bp_roots, ontology_acronym, endpoint_url, 'Submissions NOT FOUND') do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)

      if response.empty?
        bp_roots[:error] = "No root classes found for ontology #{ontology_acronym} on server #{base_rest_url}"
      else
        bp_roots[:submission_id] = id_or_acronym_from_uri(response[0]['submission']).to_i
        response.each { |cls| bp_roots[:classes][cls['@id']] = cls }
      end
    end
    bp_roots
  end

  def self.bp_ontology_classes(base_rest_url, ontology_acronym, how_many)
    bp_classes = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, total_count: 0, classes: {}, error: '' }
    params = { no_links: true, no_context: true, pagesize: how_many, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym }

    handle_bp_request(bp_classes, ontology_acronym, endpoint_url, 'Submissions NOT FOUND') do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)

      if response['collection']&.is_a?(Array) && !response['collection'].empty?
        bp_classes[:submission_id] = id_or_acronym_from_uri(response['collection'][0]['submission']).to_i
        bp_classes[:total_count] = response['totalCount'].to_i
        response['collection'].each { |cls| bp_classes[:classes][cls['@id']] = cls }
      else
        bp_classes[:error] = "Classes NOT FOUND for ontology #{ontology_acronym} on server #{base_rest_url}"
      end
    end
    bp_classes
  end

  def self.bp_ontology_class(base_rest_url, ontology_acronym, class_id)
    bp_class = { server: base_rest_url, ont: ontology_acronym, submission_id: -1, class: {}, error: '' }
    params = { no_links: true, no_context: true, display: 'prefLabel,synonym,definition,properties,submission' }
    endpoint_url = base_rest_url + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym } + '/' + CGI.escape(class_id)

    handle_bp_request(bp_class, ontology_acronym, endpoint_url, "Class #{class_id} NOT FOUND") do
      response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
      raise_std_error_message(response_raw, endpoint_url)
      response = MultiJson.load(response_raw)
      bp_class[:submission_id] = id_or_acronym_from_uri(response['submission']).to_i
      bp_class[:class] = response
    end
    bp_class
  end

  def self.find_class_in_bioportal(base_rest_url, class_id)
    params = { q: class_id, require_exact_match: true, no_context: true }
    endpoint_url = base_rest_url + Global.config.bp_search_endpoint
    response_raw = RestClient.get(endpoint_url, bp_api_headers(base_rest_url, params))
    raise_std_error_message(response_raw, endpoint_url)
    response = MultiJson.load(response_raw)
    response['totalCount'].to_i > 0 ? response['collection'][0] : false
  end

  def self.handle_bp_request(obj, ontology_acronym, endpoint_url, def_not_found_msg)
    uri = URI.parse(endpoint_url)
    base_rest_url = "#{uri.scheme}://#{uri.host}"
    api_key = Global.config.servers_to_compare[base_rest_url]

    begin
      yield
    rescue RestClient::NotFound => e
      handle_not_found(obj, ontology_acronym, base_rest_url, e, def_not_found_msg)
    rescue RestClient::Forbidden
    rescue RestClient::Unauthorized
      obj[:error] = "Access denied to ontology #{ontology_acronym} on server #{base_rest_url} using API Key #{api_key}"
    rescue RestClient::InternalServerError => e
      e.message = "#{e.message}: #{endpoint_url}"
      obj[:error] = e.message
    rescue RestClient::Exceptions::ReadTimeout,
           RestClient::Exceptions::OpenTimeout => e
      e.message = "#{e.message}: #{endpoint_url}"
      raise e
    end
  end

  def self.handle_not_found(obj, ontology_acronym, base_rest_url, exception, def_msg)
    obj[:error] = "#{def_msg} (#{ontology_acronym} on server #{base_rest_url})."
    return unless exception.response

    resp = JSON.parse(exception.response.body)
    return unless resp["errors"]

    resp["errors"] = [resp["errors"]] unless resp["errors"].is_a?(Array)
    obj[:error] = "#{resp["errors"].join(", ").reverse.sub('.', '').reverse} (#{ontology_acronym} on server #{base_rest_url})."
  end

  def self.bp_api_headers(base_rest_url, params)
    api_key = Global.config.servers_to_compare[base_rest_url]
    { Authorization: "apikey token=#{api_key}", params: params }
  end

  def self.raise_std_error_message(response, endpoint)
    raise StandardError, "Unable to query BioPortal #{endpoint} endpoint. Response code: #{response.code}." unless response.code == RESPONSE_OK
  end

  def self.id_or_acronym_from_uri(uri)
    uri.to_s.split('/')[-1]
  end

end
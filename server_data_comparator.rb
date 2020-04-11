require 'multi_json'
require 'pry'
require 'rest-client'
require 'optparse'
require 'benchmark'
require 'pp'
require_relative 'lib/config'

RESPONSE_OK = 200
TEST_NUM_ONTOLOGIES = 10
TEST_NUM_CLASSES_PER_ONTOLOGY = 30
@options = nil
@logger = nil

def main
  @options = parse_options
  dirname = File.dirname(@options[:log_file])
  FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
  @logger = Logger.new(@options[:log_file])
  puts "Logging output to #{@options[:log_file]}\n\n"
  @options[:ontologies] = random_bp_ontologies if @options[:ontologies].empty?
  puts_and_log("Testing ontologies #{@options[:ontologies]}\n\n")

  @options[:ontologies].each do |ontology_acronym|
    class_artifacts = ontology_class_artifacts(ontology_acronym)

    if class_artifacts[:error].empty?
      compare_artifacts('Total Class Counts', ontology_acronym, class_artifacts[:total_counts])
      compare_artifacts('Preferred Labels', ontology_acronym, class_artifacts[:pref_labels])
      compare_artifacts('Synonyms', ontology_acronym, class_artifacts[:synonyms])
      compare_artifacts('Definitions', ontology_acronym, class_artifacts[:definitions])
    else
      puts_and_log(class_artifacts[:error])
    end
    puts_and_log("\n" << '─' * 120 << "\n\n")
  end
end

def compare_artifacts(artifact_name, ontology_acronym, artifact_hash)
  comp_servers = Global.config.servers_to_compare.permutation(2).to_a.each { |a| a.sort! }.uniq

  comp_servers.each do |duo|
    matched = true
    set1 = artifact_hash[duo[0]]
    set2 = artifact_hash[duo[1]]

    if set1.is_a?(Integer)
      if set1 != set2
        matched = false
        puts_and_log "#{artifact_name} for #{ontology_acronym} do not match on servers #{duo[0]} and #{duo[1]}:"
        puts_and_log(JSON.pretty_generate(artifact_hash))
      end
    elsif set1.is_a?(Hash) && !set1.empty?
      if set1.values[0].is_a?(String)
        if set1 != set2
          matched = false
          diffs = set1.merge(set2) { |_k, v1, v2| v1 == v2 ? nil : :different }.compact
          puts_and_log("#{artifact_name} for #{ontology_acronym} differ on servers #{duo[0]} and #{duo[1]}. Differences:")
          puts_and_log(JSON.pretty_generate(diffs))
        end
      elsif set1.values[0].is_a?(Array)
        set1.each do |id1, coll1|
          if set2[id1]
            diffs = coll1 - set2[id1] | set2[id1] - coll1

            unless diffs.empty?
              matched = false
              puts_and_log("#{artifact_name} for #{ontology_acronym}, term #{id1} differ on servers #{duo[0]} and #{duo[1]}. Differences:")
              puts_and_log(JSON.pretty_generate(diffs))
            end
          else
            matched = false
            puts_and_log("#{artifact_name} found for #{ontology_acronym}, term #{id1} on server #{duo[0]}, but none on server #{duo[1]}.")
          end
        end
      end
    end
    puts_and_log "#{artifact_name} for #{ontology_acronym} match on servers #{duo[0]} and #{duo[1]}." if matched
  end
end

def random_bp_ontologies
  bp_ont = bp_ontologies
  test_indicies = random_numbers(TEST_NUM_ONTOLOGIES, 0, bp_ont.length - 1)
  test_indicies.map { |ind| bp_ont.keys[ind] }
end

def ontology_class_artifacts(ontology_acronym)
  total_counts = {}
  pref_labels = {}
  synonyms = {}
  definitions = {}

  Global.config.servers_to_compare.each do |server|
    bp_classes = nil

    time = Benchmark.realtime do
      bp_classes = bp_ontology_classes(server, ontology_acronym, TEST_NUM_CLASSES_PER_ONTOLOGY)
    end

    if bp_classes[:error].empty?
      puts_and_log("Retrieved #{bp_classes[:classes].keys.count} classes for ontology #{ontology_acronym} from #{server} in #{time.round(2)} seconds.")

      total_counts[server] = bp_classes[:total_count]
      pref_labels[server] = {}
      synonyms[server] = {}
      definitions[server] = {}

      bp_classes[:classes].each do |id, cls|
        pref_labels[server][id] = cls['prefLabel']
        synonyms[server][id] = cls['synonym'].sort
        definitions[server][id] = cls['definition'].sort
      end
    else
      return { error: bp_classes[:error] }
    end
  end
  { total_counts: total_counts, pref_labels: pref_labels, synonyms: synonyms, definitions: definitions, error: '' }
end

def random_numbers(how_many, min = 0, max = 20)
  (min..max).to_a.sort { rand - 0.5 }[0..how_many - 1]
end

def get_acronym_from_id(id)
  id.to_s.split('/')[-1]
end

def bp_ontologies
  response_raw = RestClient.get(Global.config.bp_base_rest_url + Global.config.bp_ontologies_endpoint, {Authorization: "apikey token=#{Global.config.bp_api_key}", params: {no_links: true, no_context: true}})
  bp_ontologies = {}

  if response_raw.code === RESPONSE_OK
    response = MultiJson.load(response_raw)
    response.each {|ont| bp_ontologies[ont['acronym']] = ont['name']}
  else
    raise Exception, "Unable to query BioPortal #{Global.config.bp_ontologies_endpoint} endpoint. Response code: #{response_raw.code}."
  end

  bp_ontologies
end

def bp_ontology_classes(base_rest_url, ontology_acronym, how_many = 50)
  bp_classes = { server: base_rest_url, ont: ontology_acronym, total_count: 0, classes: {}, error: '' }
  params = { no_links: true, no_context: true, pagesize: how_many, display: 'prefLabel,synonym,definition,properties' }

  begin
    response_raw = RestClient.get(base_rest_url + Global.config.bp_classes_endpoint  % {ontology_acronym: ontology_acronym}, {Authorization: "apikey token=#{Global.config.bp_api_key}", params: params})

    if response_raw.code == RESPONSE_OK
      response = MultiJson.load(response_raw)
      if response['collection'] && response['collection'].is_a?(Array) && !response['collection'].empty?
        response['collection'].each {|cls| bp_classes[:classes][cls['@id']] = cls}
        bp_classes[:total_count] = response['totalCount'].to_i
      end
    else
      raise Exception, "Unable to query BioPortal #{Global.config.bp_classes_endpoint  % {ontology_acronym: ontology_acronym}} endpoint. Response code: #{response_raw.code}."
    end
  rescue RestClient::NotFound
    bp_classes[:error] = "Ontology #{ontology_acronym} not found on server #{base_rest_url}"
  end
  bp_classes
end

def find_class_in_bioportal(class_id)
  response_raw = RestClient.get(Global.config.bp_base_rest_url + Global.config.bp_search_endpoint, {Authorization: "apikey token=#{Global.config.bp_api_key}", params: {q: class_id, require_exact_match: true, no_context: true}})
  term = false

  if response_raw.code === RESPONSE_OK
    response = MultiJson.load(response_raw)

    if response['totalCount'] > 0
      term = response['collection'][0]
    end
  else
    raise Exception, "Unable to query BioPortal #{Global.config.bp_search_endpoint} endpoint. Response code: #{response_raw.code}."
  end
  term
end

def parse_options
  options = { ontologies: [] }
  script_name = 'server-data-comparator'

  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename(__FILE__)} [options]"

    opts.on('-l', '--log PATH_TO_LOG_FILE', "Optional path to the log file (default: #{Global.config.default_log_file_path % {script_name: script_name}})") { |v|
      options[:log_file] = v
    }

    opts.on('-o', '--ontologies ACR1,ACR2,ACR3', "Optional comma-separated list of ontologies to test (default: #{TEST_NUM_ONTOLOGIES} random ontologies)") do |acronyms|
      options[:ontologies] = acronyms.split(",").map {|o| o.strip}
    end

    opts.on('-h', '--help', 'Display this screen') do
      puts opts
      exit
    end
  end
  opt_parser.parse!
  options[:log_file] ||= Global.config.default_log_file_path % {script_name: script_name}
  options
end

def puts_and_log(msg, type='info')
  puts msg
  case type
  when 'warn'
    @logger.warn(msg)
  when 'error'
    @logger.error(msg)
  else
    @logger.info(msg)
  end
end

main

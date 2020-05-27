require 'multi_json'
require 'pry'
require 'rest-client'
require 'optparse'
require 'colorize'
require_relative 'lib/config'
require_relative 'lib/bp_access'

DEF_TEST_NUM_ONTOLOGIES = 10
DEF_TEST_NUM_CLASSES_PER_ONTOLOGY = 500
@options = nil
@logger = nil

def main
  @options = parse_options
  dirname = File.dirname(@options[:log_file])
  FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
  @logger = Logger.new(@options[:log_file])
  puts "Logging output to #{@options[:log_file]}\n\n"
  ont_to_test = ontologies_to_test
  puts_and_log("Testing ontologies #{ont_to_test.keys.to_s.yellow}")
  puts_and_log("Proceeding with ALL checks even if Submission IDs are mismatched") if @options[:ignore_ids]
  puts_and_log("\n")

  ont_to_test.each do |ontology_acronym, ont|
    if ont['error']
      puts_and_log("#{ont['error']}\n\n")
      puts_and_log(rec_separator)
      next
    end
    metadata_artifacts = ontology_metadata_artifacts(ontology_acronym)

    if metadata_artifacts[:errors].empty?
      puts_and_log("\n")
    else
      puts_and_log("#{metadata_artifacts[:errors].values.join("\n").red}\n\n")
      puts_and_log(rec_separator)
      next
    end
    latest_sub_endpoint_url = lambda { |server, _| server + Global.config.bp_latest_submission_endpoint  % { ontology_acronym: ontology_acronym } }
    classes_endpoint_url = lambda { |server, _| server + Global.config.bp_classes_endpoint  % { ontology_acronym: ontology_acronym } }
    class_endpoint_url = lambda { |server, class_id| classes_endpoint_url.call(server, '') + '/' + CGI.escape(class_id) }
    puts_and_log(banner(ontology_acronym, 'Comparing Submission IDs'))
    err_condition = compare_artifacts('Submission IDs', ontology_acronym, metadata_artifacts[:submission_ids], latest_sub_endpoint_url)

    if !err_condition || @options[:ignore_ids]
      # Metadata
      puts_and_log(banner(ontology_acronym, 'Comparing Ontology Metadata'))
      compare_artifacts('Metadata', ontology_acronym, metadata_artifacts[:metadata], latest_sub_endpoint_url)

      # Metrics
      metrics_endpoint_url = lambda { |server, _| server + Global.config.bp_ontology_metrics_endpoint  % { ontology_acronym: ontology_acronym } }
      puts_and_log(banner(ontology_acronym, 'Comparing Ontology Metrics'))
      metrics_artifacts = ontology_metrics_artifacts(ontology_acronym)

      if metrics_artifacts[:errors].empty?
        puts_and_log("\n")
        compare_artifacts('Metrics', ontology_acronym, metrics_artifacts[:metrics], metrics_endpoint_url)
      else
        puts_and_log("#{metrics_artifacts[:errors].values.join("\n").red}\n\n")
      end

      # Root Class IDs
      puts_and_log(banner(ontology_acronym, 'Comparing Root Class IDs'))
      root_artifacts = ontology_class_artifacts(ontology_acronym, true)

      if root_artifacts[:errors].empty?
        roots_endpoint_url = lambda { |server, _| server + Global.config.bp_classes_roots_endpoint  % { ontology_acronym: ontology_acronym } }
        compare_artifacts('Root Class IDs', ontology_acronym, root_artifacts[:ids], roots_endpoint_url)

        # Root Class Artifacts
        puts_and_log(banner(ontology_acronym, 'Comparing Root Class Artifacts'))
        compare_artifacts('Root Class Preferred Labels', ontology_acronym, root_artifacts[:pref_labels], roots_endpoint_url)
        compare_artifacts('Root Class Synonyms', ontology_acronym, root_artifacts[:synonyms], class_endpoint_url)
        compare_artifacts('Root Class Definitions', ontology_acronym, root_artifacts[:definitions], class_endpoint_url)
      else
        puts_and_log("#{root_artifacts[:errors].values.join("\n").red}\n\n")
      end

      # Class Artifacts
      puts_and_log(banner(ontology_acronym, 'Comparing Sample Class Artifacts'))
      class_artifacts = ontology_class_artifacts(ontology_acronym, false)

      unless class_artifacts[:errors].empty?
        puts_and_log("#{class_artifacts[:errors].values.join("\n").red}\n\n")
        puts_and_log(rec_separator)
        next
      end
      compare_artifacts('Total Class Counts', ontology_acronym, class_artifacts[:total_counts], classes_endpoint_url)
      compare_artifacts('Preferred Labels', ontology_acronym, class_artifacts[:pref_labels], classes_endpoint_url)
      compare_artifacts('Synonyms', ontology_acronym, class_artifacts[:synonyms], class_endpoint_url)
      compare_artifacts('Definitions', ontology_acronym, class_artifacts[:definitions], class_endpoint_url)
    end
    puts_and_log(rec_separator)
  end
end

def compare_artifacts(artifact_name, ontology_acronym, artifact_hash, endpoint_url)
  comp_servers = server_permutations
  err_condition = false

  comp_servers.each do |duo|
    matched = true
    set1 = artifact_hash[duo[0]]
    set2 = artifact_hash[duo[1]]

    if set1.is_a?(Integer)
      if set1 != set2
        matched = false
        err_condition = true
        print_diffs(artifact_name, ontology_acronym, duo, nil, artifact_hash, nil)
      end
    elsif set1.is_a?(Array)
      if set1 != set2
        matched = false
        diffs_arr = compare_arrays(set1, set2)
        diffs = { "#{duo[0]}": diffs_arr[0], "#{duo[1]}": diffs_arr[1] }
        print_diffs(artifact_name, ontology_acronym, duo, endpoint_url, diffs, nil)
      end
    elsif set1.is_a?(Hash) && !set1.empty?
      if set1.values[0].is_a?(String) || set1.values[0].is_a?(Integer)
        if set1 != set2
          matched = false
          diffs_arr = compare_string_hashes(set1, set2)
          diffs = { "#{duo[0]}": diffs_arr[0], "#{duo[1]}": diffs_arr[1] }
          print_diffs(artifact_name, ontology_acronym, duo, endpoint_url, diffs, nil)
        end
      elsif set1.values[0].is_a?(Array)
        set1.each do |id1, coll1|
          if set2[id1]
            diffs = coll1 - set2[id1] | set2[id1] - coll1

            unless diffs.empty?
              matched = false
              print_diffs(artifact_name, ontology_acronym, duo, endpoint_url, diffs, id1)
            end
          else
            matched = false
            print_diffs(artifact_name, ontology_acronym, duo, endpoint_url, nil, id1)
          end
        end
      end
    end
    puts_and_log "#{artifact_name} for #{ontology_acronym} match on servers #{duo[0]} and #{duo[1]}\n\n" if matched
  end
  err_condition
end

def print_diffs(artifact_name, ontology_acronym, server_duo, endpoint_url = nil, diffs = nil, id = nil)
  str = "#{artifact_name} for #{ontology_acronym}"
  str << ", term #{id}" if id
  str << " #{'DO NOT match'.red} on servers #{server_duo[0]} and #{server_duo[1]}:"
  puts_and_log(str)

  if endpoint_url
    puts_and_log(endpoint_url.call(server_duo[0], id))
    puts_and_log(endpoint_url.call(server_duo[1], id))
  end

  if diffs
    puts_and_log('Differences:'.red)
    puts_and_log(JSON.pretty_generate(diffs).red << "\n\n")
  end
end

def compare_arrays(a1, a2)
  diff1 = a1 - a2
  diff2 = a2 - a1
  [diff1, diff2]
end

def compare_string_hashes(h1, h2)
  diff1_arr = h1.to_a - h2.to_a
  diff1 = Hash[*diff1_arr.flatten].map { |k, v| [k, v.to_s.gsub('"', "'")] }.to_h
  diff2_arr = h2.to_a - h1.to_a
  diff2 = Hash[*diff2_arr.flatten].map { |k, v| [k, v.to_s.gsub('"', "'")] }.to_h
  [diff1, diff2]
end

def banner(ontology_acronym, title)
  full_title = "#{ontology_acronym}: #{title}"
  len = full_title.length
  sprintf "%-20s  %-#{len}s  %-#{80 - len}s", ('#' * 20).blue, full_title.yellow, ('#' * (80 - len)).blue << "\n\n"
end

def rec_separator
  ('─' * 120).blue << "\n\n"
end

def server_permutations
  Global.config.servers_to_compare.hash.keys.permutation(2).to_a.each { |a| a.sort! }.uniq
end

def random_numbers(how_many, min = 0, max = 20)
  (min..max).to_a.sort { rand - 0.5 }[0..how_many - 1]
end

def ontologies_to_test
  num_ont = number_or_nil(@options[:ontologies].join(','))
  base_rest_url = Global.config.servers_to_compare.hash.keys[0]
  ont_to_test = nil

  if num_ont || @options[:ontologies].empty?
    num_ont ||= DEF_TEST_NUM_ONTOLOGIES
    bp_ont = BPAccess.bp_ontologies(base_rest_url)
    test_indicies = random_numbers(num_ont, 0, bp_ont.length - 1)
    acronyms = test_indicies.map { |ind| bp_ont.keys[ind] }
    ont_to_test = bp_ont.select { |acr, _| acronyms.include?(acr) }
  else
    ont_to_test = BPAccess.bp_ontologies(base_rest_url, @options[:ontologies])
  end
  ont_to_test
end

def ontology_metrics_artifacts(ontology_acronym)
  metrics = {}
  errors = {}

  Global.config.servers_to_compare.hash.each do |server, _|
    bp_metrics = BPAccess.bp_ontology_metrics(server, ontology_acronym)

    unless bp_metrics[:error].empty?
      errors[server] = bp_metrics[:error]
      next
    end
    puts_and_log("Retrieved metrics for ontology #{ontology_acronym} from #{server}")

    # compare only the integer values
    metrics[server] = bp_metrics[:metrics].select { |_, v| v.is_a?(Integer) }
  end
  { metrics: metrics, errors: errors }
end

def ontology_metadata_artifacts(ontology_acronym)
  submission_ids = {}
  metadata = {}
  errors = {}
  server_variations = Global.config.servers_to_compare.hash.keys.dup
  server_variations.dup.each { |server| server_variations << (server.start_with?('http://') ? server.sub('http://', 'https://') : server.sub('https://', 'http://')) }

  Global.config.servers_to_compare.hash.each do |server, _|
    bp_latest = BPAccess.bp_latest_submission(server, ontology_acronym)

    unless bp_latest[:error].empty?
      errors[server] = bp_latest[:error]
      next
    end
    puts_and_log("Retrieved latest submission for ontology #{ontology_acronym} from #{server}")
    submission_ids[server] = bp_latest[:submission_id]

    # convert all values to string for uniform comparison
    metadata[server] = bp_latest[:submission].map { |k, v| [k, v.to_s] }.to_h
    # remove any references to the servers from values for comparing
    metadata[server].each { |_, v| server_variations.each { |server_name| v.gsub!(server_name, '') unless v.frozen? } }
  end
  { submission_ids: submission_ids, metadata: metadata, errors: errors }
end

def ontology_class_artifacts(ontology_acronym, roots = false)
  submission_ids = {}
  total_counts = {}
  ids = {}
  pref_labels = {}
  synonyms = {}
  definitions = {}
  master_classes = nil
  missing_ids = []
  errors = {}

  Global.config.servers_to_compare.hash.keys.each_with_index do |server, row_index|
    bp_classes = nil

    if roots
      bp_classes = BPAccess.bp_ontology_roots(server, ontology_acronym)
    else
      bp_classes = BPAccess.bp_ontology_classes(server, ontology_acronym, @options[:num_classes])
    end

    unless bp_classes[:error].empty?
      errors[server] = bp_classes[:error]
      next
    end
    puts_and_log("Retrieved #{bp_classes[:classes].keys.count}#{roots ? ' root' : ''} classes for ontology #{ontology_acronym} from #{server}")

    unless roots
      if row_index.zero?
        master_classes = bp_classes.dup
      else
        m_keys = master_classes[:classes].keys
        bp_keys = bp_classes[:classes].keys
        missing_ids = m_keys - bp_keys
        non_matching_ids = bp_keys - m_keys
        bp_classes[:classes].reject! { |id, _| non_matching_ids.include?(id) }
      end
    end
    total_counts[server] = bp_classes[:total_count] if bp_classes[:total_count]
    submission_ids[server] = bp_classes[:submission_id]
    ids[server] = []
    pref_labels[server] = {}
    synonyms[server] = {}
    definitions[server] = {}

    bp_classes[:classes].each do |id, cls|
      ids[server] << id
      pref_labels[server][id] = cls['prefLabel']
      synonyms[server][id] = cls['synonym'].map(&:to_s).sort
      definitions[server][id] = cls['definition'].map(&:to_s).sort
    end
  end
  puts_and_log("Processing. Please wait...\n\n") if errors.empty?

  Global.config.servers_to_compare.hash.keys[1..-1].each do |server|
    missing_ids.each do |id|
      bp_class = BPAccess.bp_ontology_class(server, ontology_acronym, id)

      unless bp_class[:error].empty?
        # output error message and don't compare artifacts for a class
        # that resulted in an error on at least one of the servers
        puts_and_log("#{bp_class[:error]}\n\n")
        pref_labels.each { |_, lbl_hash| lbl_hash.reject! { |i, __| i == id } }
        synonyms.each { |_, syn_hash| syn_hash.reject! { |i, __| i == id } }
        definitions.each { |_, def_hash| def_hash.reject! { |i, __| i == id } }
        next
      end
      ids[server] << id
      pref_labels[server][id] = bp_class[:class]['prefLabel']
      synonyms[server][id] = bp_class[:class]['synonym'].map(&:to_s).sort
      definitions[server][id] = bp_class[:class]['definition'].map(&:to_s).sort
    end
  end
  { ids: ids, total_counts: total_counts, submission_ids: submission_ids, pref_labels: pref_labels, synonyms: synonyms, definitions: definitions, errors: errors }
end

def parse_options
  script_name = 'server_data_comparator'
  options = {
      ontologies: [],
      num_classes: DEF_TEST_NUM_CLASSES_PER_ONTOLOGY,
      ignore_ids: false,
      log_file: Global.config.default_log_file_path % { script_name: script_name }
  }

  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{File.basename(__FILE__)} [options]"

    opts.on('-o', "--ont ACR1,ACR2,ACR3 OR NUM", "An optional comma-separated list of ontologies to test (default: #{DEF_TEST_NUM_ONTOLOGIES} random ontologies)\n#{"\s"*37}OR\n#{"\s"*37}An optional number of random ontologies to test") do |acronyms|
      options[:ontologies] = acronyms.split(",").map { |o| o.strip }
    end

    opts.on('-c', '--classes NUM (integer > 0)', "Optional number of classes to test per ontology (default: #{DEF_TEST_NUM_CLASSES_PER_ONTOLOGY})") do |num|
      options[:num_classes] = num.to_i
    end

    opts.on('-i', '--ignore_ids', "Ignore the fact that Submission IDs are different between servers and proceed with ALL checks\n#{"\s"*37}(default: if Submission IDs are different, further checks NOT PERFORMED)") do
      options[:ignore_ids] = true
    end

    opts.on('-l', '--log PATH_TO_LOG_FILE', "Optional path to the log file (default: #{Global.config.default_log_file_path % { script_name: script_name }})") { |path|
      options[:log_file] = path
    }

    opts.on('-h', '--help', 'Display this screen') do
      puts opts
      exit
    end
  end
  opt_parser.parse!
  options[:log_file] ||= :Global.config.default_log_file_path % { script_name: script_name }
  options
end


def puts_and_log(msg, type = 'info')
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

def number_or_nil(str)
  Integer(str || '')
rescue ArgumentError
  nil
end

main

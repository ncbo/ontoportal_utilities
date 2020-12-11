require 'multi_json'
require 'pry'
require 'optparse'
require_relative 'lib/config'
require_relative 'lib/bp_access'

@options = nil
@logger = nil

def main
  base_rest_url = Global.config.servers_to_compare.hash.keys[0]
  onts = ontologies(base_rest_url)
  all_by_uri = Set.new
  all_by_label = Set.new

  onts.each do |acronym|
    props = BPAccess.bp_ontology_properties(base_rest_url, acronym)
    unique_by_uri = props[:props].keys
    unique_by_label = props[:props].values.map { |val| val['label'] }.uniq
    all_by_uri.merge(unique_by_uri)
    all_by_label.merge(unique_by_label)
  end
  puts "Number of unique properties by URI: #{all_by_uri.length}"
  puts "Number of unique properties by Label: #{all_by_label.length}"
end

def ontologies(base_rest_url)
  onts = BPAccess.bp_ontologies(base_rest_url)
  onts.keys
end

main


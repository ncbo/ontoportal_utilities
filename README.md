# OntoPortal Utilities
A set of scripts for benchmarking and troubleshooting issues with OntoPortal

## Installation
1. Clone this repo and run `bundle install`
2. Copy `config/config.yml.sample` to `config/config.yml`
3. Edit `config/config.yml` and replace the following attributes with your own:
    1. `bp_api_key: "your-bioportal-api-key"`<br/>
&nbsp;BioPortal API key can be found here: https://bioportal.bioontology.org/account
4. If needed, edit the config parameter `servers_to_compare`, adding any number of servers to the array. The performance checks will be run against every combination of two servers in the array.
    1. `servers_to_compare: ["https://data.bioontology.org", "https://stagedata.bioontology.org"]`<br/>


## Server Data Comparator
Retrieves a given number of ontologies from a set of API servers and compares their metadata and class artifacts.

### Execution:
The script accepts the following parameters (all are OPTIONAL):
<pre>
    -o, ACR1,ACR2,ACR3 OR NUM   An optional comma-separated list of ontologies to test 
        --ont                   OR 
                                An optional number of RANDOM ontologies to test
                                Default: 10 random ontologies
        
    -c  NUM (integer > 0)       Optional number of classes to test per ontology
        --classes               Default: 500
     
    -i  --ignore_ids            Ignore the fact that Submission IDs are different between servers and proceed with ALL checks
                                Default: if Submission IDs are different, further checks NOT PERFORMED

    -l, PATH_TO_LOG_FILE        Optional path to the log file        
        --log                   Default: logs/server_data_comparator-run.log
         
    -h  --help                  Display help screen
</pre>

Usage: __$ bundle exec ruby server_data_comparator.rb [options]__

### Run Examples:
#### Test 10 random ontologies with 500 classes from each:
`$ bundle exec ruby server_data_comparator.rb`

#### Test 200 classes from ontologies NCIT, DOID, and BAO:
`$ bundle exec ruby server_data_comparator.rb -o NCIT,DOID,BAO -c 200`

#### Test 20 random ontologies with 500 classes from each and ignore possible mismatch between Submission IDs:
`$ bundle exec ruby server_data_comparator.rb -o 20 -i`

#### Test 20 random ontologies with 2000 classes from each:
`$ bundle exec ruby server_data_comparator.rb -o 20 -c 2000`

 
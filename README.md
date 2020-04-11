# OntoPortal Utilities
A set of scripts for benchmarking and troubleshooting issues with OntoPortal

## Installation
1. Clone this repo and run `bundle install`
2. Copy __config/config.yml.sample__ to __config/config.yml__
3. Edit __config/config.yml__ and replace the following attributes with your own:
    1. __bp_api_key__: "your-bioportal-api-key"
   
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BioPortal API key can be found here: https://bioportal.bioontology.org/account

## Server Data Comparator
Retrieves a given number of classes from a set of API servers and compares the results.

### Execution:
The script accepts the following parameters (all are OPTIONAL):
<pre>
    -o, ACR1,ACR2,ACR3 OR NUM   An optional comma-separated list of ontologies to test 
        --ont                   OR 
                                An optional number of RANDOM ontologies to test
                                Default: 10 random ontologies
        
    -c  NUM (integer > 0)       Optional number of classes to test per ontology
        --classes               Default: 30
     
    -l, PATH_TO_LOG_FILE        Optional path to the log file        
        --log                   Default: logs/server_data_comparator-run.log
         
    -h  --help                  Display help screen
</pre>

Usage: __server_data_comparator.rb [options]__

### Run Examples:
#### Test 10 random ontologies with 30 classes from each:
`$ bundle exec ruby server_data_comparator.rb`

#### Test 20 classes from ontologies NCIT, DOID, and BAO:
`$ bundle exec ruby server_data_comparator.rb -o NCIT,DOID,BAO -c 20`

#### Test 20 random ontologies with 10 classes from each:
`$ bundle exec ruby server_data_comparator.rb -o 20 -c 10`

 
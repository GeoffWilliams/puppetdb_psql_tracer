#!/opt/puppet/bin/ruby
require 'optparse'
require 'fileutils'
require 'pp'

$REPORT_DIR="reports"
$FAIL_DIR=$REPORT_DIR + "/fail"
$DEFAULT_TEST_DIR="tests"
$TEST_EXT="txt"
$TEST_FILE_GLOB="*.#{$TEST_EXT}"
$PSQL_LOG_DIR="/var/log/pe-postgresql/pg_log"
$DEFAULT_LOG_DELAY = 5
$CMD_RAKE="/opt/puppet/bin/rake -f /opt/puppet/share/puppet-dashboard/Rakefile RAILS_ENV=production"
$CMD_WS="curl"
$COMMENT="#"
$RERUN_SCRIPT_NAME="run.sh"
$SHEBANG="#!/opt/puppet/bin/ruby\n"
$ERROR_REPORT="error.txt"
$SQL_REPORT="sql.txt"
$OUTPUT_REPORT="output.txt"

def parse_command_line(args)
    status = true
    $options = {}

    opt_parser = OptionParser.new do |opts|
        opts.banner = "Usage #{args[0]} (--mode-rake|--mode-ws) [options] "
        
        # rake tests
        opts.on("--mode-rake", "test the rake system") do |mode_rake|
            $options[:mode_rake] = true
        end

        # web-service tests
        opts.on("--mode-ws", "test the web service system") do |mode_ws|
            $options[:mode_ws] = true
        end

        # log delay
        $options[:log_delay] = $DEFAULT_LOG_DELAY
        opts.on("--log-delay N", Integer, "Seconds to wait after running command before reading logs.  Default: #{$DEFAULT_LOG_DELAY}") do |n|
            $options[:log_delay] = n
        end

        $options[:test_dir] = $DEFAULT_TEST_DIR
        opts.on("--test-dir t", String, "Directory containing test files (*.txt; default #{$DEFAULT_TEST_DIR}") do |t|
            $options[:test_dir] = t
        end

    end
    
    begin
        opt_parser.parse!(args)
    rescue OptionParser::InvalidOption => e
        puts "Invalid option: '#{e.message}'"
        status = false
    end

    # make sure one and only one of --mode-rake/--mode-ws set
    if ! $options[:mode_rake] ^ $options[:mode_ws]
        status = false
        puts "One and only one of --mode-rake or --mode-ws must be specified"
    end

    if ENV['USER'] != "root"
        status = false
        puts "You must run this script as root so we can read the logs"
    end
        
    return status
end

def parse_test_file(filename) 
    contents = {}
    file = File.open(filename)
    file.each do |line|
        # ignore lines starting with comment character or completely blank
        line = line.chomp
        if ! line.start_with?($COMMENT) && line != ""
            name = line.gsub(/[^\w\s]/,"_")
            contents[name] = line
        end
    end
    pp contents
end

def main(argv)
    if parse_command_line(argv)
        puts "Puppetdb rake/web-service psql log tracer"
        puts "========================================="
        puts "Proceed to run tests? Type 'yes' to proceed"
        proceed = gets.chomp
        if proceed == "yes"
            tests = load_tests()
            if tests.length == 0
                puts "no tests found"
            else
                if create_report_dirs(tests)
                    puts "starting tests..."
                    run_tests(tests)
                else
                    puts "report dir already exists at #{$REPORT_DIR}; aborting"
                end
            end
        else
            puts "...exiting"
        end
    end
end

def run_tests(tests)
    # 2: run tests
    if $options[:mode_rake]
        test_cmd = $CMD_RAKE
    else
        test_cmd = $CMD_WS
    end

    tests.each do |group_test_name, group_test_value|
        puts "\nrunning tests in: #{group_test_name}"
        group_test_value.each do |test_name, test_value|
            puts "running test: #{test_name}"
            run_test(test_cmd, group_test_name, test_name, test_value)
        end
    end
end

def get_report_dir(group_test_name, test_name)
    $REPORT_DIR + "/" + group_test_name + "/" + test_name 
end

def run_test(test_cmd, group_test_name, test_name, test_value)
    # 1:  establish test report directory and command
    test_report_dir = get_report_dir(group_test_name, test_name)
    cmd = test_cmd + " " + test_value

    # 2:  write script to re-run test
    File.write(test_report_dir + "/" + $RERUN_SCRIPT_NAME, $SHEBANG + cmd)
    
    # 3: get current log file line count
    start_offset = get_log_size()    

    # 4: run tests
    begin 
        output = %x{#{cmd} 2>&1}
        File.write(test_report_dir + "/" + $OUTPUT_REPORT, output)

        # 5: wait a X seconds for database to stabilise after tests
        sleep $options[:log_delay]

        # 6: snag the new content from the file and save to report
        end_offset = get_log_size()
        total_lines = end_offset - start_offset

        # use tail + shell instead of native ruby - faster
        puts "#{test_name} log file lines: #{start_offset} - #{end_offset}"
        log_split_cmd = 
            "tail -n +#{start_offset} #{get_log_filename()} | " \
            "head -n #{total_lines} > " \
            "#{test_report_dir}/#{$SQL_REPORT}" 
        %x{#{log_split_cmd}}
       #puts log_split_cmd 

    rescue Exception => e
        puts "ERRROR running test #{test_name} see report in #{$FAIL_DIR}"
        File.write(test_report_dir + "/" + $ERROR_REPORT, 
            "Exception running test: #{test_name}\n\nmessage: \n" +
            e.message + "\n\nstack trace: \n" +
            e.backtrace.join("\n") + "\n"
        )
        FileUtils.mv(test_report_dir, $FAIL_DIR)
    end

end

def load_tests
    tests = {}
    if File.directory?($options[:test_dir])
        # load each test - one file per test
        Dir.glob($options[:test_dir] + "/" + $TEST_FILE_GLOB) do |filename|
            testname = File.basename(filename).gsub(/\.#{$TEST_EXT}$/ , "")
            tests[testname] = parse_test_file(filename)
        end 
    else
        puts "No test directory found at #{$options[:test_dir]}"
    end
    
    return tests
end

def create_report_dirs(tests)
    if File.directory?($REPORT_DIR)
        status = false
    else 
        # each test file...
        tests.each do |group_test_name,group_tests|
        
            # lines in each test file...
            group_tests.each do |test_name,test_data|
                FileUtils.mkdir_p get_report_dir(group_test_name, test_name)
            end
        end
        Dir.mkdir $FAIL_DIR
        status = true
    end
    return status
end

def get_log_filename
    # return the current logfile based on most recent file in directory
    # (glob)
    return Dir.glob($PSQL_LOG_DIR + "/*").max_by {|f| File.mtime(f)}
end

def get_log_size
    # return the current size of the postgres log file in LINES
    return %x{wc -l #{get_log_filename()}}.split.first.to_i
end

main(ARGV)

#!/opt/puppet/bin/ruby
$REPORT_DIR="reports"
$TEST_DIR="tests"
$TEST_EXT="txt"
$TEST_FILE_GLOB="*.#{$TEST_EXT}"
$PSQL_LOG_DIR="/var/log/pe-postgresql/pg_log"

def main
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

def run_tests(tests)
    tests.each do |test_name, test_value|
        puts "running test: #{test_name}"
        run_test(test_name, test_value)
    end
end

def run_test(test_name, test_value)
    # 1: get current log file line count
    start_offset = get_log_size()    

    # 2: run tests
    
    # 3: wait a X seconds for database to stabilise after tests

    # 4: snag the new content from the file and save to report
    end_offset = get_log_size()

    puts "#{test_name} log file lines: #{start_offset} - #{end_offset}"
end

def load_tests
    tests = {}
    if File.directory?($TEST_DIR)
        # load each test - one file per test
        Dir.glob($TEST_DIR + "/" + $TEST_FILE_GLOB) do |filename|
            testname = File.basename(filename).gsub(/\.#{$TEST_EXT}$/ , "")
            tests[testname] = "found a test file"
        end 
    else
        puts "No test directory found at #{$TEST_DIR}"
    end
    
    return tests
end

def create_report_dirs(tests)
    if File.directory?($REPORT_DIR)
        status = false
    else 
        Dir.mkdir $REPORT_DIR
        tests.each do |key,value|
            test_report_dir = $REPORT_DIR + "/" + key
            Dir.mkdir test_report_dir
        end
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

main()

#!/opt/puppet/bin/ruby
$REPORT_DIR="reports"
$TEST_DIR="tests"

def main
    puts "Puppetdb rake/web-service psql log tracer"
    puts "========================================="
    puts "Proceed to run tests? Type 'yes' to proceed"
    proceed = gets.chomp
    if proceed == "yes"
        if create_report_dirs()
            puts "starting tests..."
        else
            puts "report dir already exists at #{$REPORT_DIR}; aborting"
        end
    else
        puts "...exiting"
    end
end

def create_report_dirs
    if File.directory?($REPORT_DIR)
        status = false
    else 
        Dir.mkdir $REPORT_DIR
        status = true
    end
    return status
end

main()

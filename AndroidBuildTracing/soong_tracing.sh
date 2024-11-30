#!/bin/bash

# Main execution script
main() {
    setup_soong_trace
    setup_detailed_metrics
    
    echo "Starting build with tracing at ${TRACE_TIMESTAMP}"
    
    # Start monitoring
    monitor_build
    
    # Analyze results
    analyze_soong_trace
    
    # Generate report
    generate_report
}

# Set up base tracing environment
setup_soong_trace() {
    export SOONG_METRICS=1               # Enable basic metrics
    export SOONG_PROFILE=1               # Enable profiling
    export SOONG_PROFILE_CSV=1           # Enable CSV output
    export OUT_DIR=out                   # Define output directory
    export TRACE_DIR="${OUT_DIR}/traces" # Directory for trace files
    
    # Create trace directory if it doesn't exist
    mkdir -p "${TRACE_DIR}"
    
    # Timestamp for trace files
    export TRACE_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
}

# Configure detailed metrics collection
setup_detailed_metrics() {
    # Enable specific metrics
    export SOONG_METRICS_ENABLE="timing,memory,cpu,io,network,modules"
    
    # Configure memory profiling
    export SOONG_MEMORY_PROFILE=1
    
    # Set trace buffer size (in MB)
    export SOONG_TRACE_BUFFER_SIZE=512
    
    # Enable module dependency tracking
    export SOONG_TRACK_MODULES=1
}

monitor_build() {
    local build_start=$(date +%s)
    local log_file="${TRACE_DIR}/build_${TRACE_TIMESTAMP}.log"
    
    # Start monitoring in background
    (
        while true; do
            # Capture CPU and memory usage
            ps aux | grep -E "soong|ninja" >> "${TRACE_DIR}/resource_${TRACE_TIMESTAMP}.log"
            # Capture IO stats
            iostat -x 1 1 >> "${TRACE_DIR}/io_${TRACE_TIMESTAMP}.log"
            sleep 5
        done
    ) &
    MONITOR_PID=$!
    
    # Run the build
    make -j$(nproc) 2>&1 | tee "${log_file}"
    
    # Stop monitoring
    kill $MONITOR_PID
    
    local build_end=$(date +%s)
    echo "Build took $((build_end - build_start)) seconds" >> "${log_file}"
}

analyze_soong_trace() {
    local trace_file="${TRACE_DIR}/soong_metrics_${TRACE_TIMESTAMP}.pb"
    
    # Parse timing information
    python3 "${ANDROID_BUILD_TOP}/build/soong/scripts/metrics_parser.py" \
        --input "${trace_file}" \
        --output "${TRACE_DIR}/timing_analysis.txt"
        
    # Generate module dependency graph
    python3 "${ANDROID_BUILD_TOP}/build/soong/scripts/graph.py" \
        --input "${trace_file}" \
        --output "${TRACE_DIR}/dependency_graph.dot"
}

generate_report() {
    local report_file="${TRACE_DIR}/report_${TRACE_TIMESTAMP}.txt"
    
    echo "Build Performance Report" > "${report_file}"
    echo "======================" >> "${report_file}"
    echo "Timestamp: ${TRACE_TIMESTAMP}" >> "${report_file}"
    
    # Add build time
    grep "Build took" "${TRACE_DIR}/build_${TRACE_TIMESTAMP}.log" >> "${report_file}"
    
    # Add top 10 slowest modules
    echo -e "\nSlowest Modules:" >> "${report_file}"
    grep "module_build_duration" "${TRACE_DIR}/timing_analysis.txt" | \
        sort -rn -k2 | head -10 >> "${report_file}"
    
    # Add memory usage summary
    echo -e "\nPeak Memory Usage:" >> "${report_file}"
    awk '/VmPeak/{print $2}' "${TRACE_DIR}/resource_${TRACE_TIMESTAMP}.log" | \
        sort -rn | head -1 >> "${report_file}"
}

# Execute main function
main "$@"
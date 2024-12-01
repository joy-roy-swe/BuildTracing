#!/bin/bash

# Set up tracing and monitoring for Gradle Android build
setup_gradle_trace() {
    # Create trace directory
    export TRACE_DIR="$(pwd)/build_traces"
    mkdir -p "${TRACE_DIR}"
    
    # Timestamp for trace files
    export TRACE_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    # Gradle-specific tracing configurations
    export GRADLE_OPTS="-Dorg.gradle.daemon=true \
                        -Dorg.gradle.caching=true \
                        -Dorg.gradle.parallel=true \
                        -Dorg.gradle.jvmargs=-Xmx4096m \
                        -Dorg.gradle.logging.level=info"
}

monitor_gradle_build() {
    local build_start=$(date +%s)
    local log_file="${TRACE_DIR}/build_${TRACE_TIMESTAMP}.log"
    local perf_file="${TRACE_DIR}/performance_${TRACE_TIMESTAMP}.log"
    
    # Background monitoring process
    (
        while true; do
            # Capture system resources
            echo "$(date): System Resources" >> "${perf_file}"
            top -bn1 | head -n 5 >> "${perf_file}"
            free -h >> "${perf_file}"
            df -h >> "${perf_file}"
            sleep 5
        done
    ) &
    MONITOR_PID=$!
    
    # Run Gradle build with performance and build info
    ./gradlew assembleDebug \
        --profile \
        --scan \
        --console=plain \
        2>&1 | tee "${log_file}"
    
    # Stop background monitoring
    kill $MONITOR_PID
    
    local build_end=$(date +%s)
    echo "Total Build Time: $((build_end - build_start)) seconds" >> "${log_file}"
}

analyze_gradle_trace() {
    # Analyze build performance reports
    local trace_dir="${TRACE_DIR}"
    
    # Extract key performance metrics
    echo "Build Performance Analysis" > "${trace_dir}/analysis_${TRACE_TIMESTAMP}.txt"
    
    # Analyze build scan if available
    if [ -f "build/reports/buildScan.html" ]; then
        echo "Build Scan Link:" >> "${trace_dir}/analysis_${TRACE_TIMESTAMP}.txt"
        cat "build/reports/buildScan.html" | grep -o 'https://.*' >> "${trace_dir}/analysis_${TRACE_TIMESTAMP}.txt"
    fi
    
    # Summarize build time and resource usage
    grep "Total Build Time" "${trace_dir}/build_${TRACE_TIMESTAMP}.log" >> "${trace_dir}/analysis_${TRACE_TIMESTAMP}.txt"
    tail -n 20 "${trace_dir}/performance_${TRACE_TIMESTAMP}.log" >> "${trace_dir}/analysis_${TRACE_TIMESTAMP}.txt"
}

# Main execution
main() {
    setup_gradle_trace
    monitor_gradle_build
    analyze_gradle_trace
    
    echo "Build tracing complete. Check traces in ${TRACE_DIR}"
}

# Run the script
main
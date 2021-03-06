#!/bin/bash -e
# Copyright 2018 WSO2 Inc. (http://wso2.org)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------------------------------------------------------------------------
# Start WSO2 Micro Integrator
# ----------------------------------------------------------------------------

default_heap_size="4G"
heap_size="$default_heap_size"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 [-m <heap_size>] [-h]"
    echo "-m: The heap memory size of WSO2 Micro Integrator. Default: $default_heap_size."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "m:h" opt; do
    case "${opt}" in
    m)
        heap_size=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"

if [[ -z $heap_size ]]; then
    echo "Please provide the heap size for WSO2 Micro Integrator."
    exit 1
fi

jvm_dir=""
for dir in /usr/lib/jvm/jdk1.8*; do
    [ -d "${dir}" ] && jvm_dir="${dir}" && break
done
export JAVA_HOME="${jvm_dir}"

carbon_bootstrap_class=org.wso2.carbon.bootstrap.Bootstrap
product_path=$HOME/wso2mi
startup_script=$product_path/bin/micro-integrator.sh

if [[ ! -f $startup_script ]]; then
    startup_script=$product_path/bin/wso2server.sh
fi

if pgrep -f "$carbon_bootstrap_class" >/dev/null; then
    echo "Shutting down Micro Integrator"
    $startup_script stop

    echo "Waiting for MI to stop"
    while true; do
        if ! pgrep -f "$carbon_bootstrap_class" >/dev/null; then
            echo "MI stopped"
            break
        else
            sleep 10
        fi
    done
fi

log_files=($product_path/repository/logs/*)
if [ ${#log_files[@]} -gt 1 ]; then
    echo "Log files exists. Moving to /tmp"
    mv "${log_files[@]}" /tmp/
fi

echo "Setting Heap to ${heap_size}"
export JVM_MEM_OPTS="-Xms${heap_size} -Xmx${heap_size}"

echo "Enabling GC Logs"
export JAVA_OPTS="-XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:$product_path/repository/logs/gc.log"

echo "Starting MI"
$startup_script start -DenablePrometheusApi=true

echo "Waiting for MI to start"

exit_status=100

n=0
until [ $n -ge 60 ]; do
   response_code=$(curl -s -w '%{http_code}' -o /dev/null http://localhost:9201/metric-service/metrics || echo "")
   if [ $response_code -eq 200 ]; then
       echo "MI is up and running"
       exit_status=0
       break
   fi
   sleep 5
   n=$(($n + 1))
done

# Wait for another 5 seconds to make sure that the server is ready to accept API requests.
sleep 5
exit $exit_status

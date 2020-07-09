#!/usr/bin/env bash
# Copyright (c) 2019, wso2 Inc. (http://wso2.org) All Rights Reserved.
#
# wso2 Inc. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# ----------------------------------------------------------------------------
# Run Identity Server Performance tests for two node cluster deployment.
# ----------------------------------------------------------------------------

source ../common/common-functions.sh

script_start_time=$(date +%s)
timestamp=$(date +%Y-%m-%d--%H-%M-%S)


key_file=""
bastion_node_ip=""
rds_host=""
nginx_instance_ip=""
aws_access_secret=""
certificate_name=""
jmeter_setup=""
is_setup=""
default_db_username="wso2carbon"
db_username="$default_db_username"
default_db_password="wso2carbon"
db_password="$default_db_password"
default_db_storage="100"
db_storage=$default_db_storage
default_db_instance_type=db.m4.xlarge
db_instance_type=$default_db_instance_type
default_is_instance_type=c5.xlarge
wso2_is_instance_type="$default_is_instance_type"
default_bastion_instance_type=c5.xlarge
bastion_instance_type="$default_bastion_instance_type"

results_dir="$PWD/results-$timestamp"
default_minimum_stack_creation_wait_time=10
minimum_stack_creation_wait_time="$default_minimum_stack_creation_wait_time"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 -k <key_file> -a <aws_access_key> -s <aws_access_secret>"
    echo "   -c <certificate_name> -j <jmeter_setup_path>"
    echo "   [-n <IS_zip_file_path>]"
    echo "   [-u <db_username>] [-p <db_password>] [-d <db_storage>] [-e <db_instance_type>]"
    echo "   [-i <wso2_is_instance_type>] [-b <bastion_instance_type>]"
    echo "   [-w <minimum_stack_creation_wait_time>] [-h]"
    echo ""
    echo "-k: The Amazon EC2 key file to be used to access the instances."
    echo "-a: The perf cloud domain name: "
    echo "-s: The AWS RDS host name."
    echo "-j: The path to JMeter setup."
    echo "-c: IS Bastion host ip."
    echo "-n: The is server zip"
    echo "-u: The database username. Default: $default_db_username."
    echo "-p: The database password. Default: $default_db_password."
    echo "-d: The database storage in GB. Default: $default_db_storage."
    echo "-e: The database instance type. Default: $default_db_instance_type."
    echo "-i: Base 64 encoded adminCredentials: $adminCredentials."
    echo "-b: Plain test admin user password : $adminPassword."
    echo "-w: The minimum time to wait in minutes before polling for cloudformation stack's CREATE_COMPLETE status."
    echo "    Default: $default_minimum_stack_creation_wait_time minutes."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "k:a:s:c:j:n:u:p:d:e:i:b:w:h" opts; do
    case $opts in
    k)
        key_file=${OPTARG}
        ;;
    a)
        nginx_instance_ip=${OPTARG}
        ;;
    s)
        rds_host=${OPTARG}
        ;;
    c)
        bastion_node_ip=${OPTARG}
        ;;
    j)
        jmeter_setup=${OPTARG}
        ;;
    n)
        is_setup=${OPTARG}
        ;;
    u)
        db_username=${OPTARG}
        ;;
    p)
        db_password=${OPTARG}
        ;;
    d)
        db_storage=${OPTARG}
        ;;
    e)
        db_instance_type=${OPTARG}
        ;;
    i)
        adminCredentials=${OPTARG}
        ;;
    b)
        adminPassword=${OPTARG}
        ;;
    w)
        minimum_stack_creation_wait_time=${OPTARG}
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

run_performance_tests_options="$@"

if [[ ! -f $key_file ]]; then
    echo "Please provide the key file."
    exit 1
fi

if [[ ${key_file: -4} != ".pem" ]]; then
    echo "AWS EC2 Key file must have .pem extension"
    exit 1
fi


if [[ -z $db_username ]]; then
    echo "Please provide the database username."
    exit 1
fi

if [[ -z $db_password ]]; then
    echo "Please provide the database password."
    exit 1
fi

if [[ -z $db_storage ]]; then
    echo "Please provide the database storage size."
    exit 1
fi

if [[ -z $adminCredentials ]]; then
    echo "Please provide the database instance type."
    exit 1
fi

if [[ -z $jmeter_setup ]]; then
    echo "Please provide the path to JMeter setup."
    exit 1
fi

if [[ -z $wso2_is_instance_type ]]; then
    echo "Please provide the AWS instance type for WSO2 IS nodes."
    exit 1
fi

if [[ -z $bastion_instance_type ]]; then
    echo "Please provide the AWS instance type for the bastion node."
    exit 1
fi

if [[ -z $is_setup ]]; then
    echo "Please provide is zip file path."
    exit 1
fi

if ! [[ $minimum_stack_creation_wait_time =~ ^[0-9]+$ ]]; then
    echo "Please provide a valid minimum time to wait before polling for cloudformation stack's CREATE_COMPLETE status."
    exit 1
fi

key_filename=$(basename "$key_file")
key_name=${key_filename%.*}

# Checking for the availability of commands in jenkins.
check_command bc
check_command aws
check_command unzip
check_command jq
check_command python

mkdir "$results_dir"
echo ""
echo "Results will be downloaded to $results_dir"

echo ""
echo "Extracting IS Performance Distribution to $results_dir"
tar -xf target/is-performance-twonode-cluster*.tar.gz -C "$results_dir"

cp run-performance-tests.sh "$results_dir"/jmeter/
estimate_command="$results_dir/jmeter/run-performance-tests.sh -t ${run_performance_tests_options[@]}"
echo ""
echo "Estimating time for performance tests: $estimate_command"
# Estimating this script will also validate the options. It's important to validate options before creating the stack.
$estimate_command

temp_dir=$(mktemp -d)


echo "your key is"
echo "$key_file"

ln -s "$key_file" "$temp_dir"/"$key_filename"

echo "Bastion Node Public IP: $bastion_node_ip"


echo "RDS Hostname: $rds_host"

if [[ -z $bastion_node_ip ]]; then
    echo "Bastion node IP could not be found. Exiting..."
    exit 1
fi

wso2_is_1_ip=$bastion_node_ip
wso2_is_2_ip=$bastion_node_ip

if [[ -z $rds_host ]]; then
    echo "RDS host could not be found. Exiting..."
    exit 1
fi

echo ""
echo "Copying files to Bastion node..."
echo "============================================"
copy_setup_files_command="scp -r -i $key_file -o "StrictHostKeyChecking=no" $results_dir/setup ubuntu@$bastion_node_ip:/home/ubuntu/"
copy_repo_setup_command="scp -i $key_file -o "StrictHostKeyChecking=no" target/is-performance-*.tar.gz \
    ubuntu@$bastion_node_ip:/home/ubuntu"

echo "$copy_setup_files_command"
$copy_setup_files_command
echo "$copy_repo_setup_command"
$copy_repo_setup_command

copy_jmeter_setup_command="scp -i $key_file -o StrictHostKeyChecking=no $jmeter_setup ubuntu@$bastion_node_ip:/home/ubuntu/"
copy_is_pack_command="scp -i $key_file -o "StrictHostKeyChecking=no" $is_setup ubuntu@$bastion_node_ip:/home/ubuntu/wso2is.zip"
copy_key_file_command="scp -i $key_file -o "StrictHostKeyChecking=no" $key_file ubuntu@$bastion_node_ip:/home/ubuntu/private_key.pem"
copy_connector_command="scp -r -i $key_file -o "StrictHostKeyChecking=no" $results_dir/lib/* ubuntu@$bastion_node_ip:/home/ubuntu/"

echo "$copy_jmeter_setup_command"
$copy_jmeter_setup_command
echo "$copy_is_pack_command"
$copy_is_pack_command
echo "$copy_key_file_command"
$copy_key_file_command
echo "$copy_connector_command"
$copy_connector_command

echo ""
echo "Running Bastion Node setup script..."
echo "============================================"
setup_bastion_node_command="ssh -i $key_file  -o "StrictHostKeyChecking=no" -t ubuntu@$bastion_node_ip \
    sudo ./setup/setup-bastion.sh  -i $wso2_is_2_ip -r $rds_host -l $nginx_instance_ip -a $adminCredentials -w $adminPassword"
echo "$setup_bastion_node_command"
# Handle any error and let the script continue.
$setup_bastion_node_command || echo "Remote ssh command failed."



echo ""
echo "Running performance tests..."
echo "============================================"
scp -i "$key_file" -o StrictHostKeyChecking=no run-performance-tests.sh ubuntu@"$bastion_node_ip":/home/ubuntu/workspace/jmeter
run_performance_tests_command="./workspace/jmeter/run-performance-tests.sh $rds_host $db_password $db_username $adminCredentials $adminPassword -p 443 ${run_performance_tests_options[@]}"
run_remote_tests="ssh -i $key_file -o "StrictHostKeyChecking=no" -t ubuntu@$bastion_node_ip $run_performance_tests_command"
echo "$run_remote_tests"
$run_remote_tests || echo "Remote test ssh command failed."

echo ""
echo "Downloading results..."
echo "============================================"
download="scp -i $key_file -o "StrictHostKeyChecking=no" ubuntu@$bastion_node_ip:/home/ubuntu/results.zip $results_dir/"
echo "$download"
$download || echo "Remote download failed"

if [[ ! -f $results_dir/results.zip ]]; then
    echo ""
    echo "Failed to download the results.zip"
    exit 0
fi

echo ""
echo "Creating summary.csv..."
echo "============================================"
cd "$results_dir"
unzip -q results.zip
wget -q http://sourceforge.net/projects/gcviewer/files/gcviewer-1.35.jar/download -O gcviewer.jar
"$results_dir"/jmeter/create-summary-csv.sh -d results -n "WSO2 Identity Server" -p wso2is -c "Heap Size" \
    -c "Concurrent Users" -r "([0-9]+[a-zA-Z])_heap" -r "([0-9]+)_users" -i -l -k 2 -g gcviewer.jar

echo "Creating summary results markdown file..."
./jmeter/create-summary-markdown.py --json-files cf-test-metadata.json results/test-metadata.json --column-names \
    "Scenario Name" "Concurrent Users" "Label" "Error %" "Throughput (Requests/sec)" "Average Response Time (ms)" \
    "Standard Deviation of Response Time (ms)" "99th Percentile of Response Time (ms)" \
    "WSO2 Identity Server 1 GC Throughput (%)" "WSO2 Identity Server GC 2 Throughput (%)"

rm -rf cf-test-metadata.json cloudformation/ common/ gcviewer.jar is/ jmeter/ jtl-splitter/ netty-service/ payloads/ results/ sar/ setup/

echo ""
echo "Done."

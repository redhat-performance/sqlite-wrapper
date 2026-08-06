#!/bin/bash
#
#                         License
#
#=================================================
# Copyright (C) <data>  <your name> <your email>
#=================================================
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# This script automates the execution of coremark.  It will determine the
# set of default run parameters based on the system configuration.
#

gl_iter=0
commit="none"
test_name="sqlite"
test_version="v1.00"
results_file=""
arguments="$@"
script_dir=$(realpath $(dirname $0))
proc_list=""
table_entries=5000

#
# Build the table entries to work with.
table_entries_build()
{
	tbl_entries=$1
	if [[ ! -f sqlite-insertions_${tbl_entries} ]]; then
		#
		# Min/max for random value.
		#
		min=1000000000000000
		max=9999999999999999
		range=$((max - min + 1))
		for rec_numb in $(seq 1 1 $tbl_entries); do
			random_val=$(( $(od -An -N8 -tu8 /dev/urandom) % range))
			#
			# We want the absolute value.
			#
			random_val=$(( random_val < 0 ? -random_val : random_val ))
			let "random_val=${random_val}+${min}"
			random_4_bytes=$(( $(od -vAn -N8 -t u8 < /dev/urandom) % 9000 ))
			#
			# We want the absolute value.
			#
			random_4_bytes=$(( random_4_bytes < 0 ? -random_4_bytes : random_4_bytes ))
			let "random_4_bytes=${random_4_bytes}+1000"
			echo "INSERT INTO 'pts1' ('I', 'DT', 'F1', 'F2') VALUES ('${rec_numb}', CURRENT_TIMESTAMP, '${random_4_bytes}', '${random_val}');" >>  sqlite-insertions_${tbl_entries}
		done
	fi
	cp sqlite-insertions_${tbl_entries} sqlite-insertions.txt
}

#
# Execute the sqlite load.  We will have one for each requested proc.
#
exec_db()
{
	DB=benchmark-$1.db
	rm -f $DB
	sqlite3 $DB  "CREATE TABLE pts1 ('I' SMALLINT NOT NULL, 'DT' TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, 'F1' VARCHAR(4) NOT NULL, 'F2' VARCHAR(16) NOT NULL);"
	sqlite3 $DB "PRAGMA journal_mode='wal';"
	#
	# Wait for all jobs to be ready.
	#
	until [ -f "ready_file" ]; do
		sleep 1
	done
	echo "cat sqlite-insertions.txt | sqlite3 $DB" > runner_db_$DB
	echo "cat sqlite-insertions.txt | sqlite3 $DB" >> runner_db_$DB
	echo "cat sqlite-insertions.txt | sqlite3 $DB" >> runner_db_$DB
	chmod 755 runner_db_$DB
	start_time=$(retrieve_time_stamp)
	/bin/time -o sqlite_timeing_iterations_${gl_iter}_entries_${3}_proc_${1}_of_${2}_procs.txt -f "%e %S %U" ./runner_db_$DB
	rtc=$?
	if [[ $rtc != 0 ]]; then
		echo ./runner_db_$DB failed.
	fi
	end_time=$(retrieve_time_stamp)
	echo "Start_time: $start_time" >> sqlite_timeing_iterations_${gl_iter}_entries_${3}_proc_${1}_of_${2}_procs.txt 
	echo "End_time: $end_time" >> sqlite_timeing_iterations_${gl_iter}_entries_${3}_proc_${1}_of_${2}_procs.txt
	exit $rtc
}

execute_sqlite()
{
	rm -f runner_db_*
	rm -f ready_file
	proc_num=$1

	pids=""
	for i in $(seq 1 $proc_num)
	do
		exec_db $i $proc_num ${2} &
		pids="$pids $!"
	done
	touch ready_file
	wait $pids
}

exit_out()
{
	echo $1
	exit $2
}

if [ ! -f "/tmp/${test_name}.out" ]; then
	command="${0} $@"
	echo $command
	$command &> /tmp/${test_name}.out
	rtc=$?
	cat /tmp/${test_name}.out
	rm /tmp/${test_name}.out
	exit $rtc 
fi

curdir=$(dirname $(realpath $0))
if [[ $0 == "./"* ]]; then
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	if [[ $chars == 1 ]]; then
		run_dir=`pwd`
	else
		run_dir=`echo $0 | cut -d'/' -f 1-${chars} | cut -d'.' -f2-`
		run_dir="${curdir}${run_dir}"
	fi
elif [[ $0 != "/"* ]]; then
	dir=`echo $0 | rev | cut -d'/' -f2- | rev`
	run_dir="${curdir}/${dir}"
else
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	run_dir=`echo $0 | cut -d'/' -f 1-${chars}`
	if [[ $run_dir != "/"* ]]; then
		run_dir=${curdir}/${run_dir}
	fi
fi
cd $run_dir
rm -rf sqlite_timeing_* results_${test_name}* 

show_usage=0

TOOLS_BIN="$HOME/test_tools"
export TOOLS_BIN

usage()
{
	echo "Usage $1:"
	echo "--table_entries <a,b,c...>: comma separated list of table sizes to create."
	echo "--procs <a,b,c....>: comma separated list of procs to create."
	source $TOOLS_BIN/general_setup --usage
	exit $E_USAGE
}

attempt_tools_generic()
{
	method="$1"
	if [[ ! -d "$TOOLS_BIN" ]]; then
		$method ${tools_git}/archive/refs/heads/main.zip
		if [[ $? -eq 0 ]]; then
			unzip -q main.zip
			mv test_tools-wrappers-main ${TOOLS_BIN}
			rm main.zip
		fi
	fi
}

attempt_tools_git()
{
	if [[ ! -d "$TOOLS_BIN" ]]; then
		git clone $tools_git "$TOOLS_BIN"
		if [ $? -ne 0 ]; then
			exit_out "Error: pulling git $tools_git failed." 101
		fi
	fi
}

install_test_tools()
{
	#
	# Clone the repo that contains the common code and tools
	#
	tools_git=https://github.com/redhat-performance/test_tools-wrappers
	found=0
	for arg in "$@"; do
		if [ $found -eq 1 ]; then
			tools_git=$arg
			found=0
		fi
		if [[ $arg == "--tools_git" ]]; then
			found=1
		fi

		#
		# We do the usage check here, as we do not want to be calling
		# the common parsers then checking for usage here.  Doing so will
		# result in the script exiting with out giving the test options.
		#
		if [[ $arg == "--usage" ]]; then
			show_usage=1
		fi
	done

	#
	# Check to see if the test tools directory exists.  If it does, we do not need to
	# clone the repo.
	#
	attempt_tools_generic "wget"
	attempt_tools_generic "curl -L -O "
	attempt_tools_git

	if [ $show_usage -eq 1 ]; then
		usage $1
	fi
}

install_test_tools "$@"

#
# Variables set by general setup.
#
# TOOLS_BIN: points to the tool directory
# to_home_root: home directory
# to_configuration: configuration information
# to_times_to_run: number of times to run the test
# to_run_label: Label for the run
# to_user: User on the test system running the test
# to_sys_type: for results info, basically aws, azure or local
# to_sysname: name of the system
# to_tuned_setting: tuned setting
#

pushd $curdir 2> /dev/null
source "$TOOLS_BIN/general_setup" "$@"
popd 2> /dev/null
# Gather hardware information
$TOOLS_BIN/gather_data ${curdir}

ARGUMENT_LIST=(
	"procs"
	"table_entries"
)

NO_ARGUMENTS=(
	"usage"
)

# read arguments
opts=$(getopt \
	--longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
	--longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
	--name "$(basename "$0")" \
	--options "h" \
	-- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
	case "$1" in
		--procs)
			proc_list=$(echo $2 | sed "s/,/ /g")
			shift 2
		;;
		--table_entries)
			table_entries=$(echo $2 | sed "s/,/ /g")
			shift 2
		;;
		--usage)
			usage $0
		;;
		-h)
			usage $0
		;;
		--)
			break
		;;
		*)
			echo option not found $1
			usage $0
		;;
	esac
done

package_tool --no_packages $to_no_pkg_install --wrapper_config $curdir/sqlite.json

if [[ $proc_list == "" ]]; then
	cpus=$(nproc)
	if [[ $cpus -lt 8 ]]; then
		intervals=$cpus
	else
		intervals=8
	fi
	proc_list=$(${TOOLS_BIN}/generate_intervals --interval $intervals --max_value $cpus | sed "s/,/ /g")
fi

# Get PCP setup if we're using it
if [[ $to_use_pcp -eq 1 ]]; then
	source $TOOLS_BIN/pcp/pcp_commands.inc
	setup_pcp
	pcp_cfg=$TOOLS_BIN/pcp/default.cfg
	pcpdir=/tmp/pcp_`date "+%Y.%m.%d-%H.%M.%S"`
	start_pcp ${pcpdir}/ ${test_name} $pcp_cfg
fi

for gl_iter in $(seq 1 1 $to_times_to_run); do
	for tb_entries in $table_entries; do
		table_entries_build $tb_entries
		for proc in $proc_list; do
			if [[ $to_use_pcp -eq 1 ]]; then
				start_pcp_subset
			fi
			start_time=$(date -u "+%Y%m%d%H%M%S")
			execute_sqlite $proc $tb_entries
			end_time=$(date -u "+%Y%m%d%H%M%S")
			max_elpased_time=$(cut -d' ' -f 1 sqlite_timeing_iterations_${gl_iter}_entries_${tb_entries}_proc_*_of_${proc}_procs.txt | sort -n | tail -1)
			max_sys=$(cut -d' ' -f 2 sqlite_timeing_iterations_${gl_iter}_entries_${tb_entries}_proc_*_of_${proc}_procs.txt | sort -n | tail -1)
			max_user=$(cut -d' ' -f 3 sqlite_timeing_iterations_${gl_iter}_entries_${tb_entries}_proc_*_of_${proc}_procs.txt | sort -n | tail -1)
#
# DJV Need to do sum of user and system, average for elapsed.
#			echo 1,$tb_entries,$proc,$max_elpased_time,$max_sys,$max_user,$start_time,$end_time >> $results_file
			if [[ $to_use_pcp -eq 1 ]]; then
				max_elpased_time=$(echo $max_elpased_time | cut -d'.' -f1)
				max_sys=$(echo $max_sys | cut -d'.' -f1)
				max_user=$(echo $max_user | cut -d'.' -f1)
				results2pcp_add_value "iteration:1"
				results2pcp_add_value "table_entries:${tb_entries}"
				results2pcp_add_value "runtime:${max_elpased_time}"
				results2pcp_add_value "numprocs:${proc}"
				results2pcp_add_value "sys_time:${max_sys}"
				results2pcp_add_value "user_time:${max_user}"
				results2pcp_add_value "end_time:${end_time}"
				results2pcp_add_value "start_time:${start_time}"
				results2pcp_add_value_commit
				reset_pcp_om
				stop_pcp_subset
			fi
		done
	done
done

# Shutdown PCP and clean up after ourselves
if [[ $to_use_pcp -eq 1 ]]; then
	stop_pcp
	shutdown_pcp
fi
#
# Need to group files together.
#

entries=$(ls sqlite_timeing_iterations* | cut -d'_' -f 6 | sort -u)
total_iters=$(ls sqlite_timeing_iterations* | cut -d'_' -f 4 | sort -u)

reduce_data()
{
	tbl_entries=$1
	tprocs=$2
	real_time="0"
	system_time=0
	user_time=0
	iterations=0
	local entries=0
	start_time=""
	end_time=""

	for iters in $total_iters; do	
		let "iterations=${iterations}+1"
		file_list=$(ls sqlite_timeing_iterations_${iters}_entries_${tbl_entries}_proc_*_of_${tprocs}_procs.txt)
		for file in $file_list; do
			data=$(grep -v Start_time $file | grep -v End_time)
			if [[ $start_time == "" ]]; then
				start_time=$(grep Start_time $file | cut -d' ' -f2)
				end_time=$(grep End_time $file | cut -d' ' -f2)
			fi
			tmp=$(echo "$data" | cut -d' ' -f3)
			user_time=$(echo "scale=2;${tmp}+${user_time}" | bc)
			tmp=$(echo "$data" | cut -d' ' -f2)
			system_time=$(echo "scale=2;${tmp}+${system_time}" | bc)
			tmp=$(echo $data | cut -d' ' -f1)
			real_time=$(echo "scale=2;${tmp}+${real_time}" | bc)
		done
	done
	real_time=$(echo "scale=2;${real_time}/(${iterations}*${tprocs})" | bc)
	user_time=$(echo "scale=2;${user_time}/${iterations}" | bc)
	system_time=$(echo "scale=2;${system_time}/${iterations}" | bc)
	echo $tbl_entries,$tprocs,$real_time,$user_time,$system_time,$start_time,$end_time >> $results_file
}

for tbl_entries in $entries;
do
	results_file="results_${test_name}_${tbl_entries}.csv"
	$TOOLS_BIN/test_header_info --front_matter --results_file $results_file --host $to_configuration --sys_type $to_sys_type --tuned $to_tuned_setting --results_version $test_version --test_name $test_name --field_header "table_entries,procs,Real_time,User_time,System_time"
	for tprocs in $proc_list;
	do
		reduce_data $tbl_entries $tprocs
	done
	${TOOLS_BIN}/csv_to_json $to_json_flags --csv_file $results_file --output_file sqlite_verify.json
	test_rtc=$?
	if [[ $test_rtc -ne 0 ]]; then
		exit_out "${TOOLS_BIN}/csv_to_json $to_json_flags --csv_file $results_file --output_file sqlite_verify.json returned an an error" $test_rtc
	fi
	${TOOLS_BIN}/verify_results $to_verify_flags --schema_file $script_dir/results_schema.py --class_name sqlite_Results --file sqlite_verify.json
	test_rtc=$?
	if [[ $test_rtc -ne 0 ]]; then
		echo Test failure detected: $results_file
	fi
done

${TOOLS_BIN}/save_results --curdir $curdir --home_root $to_home_root --other_files "*_summary,*.txt,test_results_report,${pcpdir},*csv" --results $results_file --test_name sqlite --tuned_setting=$to_tuned_setting --version $test_version --user $to_user
exit $E_SUCCESS

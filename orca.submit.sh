#! /bin/bash

###
#
# orca.submit.sh -- 
#   a script to submit a ORCA 4 calculation to a queuing system
# Copyright (C) 2019 Martin C Schwarzer
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
###

# You might not want to make modifications here.
# If you do improve the script, I would be happy to learn about it.

### begin of script content ###

# 
# The help lines are distributed throughout the script and grepped for
#
#hlp   This script will sumbit an ORCA input file to the queueing system.
#hlp   It is designed to work on the RWTH compute cluster in 
#hlp   combination with the slurm queueing system.
#hlp
#hlp   orca.submit.sh  Copyright (C) 2019  Martin C Schwarzer
#hlp   This program comes with ABSOLUTELY NO WARRANTY; this is free software, 
#hlp   and you are welcome to redistribute it under certain conditions; 
#hlp   please see the license file distributed alongside this repository,
#hlp   which is available when you type '${0##*/} license',
#hlp   or at <https://github.com/polyluxus/tools-for-gamess.bash>.
#hlp
#hlp   Usage: $scriptname [options] [IPUT_FILE]
#hlp

#
# Generic functions to find the scripts 
# (Copy of ./resources/locations.sh)
#
# Let's know where the script is and how it is actually called
#

get_absolute_location ()
{
    # Resolves the absolute location of parameter and returns it
    # Taken from https://stackoverflow.com/a/246128/3180795
    local resolve_file="$1" description="$2" 
    local link_target directory_name filename resolve_dir_name 
    debug "Getting directory for '$resolve_file'."
    #  resolve $resolve_file until it is no longer a symlink
    while [[ -h "$resolve_file" ]]; do 
      link_target="$(readlink "$resolve_file")"
      if [[ $link_target == /* ]]; then
        debug "File '$resolve_file' is an absolute symlink to '$link_target'"
        resolve_file="$link_target"
      else
        directory_name="$(dirname "$resolve_file")" 
        debug "File '$resolve_file' is a relative symlink to '$link_target' (relative to '$directory_name')"
        #  If $resolve_file was a relative symlink, we need to resolve 
        #+ it relative to the path where the symlink file was located
        resolve_file="$directory_name/$link_target"
      fi
    done
    debug "File is '$resolve_file'" 
    filename="$(basename "$resolve_file")"
    debug "File name is '$filename'"
    resolve_dir_name="$(dirname "$resolve_file")"
    directory_name="$(cd -P "$(dirname "$resolve_file")" && pwd)"
    if [[ "$directory_name" != "$resolve_dir_name" ]]; then
      debug "$description '$directory_name' resolves to '$directory_name'."
    fi
    debug "$description is '$directory_name'"
    if [[ -z $directory_name ]] ; then
      directory_name="."
    fi
    echo "$directory_name/$filename"
}

get_absolute_filename ()
{
    # Returns only the filename
    local resolve_file="$1" description="$2" return_filename
    return_filename=$(get_absolute_location "$resolve_file" "$description")
    return_filename=${return_filename##*/}
    echo "$return_filename"
}

get_absolute_dirname ()
{
    # Returns only the directory
    local resolve_file="$1" description="$2" return_dirname
    return_dirname=$(get_absolute_location "$resolve_file" "$description")
    return_dirname=${return_dirname%/*}
    echo "$return_dirname"
}

get_scriptpath_and_source_files ()
{
    local error_count tmplog line
    tmplog=$(mktemp tmp.XXXXXXXX) 
    # Who are we and where are we?
    scriptname="$(get_absolute_filename "${BASH_SOURCE[0]}" "installname")"
    debug "Script is called '$scriptname'"
    # remove scripting ending (if present)
    scriptbasename=${scriptname%.sh} 
    debug "Base name of the script is '$scriptbasename'"
    scriptpath="$(get_absolute_dirname  "${BASH_SOURCE[0]}" "installdirectory")"
    debug "Script is located in '$scriptpath'"
    resourcespath="$scriptpath/resources"
    
    if [[ -d "$resourcespath" ]] ; then
      debug "Found library in '$resourcespath'."
    else
      (( error_count++ ))
    fi
    
    # Import default variables
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/default_variables.sh
    source "$resourcespath/default_variables.sh" &> "$tmplog" || (( error_count++ ))
    
    # Set more default variables
    exit_status=0
    stay_quiet=0
    # Ensure that in/outputfile variables are empty
    unset inputfile
    unset outputfile
    
    # Import other functions
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/messaging.sh
    source "$resourcespath/messaging.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/rcfiles.sh
    source "$resourcespath/rcfiles.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/test_files.sh
    source "$resourcespath/test_files.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/process_orca.sh
    source "$resourcespath/process_orca.sh" &> "$tmplog" || (( error_count++ ))
    #shellcheck source=/home/te768755/devel/tools-for-orca.bash/resources/validate_numbers.sh
    source "$resourcespath/validate_numbers.sh" &> "$tmplog" || (( error_count++ ))

    if (( error_count > 0 )) ; then
      echo "ERROR: Unable to locate library functions. Check installation." >&2
      echo "ERROR: Expect functions in '$resourcespath'."
      debug "Errors caused by:"
      while read -r line || [[ -n "$line" ]] ; do
        debug "$line"
      done < "$tmplog"
      debug "$(rm -v -- "$tmplog")"
      exit 1
    else
      debug "$(rm -v -- "$tmplog")"
    fi
}

#
# Specific functions for this script only
#

process_inputfile ()
{
    local testfile="$1"
    debug "Processing Input: $testfile"
    validate_write_in_out_jobname "$testfile" || fatal "Unable to parse '$testfile'"
    debug "Jobname: $jobname; Input: $inputfile; Output: $outputfile."

    read_orca_input_file "$inputfile"
    debug "Depends on $( printf "%s, " "${inputfile_dependon[@]}" )"
    inputfile_modified="$jobname.inp"
    backup_if_exists "$inputfile_modified"
    debug "Writing new input: $inputfile_modified"

    write_orca_input_file > "$inputfile_modified"
    message "Written modified inputfile '$inputfile_modified'."
}

#
# Routine(s) for writing the submission script
#

write_jobscript ()
{
    debug "Creating a job script."
    local queue="$1" queue_short 
    [[ -z $queue ]] && fatal "No queueing systen selected. Abort."
    queue_short="${queue%-*}"
    submitscript="${jobname}.${queue_short}.bash"
    debug "Selected queue: $queue; short: $queue_short"
    debug "Will write submitscript to: $submitscript"

    if [[ -e $submitscript ]] ; then
      warning "Designated submitscript '$submitscript' already exists."
      warning "File will be overwritten."
      # Backup or delete, or overwrite?
    fi
    [[ -z $inputfile_modified ]]   && fatal "No inputfile specified. Abort."
    [[ -z $outputfile ]]  && fatal "No outputfile selected. Abort."

    # Open file descriptor 9 for writing
    exec 9> "$submitscript"

    local scale_memory_percent overhead_memory
    # Give ORCA some more space by default (define in rc), 
    # scale everything up, so that orca uses max 75% of memory
    scale_memory_percent=$(( 75 ))
    debug "Scaling memory by ${scale_memory_percent}% (requested_numCPU=${requested_numCPU})."
    overhead_memory=$(( (requested_memory + orca_overhead) * 100 / scale_memory_percent ))
    debug "requested_memory=$requested_memory; orca_overhead=$orca_overhead"
    message "Request a total memory of $overhead_memory MB, including overhead for ORCA."

    # Write the shebang and a origin message
    echo "#!/usr/bin/env bash" >&9
    echo "# Submission script automatically created with $scriptname ($version, $versiondate)" >&9

    # Header is different for the queueing systems
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      cat >&9 <<-EOF
			#PBS -l nodes=1:ppn=$requested_numCPU
			#PBS -l mem=${overhead_memory}m
			#PBS -l walltime=$requested_walltime
			#PBS -N ${jobname}
			#PBS -m ae
			#PBS -o $submitscript.o\${PBS_JOBID%%.*}
			#PBS -e $submitscript.e\${PBS_JOBID%%.*}
			EOF
      if [[ -n $dependency ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' 
        # which should be recognised by PBS
        echo "#PBS -W depend=afterok$dependency" >&9
      fi
      echo "jobid=\"\${PBS_JOBID%%.*}\"" >&9

    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      cat >&9 <<-EOF
			#BSUB -n $requested_numCPU
			#BSUB -M $overhead_memory
			#BSUB -W ${requested_walltime%:*}
			#BSUB -J ${jobname}
			#BSUB -N 
			#BSUB -o $submitscript.o%J
			#BSUB -e $submitscript.e%J
			EOF
      if [[ -n $dependency ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' (PBS)
        # and needs to be transformed to LSF compatible format
        debug "Resolving dependencies from '$dependency'"
        local resolve_dependency remove_dependency
        while [[ $dependency: =~ :([[:digit:]]+): ]]; do
          if [[ -z $resolve_dependency ]] ; then
            resolve_dependency="done(${BASH_REMATCH[1]})"
            remove_dependency=":${BASH_REMATCH[1]}"
            dependency="${dependency/$remove_dependency}"
          else
            resolve_dependency="$resolve_dependency && done(${BASH_REMATCH[1]})"
            remove_dependency=":${BASH_REMATCH[1]}"
            dependency="${dependency/$remove_dependency}"
          fi
        done
        echo "#BSUB -w \"$resolve_dependency\"" >&9
      fi
      # Possibly an RWTH cluster specific setting
      if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then 
			  echo "#BSUB -a openmp" >&9
        if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
          echo "#BSUB -R select[hpcwork]" >&9
        fi
        if [[ "$qsys_project" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
          warning "No project selected."
        else
          echo "#BSUB -P $qsys_project" >&9
        fi
      fi

      if [[ "$user_email" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        message "No email address given, notifications will be sent to system default."
      else
        echo "#BSUB -u $user_email" >&9
      fi
      echo "jobid=\"\${LSB_JOBID}\"" >&9

    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      warning "This is still in preparation"
      cat >&9 <<-EOF
			#SBATCH --job-name='${jobname}'
			#SBATCH --output='$submitscript.o%j'
			#SBATCH --error='$submitscript.e%j'
			#SBATCH --nodes=1 
			#SBATCH --ntasks=$requested_numCPU
			#SBATCH --mem-per-cpu=$(( overhead_memory / requested_numCPU ))
			#SBATCH --time=${requested_walltime}
			#SBATCH --mail-type=END,FAIL
			EOF
      if [[ "$qsys_project" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        warning "No project selected."
      else
        echo "#SBATCH --account='$qsys_project'" >&9
      fi
      if [[ -n "$dependency" ]] ; then
        # Dependency is stored in the form ':jobid:jobid:jobid' 
        # which should be recognised by SLURM (like PBS)
        echo "#SBATCH --depend=afterok$dependency" >&9
      fi
      if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
        if [[ "$PWD" =~ [Hh][Pp][Cc] ]] ; then
          echo "#SBATCH --constraint=hpcwork" >&9
        fi
        echo "#SBATCH --export=NONE" >&9
      fi
      if [[ "$user_email" =~ ^(|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$ ]] ; then
        debug "No email address given, notifications will be sent to system default."
      else
        echo "#SBATCH --mail-user=$user_email" >&9
      fi
      echo "jobid=\"\${SLURM_JOB_ID}\"" >&9
    else
      fatal "Unrecognised queueing system '$queue'."
    fi

    echo "" >&9

    # Initialise variables, insert cleanup procedure, trap cleanup
    local tempdir_pattern='^(|[Tt][Ee]?[Mm][Pp]([Dd][Ii][Rr])?|0|[Dd][Ee][Ff][Aa]?[Uu]?[Ll]?[Tt]?)$'
    debug "orca_scratch='$orca_scratch'; pattern: $tempdir_pattern"
    if [[ "$orca_scratch" =~ $tempdir_pattern ]] ; then
      debug "Pattern was found."
      #shellcheck disable=SC2016
      orca_scratch='$( mktemp --directory --tmpdir )'
    else
      debug "Pattern was not found."
    fi

    cat >&9 <<-EOF
		# Make a new scratch directory
		orca_basescratch="$orca_scratch"
		orca_subscratch="\$orca_basescratch/orcajob\$jobid"
		mkdir -vp "\$orca_subscratch" || { echo "Failed to create scratch directory" >&2 ; exit 1 ; }
		
		# Save the current directory
		submit_dir="$PWD"
		
		cleanup () {
		  # This should only trigger and produce a scratch-remainder if the calculation aborts
		  echo "Looking for files with filesize zero and delete them in '\$orca_subscratch'."
		  find "\$orca_subscratch" -type f -size 0 -exec rm -v {} \\;
		  echo "Deleting scratch '\$orca_subscratch' if empty."
		  find "\$orca_subscratch" -maxdepth 0 -empty -exec rmdir -v {} \\;
		  [[ -e "\$orca_subscratch" ]] && mv -v "\$orca_subscratch" "\$submit_dir/${jobname}.scr\$jobid"
		}
		
		trap cleanup EXIT SIGTERM
		EOF

    echo "" >&9

    # How ORCA is loaded
    if [[ "$load_modules" =~ [Tt][Rr][Uu][Ee] ]] ; then
      (( ${#orca_modules[*]} == 0 )) && fatal "No modules to load."
      if [[ -z "$load_modules_from_path" ]] ; then
        warning "MODULEPATH appears to be empty."
      else
        echo "export MODULEPATH=\"$load_modules_from_path\"" >&9
      fi
      cat >&9 <<-EOF
			module load ${orca_modules[*]} 2>&1
			# Because otherwise it would go to the error output.
			
			EOF
    else
      [[ -z "$orca_installpath" ]] && fatal "ORCA path is unset."
      [[ -e "$orca_installpath/orca" ]] || fatal "ORCA seams to not exist."
      [[ -z "$openmpi_installpath" ]] && fatal "OpenMPI path is unset."
      [[ -e "$openmpi_installpath/bin" ]] || fatal "Cannot find OpenMPI binaries."
      [[ -e "$openmpi_installpath/lib" ]] || fatal "Cannot find OpenMPI libraries."
      cat >&9 <<-EOF
			# Some shortcuts for the ORCA paths/bin
			ORCA_DIR="$orca_installpath"
			ORCA_BIN="\$ORCA_DIR/orca"
			PATH="\$ORCA_DIR:\$PATH"
			# Some shortcuts for OpenMPI stuff
			MPI_ROOT="$openmpi_installpath"
			MPI_BINDIR="\$MPI_ROOT/bin"
			MPI_LIBDIR="\$MPI_ROOT/lib"
			PATH="\$MPI_BINDIR:\$PATH"
			LD_LIBRARY_PATH="\$MPI_LIBDIR:\$LD_LIBRARY_PATH"
			
			export ORCA_DIR ORCA_BIN MPI_ROOT MPI_BINDIR MPI_LIBDIR PATH LD_LIBRARY_PATH
			
			EOF
    fi

    # NBO6 ?

    # Some of the body is the same for all queues (so far)
    cat >&9 <<-EOF
		# Get some information o the platform
		echo "This is \$(uname -n)"
		echo "OS \$(uname -o) (\$(uname -p))"
		echo "Running on $requested_numCPU \$(grep 'model name' /proc/cpuinfo|uniq|cut -d ':' -f 2)."
		echo "Calculation $inputfile_modified from \$submit_dir."
		echo "Working directry is \$orca_subscratch"
		
		pushd "\$orca_subscratch" || exit 1
		
		# Move the relevant files to the scratch directory
		echo "Move input file(s) to scratch"
		mv -v "\$submit_dir/$inputfile_modified" .
		EOF
    local file
    for file in "${inputfile_dependon[@]}" ; do
      debug "Writing for '$file'."
      echo "cp -va \"\$submit_dir/$file\" ." >&9
    done

    # Needs to parse the input file find dependent files and copy those back
    # currently it relies too much on the fact that there might be a file that is needed
    # this can lead to awful errors ...

    # Insert additional environment variables
    if [[ -n "$manual_env_var" ]]; then
      echo "export $manual_env_var" >&9
      debug "export $manual_env_var"
    fi

    cat >&9 <<-EOF

		echo "Start: \$(date)"
		echo "\"\$ORCA_BIN\" \"$inputfile_modified\" > \"\$submit_dir/$outputfile\""
		# Verify orca executable
		command -v "\$ORCA_BIN" || { echo "Command not found: \$ORCA_BIN" ; exit 1 ; }
		"\$ORCA_BIN" "$inputfile_modified" > "\$submit_dir/$outputfile"
		joberror=\$?
		echo "Written '\$( ls "\$submit_dir/$outputfile" )'"
		echo "End  : \$(date)"
		echo "Current content of scratch directory:"
		ls -la
		
		echo "Remove temporary files if present."
		find . -name '*.tmp' -exec rm -v {} \\;
		find . -name 'tmp.*' -exec rm -v {} \\;
		echo "Move back remaining files (make backups)."
		find . -type f -size +0 -exec mv -v --backup=existing {} "\$submit_dir" \\;
		
		popd || exit 1
		
		echo "Current content of submit directory:"
		ls -la
		
		exit \$joberror
		EOF
    # This is very, very conservative thinking to prevent any unnecessary loss of data.
    #This should be adjusted with more care.

    # Close file descriptor
    exec 9>&-
    message "Written submission script '$submitscript'."
    return 0
}

submit_jobscript_hold ()
{
    local queue="$1" submit_id submit_message
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      submit_id="$(qsub -h "$submitscript")" || exit_status="$?"
      submit_message="
        Submitted as $submit_id.
        Use 'qrls $submit_id' to release the job."
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      submit_message="$(bsub -H < "$submitscript" 2>&1 )" || exit_status="$?"
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      submit_message="$( sbatch -H "$submitscript" 2>&1 )" || exit_status="$?"
    fi
    (( exit_status > 0 )) && warning "Submission went wrong."
    message "$submit_message"
    if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
      warning "Releasing the job might not be possible on RWTH cluster."
    fi
    return $exit_status
}

submit_jobscript_keep ()
{
    local queue="$1" 
    message "Created submit script, use"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      message "  qsub $submitscript"
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      message "  bsub < $submitscript"
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      message "sbatch $submitscript"
    fi
    message "to start the job."
}

submit_jobscript_run  ()
{
    local queue="$1" submit_message
    debug "queue=$queue; submitscript=$submitscript"
    if [[ "$queue" =~ [Pp][Bb][Ss] ]] ; then
      submit_message="Submitted as $( qsub "$submitscript" )" || exit_status="$?"
    elif [[ "$queue" =~ [Bb][Ss][Uu][Bb] ]] ; then
      submit_message="$( bsub < "$submitscript" 2>&1 )" || exit_status="$?"
    elif [[ "$queue" =~ [Ss][Ll][Uu][Rr][Mm] ]] ; then
      submit_message="$( sbatch "$submitscript" 2>&1 )" || exit_status="$?"
    else
      fatal "Unrecognised queueing system '$queue'."
    fi
    (( exit_status > 0 )) && warning "Submission went wrong."
    message "$submit_message"
    return $exit_status
}

submit_jobscript ()
{
    local queue="$1" submit_status="$2" 
    debug "queue=$queue; submit_status=$submit_status"
    case "$submit_status" in
    
      [Hh][Oo][Ll][Dd]) 
        submit_jobscript_hold "$queue" || return $?
        ;;
    
      [Kk][Ee][Ee][Pp]) 
        submit_jobscript_keep "$queue" || return $?
        ;;
    
      [Rr][Uu][Nn])
        submit_jobscript_run  "$queue" || return $?
        ;;
    
      *)  
        fatal "Unrecognised status '$submit_status' requested for the job."
        ;;

    esac
}

#
# Process Options
#

process_options ()
{
  ##Needs complete rework

    #hlp   Options:
    #hlp    
    local OPTIND=1 

    while getopts :m:p:d:w:e:j:Hkq:Q:P:u:sh options ; do
        case $options in

          #hlp     -m <ARG> Define the total memory to be used in megabyte.
          #hlp              The total request will be larger to account for 
          #hlp              overhead which ORCA may need. (Default: 512)
          #hlp
            m) 
               validate_integer "$OPTARG" "the memory"
               if (( OPTARG == 0 )) ; then
                 fatal "Memory limit must not be zero."
               fi
               requested_memory="$OPTARG" 
               ;;

          #hlp     -p <ARG> Define number of professors to be used. (Default: 4)
          #hlp
            p) 
               validate_integer "$OPTARG" "the number of threads"
               if (( OPTARG == 0 )) ; then
                 fatal "Number of threads must not be zero."
               fi
               requested_numCPU="$OPTARG" 
               ;;

          #hlp     -d <ARG> Define disksize (MB). --- TODO ---
          #hlp              This option does not set a parameter for the queueing system,
          #hlp              but will/should only modify the input file with the size specification.
          #hlp              
            d) 
               validate_integer "$OPTARG" "the disksize"
               if (( OPTARG == 0 )) ; then
                 fatal "The disksize must not be zero."
               fi
               requested_maxdisk="$OPTARG"
               ;;

          #hlp     -w <ARG> Define maximum walltime.
          #hlp                Format: [[HH:]MM:]SS (Default: $requested_walltime)
          #hlp
            w) requested_walltime=$(format_duration_or_exit "$OPTARG")
               ;;

          #hlp     -e <ARG> Specify environment variable to be passed on.
          #hlp              This will be inserted after modules and other variables are written.
          #hlp              Input should have the form 'VARIABLE=<value>'.
          #hlp                (No sanity check will be performed, 
          #hlp                 may be specified multiple times.)
          #hlp
            e) 
               manual_env_var="$OPTARG $manual_env_var"
               ;;

          #hlp     -j <ARG> Wait for job with ID <ARG> (strictly numeric) to be done.
          #hlp              Option may be specified multiple times.
          #hlp              (BSUB) Implemented is only the use of the job ID.
          #hlp
            j) 
               validate_integer "$OPTARG" "the job ID"
               dependency="$dependency:$OPTARG"
               ;;

          #hlp     -H       submit the job with status hold (PBS, SLURM) or PSUSP (BSUB)
          #hlp
            H) 
               requested_submit_status="hold"
               if [[ "$queue" =~ [Rr][Ww][Tt][Hh] ]] ; then
                 warning "(RWTH) Current permissions of 'bresume' prevent releasing the job."
               fi 
               ;;

          #hlp     -k       Only create (keep) the jobscript, do not submit it.
          #hlp
            k) 
               requested_submit_status="keep"
               ;;

          #hlp     -q       submit to queue --TODO--
          #hlp              
            q) warning "The submission to a specific queue is not yet possible." ;;

          #hlp     -Q <ARG> Which type of job script should be produced.
          #hlp              Arguments currently implemented: pbs-gen, slurm-gen, slurm-rwth, bsub-gen, bsub-rwth
          #hlp
            Q) request_qsys="$OPTARG" ;;

          #hlp     -P <ARG> Account (SLURM) or Project (BSUB) for statistics.
          #hlp              If the argument is 'default', '0', or '', it reverts to system settings.
          #hlp
            P) 
               qsys_project="$OPTARG"
               ;;

          #hlp     -u <ARG> Set user email address. This is also a BSUB specific setting.
          #hlp              In other queueing systems it just won't be used.
          #hlp              If the argument is 'default', '0', or '', it reverts to system settings.
          #hlp
            u) 
               user_email=$(validate_email "$OPTARG")
               ;;

          #hlp     -s       Suppress logging messages of the script.
          #hlp              (May be specified multiple times.)
          #hlp
            s) (( stay_quiet++ )) ;;

          #hlp     -h       this help.
          #hlp
            h) helpme ;;

           \?) fatal "Invalid option: -$OPTARG." ;;

            :) fatal "Option -$OPTARG requires an argument." ;;

        esac
    done

    # Shift all variables processed to far
    shift $((OPTIND-1))

    if [[ -z "$1" ]] ; then 
      fatal "There is no inputfile specified"
    fi

    # The test whether the file exists or not will be done 
    # when extracting more information
    requested_inputfile="$1"
    shift
    debug "Specified input: $requested_inputfile"

    # Issue a warning that the addidtional flag has no effect.
    warn_additional_args "$@"
}

#
# MAIN SCRIPT
#

# If this script is not sourced, return before executing anything
if (return 0 2>/dev/null) ; then
  # [How to detect if a script is being sourced](https://stackoverflow.com/a/28776166/3180795)
  echo "This script is not meant to be sourced; skipping execution."
fi

# Save how script was called
script_invocation_spell="$0 $*"

# Sent logging information to stdout
exec 3>&1

# Need to define debug function if unknown
if ! command -v debug ; then
  debug () {
    echo "DEBUG  : " "$*" >&4
  }
fi

# Secret debugging switch
if [[ "$1" == "debug" ]] ; then
  exec 4>&1
  stay_quiet=0 
  shift 
else
  exec 4> /dev/null
fi

get_scriptpath_and_source_files || exit 1

if [[ "$1" =~ ^[Ll][Ii][Cc][Ee][Nn][Ss][Ee]$ ]] ; then
  [[ -r "$scriptpath/LICENSE" ]] || fatal "No license file found. Your copy of the repository might be corrupted."
  if command -v less &> /dev/null ; then
    less "$scriptpath/LICENSE"
  else
    cat "$scriptpath/LICENSE"
  fi
  message "Displayed license and will exit."
  exit 0
fi

# Check for settings in three default locations (increasing priority):
#   install path of the script, user's home directory, current directory
orca_tools_rc_loc="$(get_rc "$scriptpath" "/home/$USER" "/home/$USER/.config" "$PWD")"
debug "orca_tools_rc_loc=$orca_tools_rc_loc"

# Load custom settings from the rc

if [[ ! -z $orca_tools_rc_loc ]] ; then
  #shellcheck source=/home/te768755/devel/tools-for-orca.bash/orca.tools.rc 
  . "$orca_tools_rc_loc"
  message "Configuration file '$orca_tools_rc_loc' applied."
else
  debug "No custom settings found."
fi

# Evaluate Options

process_options "$@"
process_inputfile "$requested_inputfile"
write_jobscript "$request_qsys"
submit_jobscript "$request_qsys" "$requested_submit_status" 

#hlp   $scriptname is part of $softwarename $version ($versiondate) 
message "$scriptname is part of $softwarename $version ($versiondate)"
debug "$script_invocation_spell"

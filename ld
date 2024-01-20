#!/bin/bash

print_error() {
	printf "\e[41mERR!\e[0m %s\n" "$1"
}

print_warn() {
	printf "\e[103;30mWARN\e[0m %s\n" "$1"
}

print_success() {
	printf "\e[48;5;28mDONE\e[0m %s\n" "$1"
}

print_bold() {
	printf "\e[1m%s\e[0m\n" "$1"
}

get_flag_status() {
	flag_status_result=$(curl -s --fail-with-body -w 'HTTP_CODE_IDENTIFIER%{http_code}' "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
                        -H "Authorization: $ld_api_key"
        )
#	flag_status_result_with_http_code=$(read -r -d "HTTP_CODE_IDENTIFIER" <<< "$flag_status_result_with_http_code")
#	flag_status_result=${flag_status_result_with_http_code[0]}
#	flag_status_result_code=${flag_status_result_with_http_code[1]}
#
#
#	echo "CODE $flag_status_result_code"
	echo "RESULT $flag_status_result"

	flag_status=$(jq ".environments.$ld_current_environment.on" <<< "$flag_status_result")

	if [[ -z $flag_status ]]; then

		print_error "Failed to get the status of '$flag_key' in '$ld_current_environment'."

		if [[ $status_code -eq 404 ]]; then
			print_error "404: Flag '$flag_key' does not exist."
		else
			print_error "401: You possibly did not pass an API key in the config file or it expired."
		fi
		exit 1
	fi
}

show_status_output() {
	status=$1
	showOutput=$2

	if [[ $showOutput == 'true' ]]; then
		if [[ $silent_flag != 'true' ]]; then
			print_success "Status for '$flag_key' in '$ld_current_environment' is '$status'."
		else
			echo "$status"
		fi
	fi
}

print_commands() {
  echo
  print_bold "> LAUNCH DARKLY COMMANDS"
  echo
  echo "> ld toggle (flag_key) [true/false] [-e] [-s] - Turn a flag on/off."
  echo "> ld status (flag_key) [-e] [-s] - Get the on/off status of a feature flag."
  echo
}

check_connection_status() {
	TEST_CONNECTION=$(curl -s "https://google.com")

  if [[ $? -eq 6 ]]; then # The connection could not complete.
  	print_error "Connection does not exist. Unable to process any commands until connection"
  	print_error "is online."
  	exit 1
  fi
}


# Flags/Parameters
env_flag=''
silent_flag='false'
edit_enabled_flag='false'
edit_disabled_flag='false'
command=''
flag_key=''
flag_value=''

command=$1

script_args=()

while [ $OPTIND -le "$#" ]
do
		if getopts e:s option
		then
				case $option
				in
					e) env_flag="$OPTARG";;
					s) silent_flag='true';;
					*) exit 1 # Ensure that code does not run.
				esac
		else
				script_args+=("${!OPTIND}")
				((OPTIND++))
		fi
done

command=${script_args[0]}
flag_key=${script_args[1]}

# API Configurations
ld_default_environment=$(jq -r ".configurations.defaultEnvKey" "config.json")

if [[ "$ld_default_environment" == "null" ]]; then
	ld_default_environment="test"
fi

ld_current_environment=${env_flag:-$ld_default_environment}
ld_api_key=$(jq -r ".configurations.accessToken" "config.json")

key_length=${#ld_api_key}

if [[ $ld_api_key == "null" || $key_length -lt 40 || $key_length -gt 40 ]]; then
	print_error "unrecognized_token: The token provided in configurations/accessToken doesn't seem to be valid. Please be sure that the token you provided is from Launch Darkly. If you don't have one, follow the guide here to create one: https://docs.launchdarkly.com/home/account-security/api-access-tokens#creating-api-access-tokens" 
	exit 1
fi

if [[ $# -eq 0 ]]; then
  print_commands
  exit 0
fi

if [[ $command == "toggle" ]]; then

	if [[ -z $flag_key ]]; then
		echo
		print_bold "Syntax: ld toggle (flag_key) [true/false] [-e] [-s]"
		echo
		echo "where:"
		echo "      flag_key - The key/id of the flag."
		echo "      true/false - The state of whether or not the flag is on or off."
		echo "      -e - The environment where the flag is located. Will default to default environment in config if none is passed."
		echo "			-s - Runs the command in 'silent mode', which will only output the value of flag and not the entire message."
		echo
	else
		check_connection_status

		flag_value=${script_args[2]}

		if [[ -z $flag_value ]]; then
			get_flag_status
			# It's weird, but after the function executes then Bash can access $flag_status outside of the function.
			if [[ $flag_status == 'true' ]]; then
				flag_value='false'
			else
				flag_value='true'
			fi
		fi


		patch_request_result=$(curl --fail-with-body -s -X PATCH \
				"https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
				-H "Authorization: $ld_api_key" \
				-H 'Content-Type: application/json' \
				-d @- << JSON
						[
							{
								"op": "replace",
								"path": "/environments/$ld_current_environment/on",
								"value": $flag_value
							}
						]
JSON
)

	echo $ld_current_environment
		final_flag_result=$(jq ".environments.$ld_current_environment.on" <<< "$patch_request_result")

		if [[ $final_flag_result == "$flag_value" ]]; then
			if [[ $silent_flag != 'true' ]]; then
				print_success "Flag '$flag_key' in environment '$ld_current_environment' now has value $flag_value."
			else
				echo "$final_flag_result"
			fi
		else
			code=$(jq -r ".code" <<< "$patch_request_result")
			message=$(jq ".message" <<< "$patch_request_result")
			print_error "There was a problem trying to update the flag value."

			jq <<< "$patch_request_result"

			if [[ $code == "not_found" ]]; then
				print_error "$code: Flag '$flag_key' does not exist."
			elif [[ $code == "invalid_request" || $code == "invalid_patch" ]]; then
				print_error "$code: You most likely entered an invalid value for either the flag value or the environment (if you passed a flag)."
			elif [[ $code == "unauthorized" ]]; then
				print_error "$code: The token you provided is either invalid or expired. Please correct this."
			else
				echo "$patch_request_result"
				print_error "Bad Request: $code: $message"
				# add debug flag that prints extra output if supplied -d
				# if debug is enabled do the following
				# if code is empty, or message is empty, output full patch_request_result
				print_warn "If there is no error output, please report the steps you took to encounter this error on the GitHub via https://github.com/MarkE16/LaunchDarklyCLI"
			fi
		fi
	fi

elif [[ $command == "status" ]]; then
	if [[ -z $flag_key ]]; then
		echo
		print_bold "Syntax: ld status (flag_key) [-e] [-s]"
		echo
		echo "where:"
		echo "      flag_key - The key/id of the flag."
		echo "      -e - The environment where the flag is located. Will default to default environment in config if none is passed."
		echo "			-s - Runs the command in 'silent mode', which will only output the value of flag and not the entire message."
		echo
	else
		check_connection_status
		get_flag_status
		show_status_output "$flag_status" 'true'
	fi
elif [[ $command == 'edit' ]]; then
	check_connection_status
#	RESPONSE=$(curl -X PATCH \
#               "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
#               -H "Authorization: $ld_api_key" \
#               -H 'Content-Type: application/json' \
#               -d @- << JSON
#                 [
#                   {
#                     "op": "replace",
#                     "path": "",
#                     "value": "AWESOME!!!"
#                   }
#                 ]
#JSON
#)
#	jq <<< "$RESPONSE"
else
	print_error "Invalid command."
	print_commands
fi


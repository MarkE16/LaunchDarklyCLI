#!/bin/bash

env_flag=''
silent_flag='false'
edit_enabled_flag='false'
edit_disabled_flag='false'
command=''
flag_key=''
flag_value=''

get_flag_status() {
	flag_status_result=$(curl -s "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
                        -H "Authorization: $ld_api_key"
        )

	flag_status=$(jq ".environments.$ld_current_environment.on" <<< "$flag_status_result")

	if [[ -z $flag_status ]]; then
		status_code=$(curl -s -I -o /dev/null -w '%{http_code}' "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
                                                                                    -H "Authorization: $ld_api_key"
		)

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

print_error() {
	printf "\e[41mERR!\e[0m %s\n" "$1"
}

print_success() {
	printf "\e[48;5;28mDONE\e[0m %s\n" "$1"
}

print_bold() {
	printf "\e[1m%s\e[0m\n" "$1"
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

if [[ $# -eq 0 ]]; then
  print_commands
  exit 0
fi

command=$1
ld_default_environment=$(jq -r ".configuration.defaultEnvKey" "config.json")

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

# Weird syntax, but apparently Bash knows what parameter is used even though you don't use the syntax "$4".
# Just a guess, but maybe it's because it's in a variable substitution block? Though it doesn't make sense as to
# the fact that I have to include a $ for LD_DEFAULT_ENVIRONMENT.
ld_current_environment=${env_flag:-$LD_DEFAULT_ENVIRONMENT}
ld_api_key=$(jq -r ".configuration.accountPAT" "config.json")

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
			if [[ $flag_status == 'true' ]]; then
				flag_value='false'
			else
				flag_value='true'
			fi
		fi


		CURL_RESULT=$(curl -s -X PATCH \
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
		final_flag_result=$(jq ".environments.$ld_current_environment.on" <<< "$CURL_RESULT")

		if [[ $final_flag_result == "$flag_value" ]]; then
			if [[ $silent_flag != 'true' ]]; then
				print_success "Flag '$flag_key' in environment '$ld_current_environment' now has value $flag_value."
			else
				echo "$final_flag_result"
			fi
		else
			status_code=$(curl -s -I -o /dev/null -w '%{http_code}' \
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
			print_error "There was a problem trying to update the flag value."

			echo "CODE: $status_code"

			if [[ $status_code -eq 404 ]]; then
				print_error "404: Flag '$flag_key' does not exist."
			elif [[ $status_code -eq 405 ]]; then
				print_error "405: You are not authorized to complete this action. Contact @MarkE16 via GitHub if you think this is a problem."
			elif [[ $status_code -eq 401 ]]; then
				print_error "401: You possibly did not pass an API key in the config file or it expired."
			else
				print_error "400: Bad Request. This could mean anything."
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


#!/bin/bash

env_flag=''
silent_flag='false'
edit_enabled_flag='false'
edit_disabled_flag='false'
command=''
flag_key=''
flag_value=''

get_flag_status() {
	FLAG_STATUS_RESULT=$(curl -s "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
                        -H "Authorization: $LD_API_KEY"
        )

	FLAG_STATUS=$(jq ".environments.$LD_CURRENT_ENVIRONMENT.on" <<< "$FLAG_STATUS_RESULT")
	echo "debug FLAG_STATUS: '$FLAG_STATUS'" >&2

	if [[ -z $FLAG_STATUS ]]; then
		print_error "Failed to get the status of '$flag_key' in '$LD_CURRENT_ENVIRONMENT'."
		echo "debug raw error json: '$FLAG_STATUS_RESULT'" >&2 # debug raw error json
#		ERROR_MESSAGE=$(jq ".message" <<< "$FLAG_STATUS_RESULT")
		exit 1
	fi


	echo "$FLAG_STATUS" # return
}

show_status_output() {
	status=$1
	showOutput=$2

	if [[ $showOutput == 'true' ]]; then
		if [[ $silent_flag != 'true' ]]; then
			print_success "Status for '$flag_key' in '$LD_CURRENT_ENVIRONMENT' is '$status'."
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

if [[ $# -eq 0 ]]; then
  print_commands
  exit 0
fi

command=$1
LD_DEFAULT_ENVIRONMENT=$(jq -r ".configuration.defaultEnvKey" "config.json")

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
LD_CURRENT_ENVIRONMENT=${env_flag:-$LD_DEFAULT_ENVIRONMENT}
LD_API_KEY=$(jq -r ".configuration.accountPAT" "config.json")

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

		flag_value=${script_args[2]}

		if [[ -z $flag_value ]]; then
			CURRENT_STATUS=$(get_flag_status)
			if [[ $CURRENT_STATUS == 'true' ]]; then
				flag_value='false'
			else
				flag_value='true'
			fi
		fi


		CURL_RESULT=$(curl -s -X PATCH \
				"https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
				-H "Authorization: $LD_API_KEY" \
				-H 'Content-Type: application/json' \
				-d @- << JSON
						[
							{
								"op": "replace",
								"path": "/environments/$LD_CURRENT_ENVIRONMENT/on",
								"value": $flag_value
							}
						]
JSON
)
		FINAL_FLAG_RESULT=$(jq ".environments.$LD_CURRENT_ENVIRONMENT.on" <<< "$CURL_RESULT")

		if [[ $FINAL_FLAG_RESULT == "$flag_value" ]]; then
			if [[ $silent_flag != 'true' ]]; then
				print_success "Flag '$flag_key' in environment '$LD_CURRENT_ENVIRONMENT' now has value $flag_value."
			else
				echo "$FINAL_FLAG_RESULT"
			fi
		else
			print_error "There was a problem trying to update the flag value."
			echo "Error: $(jq ".message" <<< "$CURL_RESULT")"
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
		status=$(get_flag_status)
		echo "163 $status"
		if [ "$status" -eq 1 ]; then
			exit 1
		fi
		show_status_output "$status" 'true'
	fi
elif [[ $command == 'edit' ]]; then
	RESPONSE=$(curl -X PATCH \
               "https://app.launchdarkly.com/api/v2/flags/default/$flag_key" \
               -H "Authorization: $LD_API_KEY" \
               -H 'Content-Type: application/json' \
               -d @- << JSON
                 [
                   {
                     "op": "replace",
                     "path": "",
                     "value": "AWESOME!!!"
                   }
                 ]
JSON
)
	jq <<< "$RESPONSE"
else
	print_error "Invalid command."
	print_commands
fi


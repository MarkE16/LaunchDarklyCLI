#!/bin/bash

print_commands() {
  echo
  echo "LAUNCH DARKLY COMMANDS"
  echo
  echo "- ld toggle [flag_key] [true/false] [environment?] - Turn a flag on/off"
  echo "- ld status [flag_key] [environment?] - Get the status of a feature flag."
  echo
}

if [[ $# -eq 0 ]]; then
  print_commands
else

  LD_ACTION=$1
  LD_DEFAULT_ENVIRONMENT=$(jq -r ".configuration.defaultEnvKey" "config.json")

  # Weird syntax, but apparently Bash knows what parameter is used even though you don't use the syntax "$4".
  # Just a guess, but maybe it's because it's in a variable substitution block? Though it doesn't make sense as to
  # the fact that I have to include a $ for LD_DEFAULT_ENVIRONMENT.
  LD_CURRENT_ENVIRONMENT=${4:-$LD_DEFAULT_ENVIRONMENT}
  LD_FLAG_KEY=$2
  LD_API_KEY=$(jq -r ".configuration.accountPAT" "config.json")

  if [[ $LD_ACTION == "toggle" ]]; then
    LD_NEW_FLAG_VALUE=$3

    if [[ -z $LD_FLAG_KEY || -z $LD_NEW_FLAG_VALUE ]]; then
      echo "Insignificant amount of arguments provided."
      echo
      echo "Syntax: ld toggle [flag_key] [true/false] [environment?]"
      echo
      echo "where:"
      echo "      - flag_key - The key/id of the flag."
      echo "      - true/false - The state of whether or not the flag is on or off."
      echo "      - environment? (optional) - The environment where the flag is stored. Will default to default environment in config if none is passed."
      echo
    else
      
      CURL_RESULT=$(curl -s -X PATCH \
          "https://app.launchdarkly.com/api/v2/flags/default/$LD_FLAG_KEY" \
          -H "Authorization: $LD_API_KEY" \
          -H 'Content-Type: application/json' \
          -d @- << JSON
              [
                {
                  "op": "replace",
                  "path": "/environments/$LD_CURRENT_ENVIRONMENT/on",
                  "value": $3
                }
              ]
JSON
)
      FINAL_FLAG_RESULT=$(jq ".environments.$LD_CURRENT_ENVIRONMENT.on" <<< "$CURL_RESULT")

      if [[ "$FINAL_FLAG_RESULT" == "$LD_NEW_FLAG_VALUE" ]]; then
        echo "[DONE] Flag '$LD_FLAG_KEY' in environment '$LD_CURRENT_ENVIRONMENT' now has value $LD_NEW_FLAG_VALUE."
      else
        echo "[FAILURE] There was a problem trying to update the flag value."
        echo "Error: $(jq ".message" <<< "$CURL_RESULT")"
      fi
    fi
  elif [[ $LD_ACTION == "status" ]]; then
    if [[ -z $LD_FLAG_KEY ]]; then
      echo
      echo "Syntax: ld flag_status [flag_key] [environment?]"
      echo
      echo "where:"
      echo "      - flag_key - The key/id of the flag."
      echo "      - environment? (optional) - The environment where the flag is located. Will default to default environment in config if none is passed."
      echo
    else
      FLAG_STATUS_RESULT=$(curl "https://app.launchdarkly.com/api/v2/flags/default/$LD_FLAG_KEY" \
                      -H "Authorization: $LD_API_KEY"
      )

      jq <<< "$FLAG_STATUS_RESULT"
      FLAG_STATUS=$(jq ".environments.$LD_CURRENT_ENVIRONMENT.on" <<< "$FLAG_STATUS_RESULT")

      echo $FLAG_STATUS

      if [[ -z $FLAG_STATUS ]]; then
       echo "[FAILURE] Failed to get the status of '$LD_FLAG_KEY' in '$LD_CURRENT_ENVIRONMENT'."
       echo "Error: $(jq ".message" <<< "$FLAG_STATUS_RESULT")"
      else
       echo "[DONE] Status for $LD_FLAG_KEY in $LD_CURRENT_ENVIRONMENT: $FLAG_STATUS"
      fi
   fi
  else
    print_commands
  fi
fi
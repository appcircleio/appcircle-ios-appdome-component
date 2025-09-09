#!/bin/bash
set -e

APPDOME_APP_PATH="$AC_APPDOME_IPA_PATH"
APPDOME_API_KEY="$AC_APPDOME_API_KEY"
APPDOME_FUSION_SET_ID="$AC_APPDOME_FUSION_SET_ID"
APPDOME_TEAM_ID="$AC_APPDOME_TEAM_ID"
APPDOME_IOS_ENTITLEMENT="$AC_APPDOME_IOS_ENTITLEMENTS"
APPDOME_PROVISION_PROFILE="$AC_APPDOME_PROVISIONING_PROFILES"
APPDOME_CERTIFICATES="$AC_APPDOME_CERTIFICATES"
APPDOME_CERTIFICATE_PASS="$AC_APPDOME_CERTIFICATES_PASS"
APPDOME_SIGN_METHOD="$AC_APPDOME_SIGN_METHOD"
APPDOME_BUILD_LOGS="$AC_APPDOME_BUILD_LOGS"

download_file() {
	file_location="$1"
	uri=$(echo "$file_location" | awk -F "?" '{print $1}')
	downloaded_file=$(basename "$uri")
	curl -L "$file_location" --output "$downloaded_file" && echo "$downloaded_file"
}

if [[ "$APPDOME_APP_PATH" == *"http"* ]];
then
	app_file="../$(download_file "$APPDOME_APP_PATH")"
else
	app_file="$APPDOME_APP_PATH"
fi

certificate_output="$AC_OUTPUT_DIR/certificate.pdf"
secured_app_output="$AC_OUTPUT_DIR/Appdome_$(basename "$app_file")"

appdome_team_id=""
if [[ -n "$APPDOME_TEAM_ID" ]]; then
	appdome_team_id="--team_id ${APPDOME_TEAM_ID}"
fi

entitlement_list=""
if [[ -n "$APPDOME_IOS_ENTITLEMENT" ]]; then
	entitlement_list="--entitlements ${APPDOME_IOS_ENTITLEMENT}"
fi

provision_profile_list=$(echo "$APPDOME_PROVISION_PROFILE" | tr "|" ,)
echo "Provision Profile List: $provision_profile_list"

git clone https://github.com/Appdome/appdome-api-bash.git > /dev/null
cd appdome-api-bash

echo "iOS platform detected"

case "$APPDOME_SIGN_METHOD" in
"Private-Signing")		echo "Private Signing"						
						./appdome_api.sh --api_key "$APPDOME_API_KEY" \
							--app "$app_file" \
							--fusion_set_id "$APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--private_signing \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
"Auto-Dev-Signing")		echo "Auto Dev Signing"
						./appdome_api.sh --api_key "$APPDOME_API_KEY" \
							--app "$app_file" \
							--fusion_set_id "$APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--auto_dev_private_signing \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
"On-Appdome")			echo "On Appdome Signing"
						certificate_file="$APPDOME_CERTIFICATES"
						certificate_pass="$APPDOME_CERTIFICATE_PASS"
						./appdome_api.sh --api_key "$APPDOME_API_KEY" \
							--app "$app_file" \
							--fusion_set_id "$APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--sign_on_appdome \
							--keystore "$certificate_file" \
							--keystore_pass "$certificate_pass" \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
esac

if [[ "$secured_app_output" == *.sh ]]; then
	echo "AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH=$secured_app_output" >> "$AC_ENV_FILE_PATH"
elif [[ "$secured_app_output" == *.ipa ]]; then
	echo "AC_APPDOME_SECURED_IPA_PATH=$secured_app_output" >> "$AC_ENV_FILE_PATH"
else
	echo "Secured app output type is undefined: $secured_app_output"
fi
echo "AC_APPDOME_CERTIFICATE_PATH=$certificate_output" >> "$AC_ENV_FILE_PATH"
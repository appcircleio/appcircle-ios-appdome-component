#!/bin/bash
set -e

download_file() {
	file_location=$1
	uri=$(echo $file_location | awk -F "?" '{print $1}')
	downloaded_file=$(basename $uri)
	curl -L $file_location --output $downloaded_file && echo $downloaded_file
}

if [[ $AC_APPDOME_IPA_PATH == *"http"* ]];
then
	app_file="../$(download_file $AC_APPDOME_IPA_PATH)"
else
	app_file="$AC_APPDOME_IPA_PATH"
fi

certificate_output="$AC_OUTPUT_DIR/certificate.pdf"
secured_app_output="$AC_OUTPUT_DIR/Appdome_$(basename $app_file)"

appdome_team_id=""
if [[ -n $AC_APPDOME_TEAM_ID ]]; then
	appdome_team_id="--team_id ${AC_APPDOME_TEAM_ID}"
fi

entitlement_list=""
if [[ -n $AC_APPDOME_IOS_ENTITLEMENTS ]]; then
	entitlement_list="--entitlements ${AC_APPDOME_IOS_ENTITLEMENTS}"
fi

provision_profile_list=$(echo "$AC_APPDOME_PROVISIONING_PROFILES" | tr "|" ,)
echo "Provision Profile List: $provision_profile_list"

git clone https://github.com/Appdome/appdome-api-bash.git > /dev/null
cd appdome-api-bash

echo "iOS platform detected"

case $AC_APPDOME_SIGN_METHOD in
"Private-Signing")		echo "Private Signing"						
						./appdome_api.sh --api_key "$AC_APPDOME_API_KEY" \
							--app $app_file \
							--fusion_set_id "$AC_APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--private_signing \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
"Auto-Dev-Signing")		echo "Auto Dev Signing"
						./appdome_api.sh --api_key "$AC_APPDOME_API_KEY" \
							--app $app_file \
							--fusion_set_id "$AC_APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--auto_dev_private_signing \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
"On-Appdome")			echo "On Appdome Signing"
						keystore_file="$AC_APPDOME_CERTIFICATES"
						keystore_pass="$AC_APPDOME_CERTIFICATES_PASS"
						./appdome_api.sh --api_key "$AC_APPDOME_API_KEY" \
							--app "$app_file" \
							--fusion_set_id "$AC_APPDOME_FUSION_SET_ID" \
							$appdome_team_id \
							--sign_on_appdome \
							--keystore "$keystore_file" \
							--keystore_pass "$keystore_pass" \
							--provisioning_profiles "$provision_profile_list" \
							$entitlement_list \
							--output "$secured_app_output" \
							--certificate_output "$certificate_output" 
							
						;;
esac

if [[ "$secured_app_output" == *.sh ]]; then
	echo "AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH=$secured_app_output" >> $AC_ENV_FILE_PATH
elif [[ "$secured_app_output" == *.ipa ]]; then
	echo "AC_APPDOME_SECURED_IPA_PATH=$secured_app_output" >> $AC_ENV_FILE_PATH
else
	echo "Secured app output type is undefined: $secured_app_output"
fi
echo "AC_APPDOME_CERTIFICATE_PATH=$certificate_output" >> $AC_ENV_FILE_PATH
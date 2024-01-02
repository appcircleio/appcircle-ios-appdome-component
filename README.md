# Appcircle _Appdome-Build-2Secure for iOS_ component

Integration that allows activating security and app protection features, building and signing mobile apps using Appdome's API.

## Required Inputs

- `AC_APPDOME_IPA_PATH`: URL to app file (ipa) or an environment variable representing its path (i.e. `$AC_EXPORT_DIR/<myappname>.ipa`).
- `AC_APPDOME_API_KEY`: This API key must be taken from the Appdome.
- `AC_APPDOME_FUSION_SET_ID`: Fusion Set ID must be taken from the Appdome.
- `AC_APPDOME_SIGN_METHOD`: Signing method for automatically sign applications using the Appdome service in accordance with Apple's guidelines.
- `AC_APPDOME_PROVISIONING_PROFILES`: Paths of the provisioning profiles. You can separate files with commas. It must have `mobileprovision` extension.
- `AC_APPDOME_CERTIFICATES`: Paths of the certificate file. It must have `p12` extension.

## Optional Inputs

- `AC_APPDOME_TEAM_ID`: Team ID must be taken from the Appdome.
- `AC_APPDOME_IOS_ENTITLEMENTS`: Entitlements must be taken from the Xcode. You can separate entitlement files with commas. It must have `plist`, `txt` or `xml` file extension.
- `AC_APPDOME_CERTIFICATES_PASS`: iOS Certificate Password.

## Output Variables

- `AC_APPDOME_SECURED_IPA_PATH`: Local path of the secured .ipa file. Available when 'Signing Method' set to 'On-Appdome' or 'Private-Signing'.
- `AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH`: Local path of the `.sh` sign script file. Available when 'Signing Method' set to 'Auto-Dev-Signing'.
- `AC_APPDOME_CERTIFICATE_PATH`: Local path of the Certified Secure Certificate `.pdf` file

## Adding File Inputs

You can utilize Appcircle's `Environment Variables` page to generate the necessary file inputs for Appdome. For more detailed information, please refer to the document below:
- https://docs.appcircle.io/environment-variables/managing-variables#adding-files-as-environment-variables

If you want to use reserved environment variables such as `AC_PROVISIONING_PROFILES` and `AC_CERTIFICATES` for the files input, you must also adapt the file extensions. For instance, to change the `AC_PROVISIONING_PROFILES` extension to `mobileprovision` you can execute the following code using the `Custom Script` before the `Appdome-Build-2Secure for iOS` step:
```
provision_profiles=$(echo "$AC_PROVISIONING_PROFILES" | tr "|" ,)

if [ -f "$provision_profiles" ];  then
  echo "provision_profiles exists"
else
  echo "provision_profiles not found"
  exit 1
fi

mv "${provision_profiles}" "${provision_profiles}.mobileprovision" 

AC_PROVISIONING_PROFILES="${AC_PROVISIONING_PROFILES}.mobileprovision"
echo $AC_PROVISIONING_PROFILES

echo "AC_PROVISIONING_PROFILES=${AC_PROVISIONING_PROFILES}" >> $AC_ENV_FILE_PATH
```

For more details about Custom Script, see the document below:
- https://docs.appcircle.io/integrations/working-with-custom-scripts/
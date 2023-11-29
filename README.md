# Appcircle _Appdome-Build-2Secure for iOS_ component

Integration that allows activating security and app protection features, building and signing mobile apps using Appdome's API.

## Required Inputs

- `AC_APPDOME_IPA_PATH`: URL to app file (ipa) or an environment variable representing its path (i.e. $AC_EXPORT_DIR/<myappname>.ipa).
- `AC_APPDOME_API_KEY`: This API key must be taken from the Appdome.
- `AC_APPDOME_FUSION_SET_ID`: Fusion Set ID must be taken from the Appdome.
- `AC_APPDOME_SIGN_METHOD`: App signing method.
- `AC_IOS_ENTITLEMENTS`: Entitlements must be taken from the Xcode. You can separate entitlement files with commas.
- `AC_APPDOME_PROVISIONING_PROFILES`: Paths of the provisioning profiles. You can separate files with commas.
- `AC_APPDOME_CERTIFICATES`: Paths of the certificate file.
- `AC_APPDOME_BUILD_LOGS`: Build with diagnostic logs?

## Optional Inputs

- `AC_APPDOME_TEAM_ID`: Team ID must be taken from the Appdome.
- `AC_APPDOME_CERTIFICATES_PASS`: iOS Certificate Password.

## Output Variables

- `AC_APPDOME_SECURED_IPA_PATH`: Local path of the secured .ipa file. Available when 'Signing Method' set to 'On-Appdome' or 'Private-Signing'.
- `AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH`: Local path of the .sh sign script file. Available when 'Signing Method' set to 'Auto-Dev-Signing
- `AC_APPDOME_CERTIFICATE_PATH`: Local path of the Certified Secure Certificate .pdf file

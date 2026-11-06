# Open NavG — development environment.
# Usage:  source scripts/env.sh
# Puts Java and the newest installed Connect IQ SDK on PATH.

export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"

_ciq_root="$HOME/Library/Application Support/Garmin/ConnectIQ"
_sdk="$(ls -d "$_ciq_root"/Sdks/connectiq-sdk-mac-* 2>/dev/null | sort -V | tail -1)"

if [ -z "$_sdk" ]; then
  echo "Connect IQ SDK not found. Open ~/Applications/SdkManager.app, log in, and download an SDK + the Venu 2 device." >&2
else
  export CIQ_SDK="$_sdk"
  export CIQ_DEVICES="$_ciq_root/Devices"
  export PATH="$JAVA_HOME/bin:$CIQ_SDK/bin:$PATH"
fi

# Signing key lives outside the repo and must never be committed.
export CIQ_DEV_KEY="${CIQ_DEV_KEY:-$HOME/.garmin/developer_key.der}"

unset _ciq_root _sdk

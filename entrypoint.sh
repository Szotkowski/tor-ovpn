#!/bin/bash
set -e
# set -x # Uncomment this line for detailed debugging output (shows commands as they are executed)

# --- Configuration Variables ---
EASY_RSA_DIR="/usr/share/easy-rsa" # Default Easy-RSA location
OVPN_DIR="/etc/openvpn"
CLIENT_NAME="client" # Name for your client certificate and key
SERVER_COMMON_NAME="server" # Common Name for your OpenVPN server certificate
CA_COMMON_NAME="OpenVPN-CA" # Common Name for your Certificate Authority

# Tor Hidden Service configuration
TOR_SERVICE_DIR="/var/lib/tor/openvpn_service" # Must match chown command
TOR_HIDDEN_PORT_INTERNAL="1195" # OpenVPN server port (internal to Tor)
TOR_HIDDEN_PORT_EXTERNAL="1195" # External port for the .onion service (exposed by Tor)

# --- Initial Cleanup (Run this FIRST for a fresh start) ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Performing initial cleanup of old certificates and keys..."
# Remove Easy-RSA PKI
if [[ -d "${EASY_RSA_DIR}/pki" ]]; then
    rm -rf "${EASY_RSA_DIR}/pki"
    echo "$(date +"%Y-%m-%d %H:%M:%S") Removed Easy-RSA PKI directory."
fi
# Remove OpenVPN server/client keys and certs
rm -f "${OVPN_DIR}/ca.crt" \
      "${OVPN_DIR}/server.crt" \
      "${OVPN_DIR}/server.key" \
      "${OVPN_DIR}/ta.key" \
      "${OVPN_DIR}/client.crt" \
      "${OVPN_DIR}/client.key" \
      "${OVPN_DIR}/client.ovpn" \
      "${OVPN_DIR}/openvpn_server.log" \
      "${OVPN_DIR}/tor_startup.log" # Also clean up old server logs
echo "$(date +"%Y-%m-%d %H:%M:%S") Removed existing OpenVPN server and client files from ${OVPN_DIR}."

# --- Install Necessary Libraries ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Updating package list and installing OpenVPN and Easy-RSA..."
apt update
apt install -y openvpn easy-rsa tor procps iproute2 # Ensure procps and iproute2 (for ss) are installed

# --- Fix ownership for Tor data dir ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Fixing ownership for Tor data directory ${TOR_SERVICE_DIR}..."
mkdir -p "${TOR_SERVICE_DIR}" # Ensure directory exists before chown
chown -R debian-tor:debian-tor "${TOR_SERVICE_DIR}" || { echo "ERROR: Failed to set ownership for Tor directory. Exiting."; exit 1; }
echo "$(date +"%Y-%m-%d %H:%M:%S") Ownership fixed for Tor data directory."


# --- Generate Server Certificates and Keys (if missing) ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Checking for existing CA and server certificates in ${OVPN_DIR}..."

# After cleanup, these should always be missing, so we'll always generate them.
echo "$(date +"%Y-%m-%d %H:%M:%S") CA, server certificates, or TA key are missing. Generating them now using Easy-RSA 3..."

# Ensure Easy-RSA PKI is initialized
cd "${EASY_RSA_DIR}"
if [[ ! -d pki ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") Initializing Easy-RSA PKI..."
    EASYRSA_BATCH=1 ./easyrsa init-pki # Added EASYRSA_BATCH=1
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") Easy-RSA PKI already initialized (or recreated)."
fi

# Build CA
echo "$(date +"%Y-%m-%d %H:%M:%S") Building CA with Common Name '${CA_COMMON_NAME}' non-interactively..."
echo "${CA_COMMON_NAME}" | EASYRSA_BATCH=1 ./easyrsa build-ca nopass
if [ $? -ne 0 ]; then
    echo "$(date +"%m-%d %H:%M:%S") ERROR: Failed to build the CA. Please check Easy-RSA requirements and permissions."
    exit 1
fi

# Build Server Certificate and Key
echo "$(date +"%Y-%m-%d %H:%M:%S") Building server certificate and key for Common Name '${SERVER_COMMON_NAME}'..."
echo "${SERVER_COMMON_NAME}" | EASYRSA_BATCH=1 ./easyrsa build-server-full "${SERVER_COMMON_NAME}" nopass
if [ $? -ne 0 ]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Failed to build the server certificate. Please check Easy-RSA requirements."
    exit 1
fi

# Generate TLS Authentication Key
echo "$(date +"%Y-%m-%d %H:%M:%S") Generating TLS authentication key (${OVPN_DIR}/ta.key)..."
openvpn --genkey --secret "${OVPN_DIR}/ta.key"

# Copy generated server components to OpenVPN directory
echo "$(date +"%Y-%m-%d %H:%M:%S") Copying server certificates and keys to ${OVPN_DIR}..."
cp pki/ca.crt "${OVPN_DIR}/ca.crt"
cp pki/issued/${SERVER_COMMON_NAME}.crt "${OVPN_DIR}/server.crt"
cp pki/private/${SERVER_COMMON_NAME}.key "${OVPN_DIR}/server.key"

echo "$(date +"%Y-%m-%d %H:%M:%S") Server certificates and keys generation complete."

# --- Fix permissions on OpenVPN server key ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Fixing permissions on OpenVPN server key..."
chmod 600 "${OVPN_DIR}/server.key"

# --- Generate Client Certificates and Keys ---
echo "$(date +"%Y-%m-%d %H:%M:%M") Generating client certificate and key for ${CLIENT_NAME}..."

# Navigate to the Easy-RSA directory (already there from previous steps, but safe to re-cd)
cd "${EASY_RSA_DIR}"

# Generate client certificate
if [[ -f pki/index.txt ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") Easy-RSA PKI found. Generating client certificate for ${CLIENT_NAME} non-interactively..."
    echo "${CLIENT_NAME}" | EASYRSA_BATCH=1 ./easyrsa build-client-full "${CLIENT_NAME}" nopass
    if [ $? -ne 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Failed to build the client certificate. Please check Easy-RSA setup."
        exit 1
    fi
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Easy-RSA PKI not initialized correctly. Cannot generate client certificate."
    echo "Please ensure the 'Generate Server Certificates and Keys' section of the script completed successfully."
    exit 1
fi

# Copy generated client certificates and keys to OpenVPN directory
echo "$(date +"%Y-%m-%d %H:%M:%S") Copying client certificates and keys to ${OVPN_DIR}..."
cp pki/issued/${CLIENT_NAME}.crt "${OVPN_DIR}/client.crt"
cp pki/private/${CLIENT_NAME}.key "${OVPN_DIR}/client.key"

# Ensure ca.crt is in the OpenVPN directory for the client config
if [[ ! -f ${OVPN_DIR}/ca.crt ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") WARNING: CA certificate not found in ${OVPN_DIR}. Attempting to copy from Easy-RSA pki..."
    cp pki/ca.crt "${OVPN_DIR}/ca.crt"
fi

# --- Start Tor and get .onion address ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Starting Tor and waiting for .onion address..."

TOR_LOG_FILE="${OVPN_DIR}/tor_startup.log"
# Start Tor in the background, redirecting stdout and stderr to a log file
if ! su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc > \"${TOR_LOG_FILE}\" 2>&1 &"; then
    echo "ERROR: Attempt to start Tor process failed. Check permissions or 'su' command."
    exit 1
fi

# Give Tor a moment to start and write logs
sleep 2

# Check if Tor process is actually running
if ! pgrep -u debian-tor tor > /dev/null; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Tor process is not running. Check ${TOR_LOG_FILE} for details."
    cat "${TOR_LOG_FILE}" # Output logs for immediate debugging
    exit 1
fi

ONION_HOSTNAME_FILE="${TOR_SERVICE_DIR}/hostname"
TIMEOUT=60 # seconds
ELAPSED_TIME=0

# Wait for the hostname file to appear
while [ ! -f "${ONION_HOSTNAME_FILE}" ] && [ ${ELAPSED_TIME} -lt ${TIMEOUT} ]; do
    echo "$(date +"%Y-%m-%d %H:%M:%S") Waiting for Tor to create ${ONION_HOSTNAME_FILE}..."
    sleep 5
    ELAPSED_TIME=$((ELAPSED_TIME + 5))
done

if [ ! -f "${ONION_HOSTNAME_FILE}" ]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Tor hostname file not found after ${TIMEOUT} seconds. Tor may not be running or configured correctly."
    echo "Please check Tor logs in ${TOR_LOG_FILE} for more information."
    cat "${TOR_LOG_FILE}" # Output logs for immediate debugging
    exit 1
fi

# Read the .onion address from the file
ONION_ADDRESS=$(cat "${ONION_HOSTNAME_FILE}")
ONION_ADDRESS=$(echo "${ONION_ADDRESS}" | tr -d '\n\r') # Remove any newline characters
echo "$(date +"%Y-%m-%d %H:%M:%S") Discovered .onion address: ${ONION_ADDRESS}"

# --- Start OpenVPN server ---
OPENVPN_SERVER_CONF="${OVPN_DIR}/server.conf"
OPENVPN_SERVER_LOG="${OVPN_DIR}/openvpn_server.log"

echo "$(date +"%Y-%m-%d %H:%M:%S") Starting OpenVPN server..."

# Check if server.conf exists
if [[ ! -f "${OPENVPN_SERVER_CONF}" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: OpenVPN server configuration file '${OPENVPN_SERVER_CONF}' not found."
    echo "Please create this file with your OpenVPN server settings in the 'openvpn_data' directory on your host."
    exit 1
fi

# Start OpenVPN server in the background, redirecting output to log file
openvpn --config "${OPENVPN_SERVER_CONF}" > "${OPENVPN_SERVER_LOG}" 2>&1 &

# Give OpenVPN a moment to start and write logs
sleep 5

# Check if OpenVPN process is actually running
if ! pgrep openvpn > /dev/null; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: OpenVPN server process is not running. Check ${OPENVPN_SERVER_LOG} for details."
    cat "${OPENVPN_SERVER_LOG}" # Output logs for immediate debugging
    exit 1
fi

# Check if OpenVPN server is listening on the internal port
if ! ss -tln | grep ":${TOR_HIDDEN_PORT_INTERNAL}" > /dev/null; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: OpenVPN server is not listening on port ${TOR_HIDDEN_PORT_INTERNAL}."
    echo "This indicates a problem with the OpenVPN server configuration or startup."
    echo "Please check ${OPENVPN_SERVER_LOG} for more details."
    cat "${OPENVPN_SERVER_LOG}" # Output logs for immediate debugging
    exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") OpenVPN server started and listening on port ${TOR_HIDDEN_PORT_INTERNAL}. Check ${OPENVPN_SERVER_LOG} for server logs."

# Wait some seconds for services to initialize
echo "$(date +"%Y-%m-%d %H:%M:%S") Waiting 10 seconds for services to initialize..."
sleep 10

# --- Only create client.ovpn if all necessary keys and certs exist ---
echo "$(date +"%Y-%m-%d %H:%M:%S") Checking for necessary client certificates and keys before creating .ovpn..."
if [[ -f ${OVPN_DIR}/client.crt && -f ${OVPN_DIR}/client.key && -f ${OVPN_DIR}/ta.key && -f ${OVPN_DIR}/ca.crt ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") All client certificates and keys found. Reading contents for .ovpn embedding..."

    # Read the contents of the files into variables
    CA_CERT_CONTENT=$(cat "${OVPN_DIR}/ca.crt")
    CLIENT_CERT_CONTENT=$(cat "${OVPN_DIR}/client.crt")
    CLIENT_KEY_CONTENT=$(cat "${OVPN_DIR}/client.key")
    TA_KEY_CONTENT=$(cat "${OVPN_DIR}/ta.key")

    REMOTE_PORT="${TOR_HIDDEN_PORT_EXTERNAL}" # Use the external Tor port
    REMOTE_PROTOCOL="tcp" # Protocol from your example

    cat > "${OVPN_DIR}/client.ovpn" <<EOF
client
dev tun
proto ${REMOTE_PROTOCOL}
remote ${ONION_ADDRESS} ${REMOTE_PORT} ${REMOTE_PROTOCOL}
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
remote-cert-tls server
socks-proxy 127.0.0.1 9050
key-direction 1
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305 # Explicitly set data ciphers for client (matching server)
auth SHA256 # Explicitly set auth algorithm for client (matching server)
verb 4 # Increased verbosity for client debugging

<ca>
${CA_CERT_CONTENT}
</ca>

<cert>
${CLIENT_CERT_CONTENT}
</cert>

<key>
${CLIENT_KEY_CONTENT}
</key>

<tls-auth>
${TA_KEY_CONTENT}
</tls-auth>
EOF

    echo "$(date +"%Y-%m-%d %H:%M:%S") .ovpn client config created at ${OVPN_DIR}/client.ovpn"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") ERROR: Client certs/keys, CA cert, or ta.key missing; skipping .ovpn creation."
    echo "$(date +"%Y-%m-%d %H:%M:%S") Please ensure the server's CA, server cert/key, and TA key are in ${OVPN_DIR} and client certs were generated successfully."
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") Script finished. Waiting for background processes to complete..."
wait

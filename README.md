OpenVPN Server via Tor Hidden Service

This project provides a secure OpenVPN server accessible exclusively through a Tor Hidden Service. This setup enhances privacy by concealing the server's true IP address from the OpenVPN client, routing all VPN connection traffic through the Tor network.
Features

    Tor Integration: OpenVPN server is exposed as a Tor Hidden Service, providing a .onion address for connection.

    Dynamic Onion Address: The .onion address is dynamically generated and retrieved by the setup script.

    Automated Setup: Docker and Docker Compose automate the generation of certificates, keys, and configuration files.

    Enhanced Privacy: Clients connect via Tor, obscuring the server's physical location.

    Secure VPN: Utilizes OpenVPN with TLS authentication for encrypted communication.

Prerequisites

Before you begin, ensure you have the following installed on your host machine:

    Docker: Containerization platform.

    Docker Compose: Tool for defining and running multi-container Docker applications.

    Git: For cloning the repository.

    OpenVPN Client: On the client machine you wish to connect from (e.g., OpenVPN Connect for Windows/macOS, or OpenVPN package for Linux).

    Tor Client/Browser: On the client machine, you need a running Tor instance (e.g., Tor Browser or a standalone Tor client) to provide a SOCKS proxy on 127.0.0.1:9050.

Setup

Follow these steps to set up and run your OpenVPN-Tor server.
1. Clone the Repository

First, clone this repository to your local machine:

git clone <repository-url>
cd <repository-directory>

2. Configure Tor (torrc)

Create a file named torrc in the root directory of your project (the same directory as docker-compose.yml). This file configures Tor's hidden service.

torrc content:

HiddenServiceDir /var/lib/tor/openvpn_service
HiddenServicePort 1195 127.0.0.1:1195

3. Configure OpenVPN Server (server.conf)

Create a directory named openvpn_data in the root of your project. Inside openvpn_data, create a file named server.conf. This file contains the OpenVPN server's configuration.

openvpn_data/server.conf content:

port 1195
proto tcp
dev tun

ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh none

tls-auth /etc/openvpn/ta.key 0

server 10.8.0.0 255.255.255.0
keepalive 10 120

data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
auth SHA256

persist-key
persist-tun

status /etc/openvpn/openvpn-status.log
log /etc/openvpn/openvpn_server.log
log-append /etc/openvpn/openvpn_server.log
verb 4
topology subnet
user nobody
group nogroup
explicit-exit-notify 1

4. Docker Compose Configuration (docker-compose.yml)

Ensure your docker-compose.yml file is configured to use a Docker named volume for Tor's sensitive data and bind mounts for OpenVPN configuration and logs. This is crucial for proper permissions and data persistence.

docker-compose.yml content:

services:
  openvpn_tor_server:
    build: .
    container_name: openvpn_tor_server
    cap_add:
      - NET_ADMIN      # needed for tun/tap device control
    devices:
      - /dev/net/tun   # expose tun device
    volumes:
      - tor_hidden_service_data:/var/lib/tor/openvpn_service # Docker named volume for Tor data
      - ./torrc:/etc/tor/torrc:ro                            # Mount host torrc
      - ./openvpn_data:/etc/openvpn                          # Mount OpenVPN config/certs
    ports:
      - "1195:1195" # This port is for internal Docker networking, not directly exposed to internet
    restart: unless-stopped

volumes:
  tor_hidden_service_data: # Define the Docker named volume

5. entrypoint.sh Script

The entrypoint.sh script handles the generation of OpenVPN certificates and keys, starts Tor, retrieves the .onion address, starts the OpenVPN server, and generates the client configuration file. This script is automatically copied and executed by the Dockerfile.

(The content of entrypoint.sh is managed internally by the project; you typically don't need to modify it directly unless debugging deep issues.)
6. Build and Run the Docker Containers

Navigate to the root directory of your project in your terminal and run the following commands:

# Stop and remove any previous containers and volumes to ensure a clean start
docker-compose down -v

# Build the Docker image (using --no-cache for a fresh build)
docker-compose build --no-cache

# Start the services in detached mode
docker-compose up -d

Monitor the logs to ensure everything starts correctly:

docker-compose logs -f openvpn_tor_server

You should see messages indicating Tor bootstrapping, an .onion address being discovered, and the OpenVPN server starting successfully.
Connecting to the VPN

Once the server is up and running, you need to retrieve the client configuration file and connect using your OpenVPN client.
1. Retrieve client.ovpn

The entrypoint.sh script generates the client.ovpn file inside the container, embedding all necessary certificates and keys. Copy it to your host machine:

docker cp openvpn_tor_server:/etc/openvpn/client.ovpn ./openvpn_data/client.ovpn

This will place the client.ovpn file in your openvpn_data directory on your host.
2. Prepare your Client Machine

On the machine you want to connect from:

    Install OpenVPN Client Software: (e.g., OpenVPN Connect).

    Run a Tor Client/Browser: Ensure you have Tor running and providing a SOCKS proxy on 127.0.0.1:9050. If you're using Tor Browser, it typically runs a SOCKS proxy on this address automatically. If you're using a standalone Tor client, ensure it's configured to do so.

3. Import and Connect

    Import the client.ovpn file into your OpenVPN client software.

    Ensure your OpenVPN client is configured to use the local Tor SOCKS proxy (this is already specified in the generated client.ovpn with socks-proxy 127.0.0.1 9050).

    Initiate the connection.

If successful, your OpenVPN client should connect through the Tor network to your hidden service VPN server.
Important Notes & Troubleshooting

    Git Ignored Files: The openvpn_data/ directory and its contents (including server.conf, client.ovpn, and all generated keys/certs) are ignored by Git for security reasons. Never commit private keys or sensitive configurations to a public repository.

    Logs: If you encounter issues, check the Docker Compose logs:

        docker-compose logs -f openvpn_tor_server for general container output.

        docker exec openvpn_tor_server cat /etc/openvpn/tor_startup.log for Tor-specific startup issues.

        docker exec openvpn_tor_server cat /etc/openvpn/openvpn_server.log for OpenVPN server-side issues.

    Firewall: Ensure no firewalls on your host or within your Docker environment are blocking internal 127.0.0.1:1195 (between Tor and OpenVPN) or 127.0.0.1:9050 (between OpenVPN client and Tor proxy).

    Time Synchronization: Ensure your host machine's time is synchronized, as TLS certificates are time-sensitive.

License

This project is open-source and available under the MIT License.
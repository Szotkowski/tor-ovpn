# OpenVPN Server via Tor Hidden Service

This project provides a secure OpenVPN server accessible exclusively through a **Tor Hidden Service**. This setup enhances privacy by concealing the server's true IP address from the OpenVPN client, routing all VPN connection traffic through the Tor network.

---

## Features

* **Tor Integration**: OpenVPN server is exposed as a Tor Hidden Service, providing a `.onion` address for connection.
* **Dynamic Onion Address**: The `.onion` address is dynamically generated and retrieved by the setup script.
* **Automated Setup**: Docker and Docker Compose automate the generation of certificates, keys, and configuration files.
* **Enhanced Privacy**: Clients connect via Tor, obscuring the server's physical location.
* **Secure VPN**: Utilizes OpenVPN with TLS authentication for encrypted communication.

---

## Prerequisites

Before you begin, ensure you have the following installed on your host machine:

* **Docker**: Containerization platform.
* **Docker Compose**: Tool for defining and running multi-container Docker applications.
* **Git**: For cloning the repository.
* **OpenVPN Client**: On the client machine you wish to connect from (e.g., OpenVPN Connect for Windows/macOS, or OpenVPN package for Linux).
* **Tor Client/Browser**: On the client machine, you need a running Tor instance (e.g., Tor Browser or a standalone Tor client) to provide a SOCKS proxy on `127.0.0.1:9050`.

---

## Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Configure Tor (`torrc`)

Create a file named `torrc` in the root directory of your project (same level as `docker-compose.yml`):

```
HiddenServiceDir /var/lib/tor/openvpn_service
HiddenServicePort 1195 127.0.0.1:1195
```

### 3. Configure OpenVPN Server (`server.conf`)

Create a directory named `openvpn_data` in the project root. Inside it, create a file named `server.conf`:

```
local 127.0.0.1
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
```

### 4. Docker Compose Configuration (`docker-compose.yml`)

Ensure your `docker-compose.yml` is configured to use a Docker named volume for Tor’s data and bind mounts for OpenVPN config:

```yaml
services:
  openvpn_tor_server:
    build: .
    container_name: openvpn_tor_server
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - tor_hidden_service_data:/var/lib/tor/openvpn_service
      - ./torrc:/etc/tor/torrc:ro
      - ./openvpn_data:/etc/openvpn
    ports:
      - "1195:1195"
    restart: unless-stopped

volumes:
  tor_hidden_service_data:
```

### 5. `entrypoint.sh` Script

The `entrypoint.sh` script (bundled in the Dockerfile) will:

1. Generate OpenVPN certificates and keys
2. Start Tor
3. Retrieve the `.onion` address
4. Start the OpenVPN server
5. Generate the `client.ovpn` configuration file

You typically don’t need to modify this script.

---

## Build and Run

In your project root, run:

```bash
# Clean previous state
docker-compose down -v

# Build fresh
docker-compose build --no-cache

# Run in background
docker-compose up -d

# Monitor logs
docker-compose logs -f openvpn_tor_server
```

You should see:

* Tor bootstrapping
* `.onion` address discovery
* OpenVPN server start

---

## Connecting to the VPN

1. **Retrieve `client.ovpn`:**

   ```bash
   docker cp openvpn_tor_server:/etc/openvpn/client.ovpn ./openvpn_data/client.ovpn
   ```

2. **Prepare Client Machine:**

   * Install your OpenVPN client.
   * Ensure Tor is running with a SOCKS proxy at `127.0.0.1:9050`.

3. **Import & Connect:**

   * Import `client.ovpn` into your VPN client.
   * Connect—traffic will route via Tor to the hidden service.

> The generated `client.ovpn` includes `socks-proxy 127.0.0.1 9050`.

---

## Important Notes & Troubleshooting

* **Git-Ignored Files**:
  The `openvpn_data/` directory (including configs, certs, and `client.ovpn`) is `.gitignore`d. Never commit sensitive files.

* **Logs**:

  * General container logs:

    ```bash
    docker-compose logs -f openvpn_tor_server
    ```
  * Tor startup log:

    ```bash
    docker exec openvpn_tor_server cat /etc/openvpn/tor_startup.log
    ```
  * OpenVPN log:

    ```bash
    docker exec openvpn_tor_server cat /etc/openvpn/openvpn_server.log
    ```

* **Firewall**:
  Ensure nothing blocks `127.0.0.1:1195` (Tor↔OpenVPN) or `127.0.0.1:9050` (client↔Tor).

* **Time Sync**:
  TLS certificates require accurate system time.

---

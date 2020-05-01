# openvpn-socks-proxy

Obfuscation of the client-side IP using a SOCKS5 tunnel in a site-to-site OpenVPN setup

- [openvpn-socks-proxy](#openvpn-socks-proxy)
  - [Overview](#overview)
  - [Getting Started](#getting-started)
    - [Requirements](#requirements)
      - [Toolkit](#toolkit)
      - [Terraform](#terraform)
      - [Ansible](#ansible)
      - [Google Cloud SDK](#google-cloud-sdk)
      - [Google project](#google-project)
      - [Service Account](#service-account)
    - [Installing](#installing)
    - [Infrastructure](#infrastructure)
    - [Provision](#provision)
  - [Implementation details](#implementation-details)
  - [Terraform tags](#terraform-tags)
  - [Expand Scope of the VPN](#expand-scope-of-the-vpn)
    - [Server Side](#server-side)
    - [Client side](#client-side)
    - [Multiple LANs behind OpenVPN clients](#multiple-lans-behind-openvpn-clients)
    - [Bridging and routing](#bridging-and-routing)
  - [TODO](#todo)
  - [Helpful links](#helpful-links)

## Overview

The goal of this POC is to create a site-to-site OpenVPN setup between two networks connected to each other using an OpenVPN tunnel, obfuscating the OpenVPN client-side IP using a SOCKS5 tunnel. As an added benefit, client-side obfuscation proxy also makes it difficult to detect an OpenVPN connection by deep packet inspection.

The SSH server offers a SOCKS5 proxy interface to which an OpenVPN client can connect, the result is that VPN network packets are obfuscated, making it difficult to identify the connection.

```ascii
                   SOCK PROXY
                   +-----------+
          SOCKS5   | SSH       | OpenVPN client SNAT
        +-Tunnel---> Server    +-------------+
        |          |           |             |
        |          +-----------+             |
        |                                    |
        |                                    |
+----------------+                           |
|   +--------+   |VPN                        |
|   | SSH    |   |Gateway                    |
|   | Client |   |                           |
|   +---+----+   |                           |
|       |        |                           |
|       |        |                           |
|   +---v----+   |                           |
|   |Local   |   |                           |
|   |TCP port    |                           |
|   +---^----+   |                           |
|       |        |                           |
|       |        |                           |
|       |        |                           |
|  +----+-----+  |                     +-----v------+
|  | OpenVPN  |  |    LAN Tunneling    | OpenVPN    |
|  | Client   <------------------------> Server     |
|  +----------+  |    10.8.0.0/16      +-----^------+
+----------------+                           |
        ^                                    |
        |                                    |
        |                                    |
        |                                    |
+-------+--------+                   +-------+------+
|                |                   |              |
|  10.0.0.0/16   |                   | 10.1.0.0/16  |
+----------------+                   +--------------+
Site A        LAN                    Site B      LAN

```

## Getting Started

### Requirements

#### Toolkit

- Terraform
- Ansible
- Gcloud
- jq

#### Terraform

This will install Terraform on Fedora, please check instructions for your distribution

```bash
# Ensure wget is installed
sudo dnf -y install wget unzip
# Download the terraform archive
# Check the latest release on Terraform releases page before downloading below.
export VER="0.12.24"
wget https://releases.hashicorp.com/terraform/${VER}/terraform_${VER}_linux_amd6
# Extract it
unzip terraform_${VER}_linux_amd64.zip
# Move terraform executable to a directory within your $PATH
mv terraform $HOME/bin/
```

#### Ansible

```bash
export VENV=openvpn-socks-proxy
export TMPDIR=`mktemp -d`
# Creating a virtual environment
python3 -m venv $TMPDIR/$VENV
# Activate virtual env
source $TMPDIR/$VENV/activate
# Install requirements
pip3 install -r ansible/requirements.txt
```

#### Google Cloud SDK

Install the Google Cloud SDK, initialize it

```bash
# Cloud SDK requires Python
# Download the latest sdk file best suited to your operating system (Linux 64-bit in this case).
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-290.0.1-linux-x86_64.tar.gz
# Extract gcloud sdk
tar zxvf [ARCHIVE_FILE] google-cloud-sdk
# Install it
./google-cloud-sdk/install.sh
# Run gcloud init to get started
gcloud init

```

#### Google project

Create a project to host the required infrastructure

```bash
gcloud projects create <project_id>
```

#### Service Account

To work with the GCE modules, you’ll first need to get some credentials in the JSON format:

- [Create a Service Account](https://developers.google.com/identity/protocols/oauth2/service-account#creatinganaccount)
- [Download JSON credentials](https://support.google.com/cloud/answer/6158849?hl=en&ref_topic=6262490#serviceaccounts)]

In order to configure Ansible and Terraform with your GCP credentials, set the following environment variables:

```bash
# For terraform
export GOOGLE_CLOUD_KEYFILE_JSON=<service account json file>

# For ansible
export GCE_CREDENTIALS_FILE_PATH=$GOOGLE_CLOUD_KEYFILE_JSON
export GCE_EMAIL=$(jq -r .client_email $GCE_CREDENTIALS_FILE_PATH)

# For both
export GCE_PROJECT=$(jq -r .project_id $GCE_CREDENTIALS_FILE_PATH)

```

### Installing

### Infrastructure

```shell
terraform apply -var project_id=$GCE_PROJECT
```

### Provision

```shell
ansible-playbook -i inventory tasks.yaml
```

## Implementation details

## Terraform tags

The following network tags are assigned to the GCE instances depending on their role, causing the dynamic inventory (`gce.py`) to group the instances by these tag, so we can select hosts group on the playbook.

- `socks`: instance acting as socks server
- `openvpn`: peers of the OpenVPN tunnel
- `site-a`: client side of the OpenVPN tunnel
- `site-b`: server side of the OpenVPN tunnel

## Expand Scope of the VPN

The included Ansible playbooks configure a site-to-site OpenVPN tunnels and expand the scope of the VPN in both sides.

### Server Side

To expand the scope of the VPN so that clients can reach multiple machines on the server network we must advertise the server subnet to VPN clients, using:

```bash
push "route <network> <netmask>"
```

The `push` routes are added on the clients connecting, telling them to route those networks over the vpn.

Make sure that IP and TUN forwarding are enabled on the OpenVPN server machine.

### Client side

In a typical road-warrior or remote access scenario, the client machine connects to the VPN as a single machine. But suppose the client machine is a gateway for a local LAN and we would like to reach each machine on the client LAN. We need to configure the server to route clients subnets thought their specific client.

First configure the client config dir (ccd) that is where the server will look for client configurations:

```bash
client-config-directory ccd
```

Create a file called `client Common Name` with the route, this will tell OpenVPN server that `<client_network>` should be routed thought  `client Common Name`

```bash
iroute <client_network> <client_netmask>
```

We also have to tell the kernel to route `<client_network>` thought the `tun` interface, add the following line to `server.conf` in the server side:

```bash
route <client_network> <client_netmask>
```

The `route` entry adjust the local routing table, telling it to route this network over the vpn.

Make sure that IP and TUN forwarding are enabled on the OpenVPN server machine.

### Multiple LANs behind OpenVPN clients

The configuration for multiple OpenVPN clients is similar to a single client, the server will `push` every client route to all the clients, but skipping the route that is local to each client. The `iroute` entry will tell the server which client is responsible for which route and will skip pushing those routes to the clients. Without the `iroute` entry we will find the following error in the logs file:

```txt
MULTI: bad source address from client [IP ADDRESS], packet dropped
```

### [Bridging and routing](BridgingAndRouting.md)

## TODO

- Investigate obfsproxy and obfs4 as replacement of ssh SOCKS5 tunnel
- Ansible secrets.py
- Investigate glinder to loadbalance the socks proxy
- Investigate HA in OpenVPN

## Helpful links

- [Site-To-Site VPN Routing Explained In Detail](https://openvpn.net/vpn-server-resources/site-to-site-routing-explained-in-detail/)
- [Create a SOCKS proxy on a Linux server with SSH to bypass content filters](https://ma.ttias.be/socks-proxy-linux-ssh-bypass-content-filters/)
- [Routing traffic through OpenVPN using a local SOCKS proxy](https://kiljan.org/2017/11/15/routing-traffic-through-openvpn-using-a-local-socks-proxy/)
- [OpenVPN Routing](https://www.secure-computing.net/wiki/index.php/OpenVPN/Routing)
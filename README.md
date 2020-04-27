# openvpn-socks-proxy

Obfuscation of the client-side IP using a SOCKS5 tunnel in a site-to-site OpenVPN setup

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

#### Google project

Create a project to host the required infrastructure

#### Service Account

To work with the GCE modules, you’ll first need to get some credentials in the JSON format:

- [Create a Service Account](https://developers.google.com/identity/protocols/oauth2/service-account#creatinganaccount)
- [Download JSON credentials](https://support.google.com/cloud/answer/6158849?hl=en&ref_topic=6262490#serviceaccounts)]

In order to configure Ansible and Terraform with your GCP credentials, set the following environment variables:

- `GCE_EMAIL`
- `GCE_PROJECT`
- `GCE_CREDENTIALS_FILE_PATH`: Service Account json file
- `GOOGLE_CLOUD_KEYFILE_JSON`: Service Account json file

### Installing

### Infrastructure

```shell
terraform apply -var project_id=<project_id>
```

### Provision

```shell
ansible-playbook -i inventory tasks.yaml
```

## Implementation details

## Expand Scope of the VPN

The included Ansible playbooks configure a site-to-site OpenVPN tunnels and expand the scope of the VPN in both sides.

### Server Side

To expand the scope of the VPN so that clients can reach multiple machines on the server network we must advertise the server subnet to VPN clients, using:

```bash
push "route <network> <netmask>"
```

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

We also have to tell the kernel to route `<client_network>` thought the `tun` interface, add the following line to `server.conf`:

```bash
route <client_network> <client_netmask>
```

## TODO

- Investigate obfsproxy and obfs4 as replacement of ssh SOCKS5 tunnel
- Ansible secrets.py
- Investigate glinder to loadbalance the socks proxy
- Investigate HA in OpenVPN

## Helpful links

- [Site-To-Site VPN Routing Explained In Detail](https://openvpn.net/vpn-server-resources/site-to-site-routing-explained-in-detail/)
- [Create a SOCKS proxy on a Linux server with SSH to bypass content filters](https://ma.ttias.be/socks-proxy-linux-ssh-bypass-content-filters/)
- [Routing traffic through OpenVPN using a local SOCKS proxy](https://kiljan.org/2017/11/15/routing-traffic-through-openvpn-using-a-local-socks-proxy/)
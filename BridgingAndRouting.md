# Introduction

For a brief introduction on bridging and routing, look at these links:

* [Determining whether to use a routed or bridged VPN in OpenVPN HOWTO](http://openvpn.net/index.php/open-source/documentation/howto.html#vpntype)
* [What are the fundamental differences between bridging and routing in terms of configuration? in OpenVPN FAQ](http://openvpn.net/index.php/open-source/faq/75-general/311-what-are-the-fundamental-differences-between-bridging-and-routing-in-terms-of-configuration.html)
* [OpenvVPN Routing in Secure-Computing Wiki](http://www.secure-computing.net/wiki/index.php/OpenVPN/Routing)

'''NOTE:''' The remaining sections are mostly based [on this email for dazo](http://thread.gmane.org/gmane.network.openvpn.user/32935/).

## Bridging vs. routing

This discussion needs to start with TAP vs TUN devices.  You want TAP if:

* You want to transport non-IP based traffic, or IPv6 traffic on OpenVPN 2.2 or older releases
* You want to bridge

And you want to bridge if:

* You want your LAN and VPN clients to be in the same broadcast domain
* You want your LAN DHCP server to provide DHCP addresses to your VPN client
* You have Windows server(s) you want to access and require network neighbourhood discovery to work via VPN '''and''' WINS is not an option to implement.  If you have WINS, you don't want bridging.  Really.

It might be a few more reasons, but these are the most typical ones.  And as you see, TAP is a requirement for bridging.  TUN devices cannot be used for bridges and non-IP traffic.

Bridging looks easier at first glance, but it brings a completely different can of worms.  Make no mistake: '''There are no shortcuts in making networking easier''' - except learning how to do it properly.

Now lets see benefits and drawbacks of TAP vs TUN.

TAP benefits:

* behaves like a real network adapter (except it is a virtual network adapter)
* can transport any network protocols (IPv4, IPv6, Netalk, IPX, etc, etc)
* Works in layer 2, meaning Ethernet frames are passed over the VPN tunnel
* ''Can'' be used in bridges

TAP drawbacks

* causes much more broadcast overhead on the VPN tunnel
* adds the overhead of Ethernet headers on all packets transported over the VPN tunnel
* scales poorly
* can not be used with Android or iOS devices

TUN benefits:

* A lower traffic overhead, transports only traffic which is destined for the VPN client
* Transports only layer 3 IP packets

TUN drawbacks:

* Broadcast traffic is not normally transported
* Can only transport IPv4 (OpenVPN 2.3 adds IPv6)
* '''Cannot''' be used in bridges

Please understand that in both setups, '''basic networking knowledge is a must'''.  You do need to understand basic network ''routing'' and ''firewalling'', no matter if you use routing, bridging, TUN or TAP.  Both TUN and TAP devices supports traditional network routing, so you are not required to use bridging with TAP.  But using bridges, you need in addition to know how bridges work and how this changes your firewalling.  To say it simple: Bridging will complicate your setup further.  Of course, there are scenarios where bridging really is the right solution.  But in most cases you will most likely solve your VPN setup with basic routing.

For more information about TCP/IP networking, the [TCP/IP Tutorial and Technical Overview IBM Red Book](http://www.redbooks.ibm.com/redbooks/pdfs/gg243376.pdf)  is recommended reading, especially chapter 3.1.

## Using routing

```txt
<disclaimer>
  NONE OF THIS IS TESTED.  But this is the basic theory behind it.
  It might be syntax errors here, or other stupid mistakes.
</disclaimer>
```

To set up a TUN setup with routing and masquerading for the VPN subnet, one approach could be something like this.  This example is based on a pretty standard network with a single Linux based firewall with two Ethernet cards:

```txt
                         +--------------------------------+
                         |            FIREWALL            |
              (public IP)|                                |192.168.0.1
 {INTERNET}=============={eth1                        eth0}=============<internal network / 192.168.0.0/24>
                         |   \                        /   |
                         |    +----------------------+    |
                         |    | iptables and         |    |
                         |    | routing engine       |    |
                         |    +--+----------------+--+    |
                         |       |*1              |*2     |
                         |     (openvpn)-------{tun0}     |
                         |                    10.8.0.1    |
                         +--------------------------------+

   *1 Only encrypted traffic will pass here, over UDP or TCP and only to the remote OpenVPN client
   *2 The unencrypted traffic will pass here.  This is the exit/entry point for the VPN tunnel.
```

Here tun0 is configured as 10.8.0.1 as a VPN, with the whole VPN network configured as 10.8.0.0/24.

What happens with OpenVPN is that it accepts OpenVPN clients from eth1, OpenVPN will decrypt the data and put it to the tun0 interface, and the iptables and routing engine will pick up that traffic again, filter/masquerade it and send it further to eth0 or eth1, depending on the routing table.  When the routing engine sends traffic destined for the tun0 network, OpenVPN will pick it up, encrypt it and send it out on eth1, towards the proper OpenVPN client.

First we need to be sure that IP forwarding is enabled.  Very often this is disabled by default.  This is done by running the following command line as root:

```txt
    [root@host ~] # sysctl -w net.ipv4.ip_forward=1
    net.ipv4.ip_forward = 1
    [root@host ~] #
```

This change is only temporary, so if you reboot your box this will be reset back to the default value.  To make this change persistent you need to modify ''/etc/sysctl.conf''.  In this file you should have a line stating:

```txt
    net.ipv4.ip_forward = 1
```

So, lets look at the iptables rules required for this to work.

```txt
    # Allow traffic initiated from VPN to access LAN
    iptables -I FORWARD -i tun0 -o eth0 \
         -s 10.8.0.0/24 -d 192.168.0.0/24 \
         -m conntrack --ctstate NEW -j ACCEPT

    # Allow traffic initiated from VPN to access "the world"
    iptables -I FORWARD -i tun0 -o eth1 \
         -s 10.8.0.0/24 -m conntrack --ctstate NEW -j ACCEPT

    # Allow traffic initiated from LAN to access "the world"
    iptables -I FORWARD -i eth0 -o eth1 \
         -s 192.168.0.0/24 -m conntrack --ctstate NEW -j ACCEPT

    # Allow established traffic to pass back and forth
    iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED \
         -j ACCEPT

    # Notice that -I is used, so when listing it (iptables -vxnL) it
    # will be reversed.  This is intentional in this demonstration.

    # Masquerade traffic from VPN to "the world" -- done in the nat table
    iptables -t nat -I POSTROUTING -o eth1 \
          -s 10.8.0.0/24 -j MASQUERADE

    # Masquerade traffic from LAN to "the world"
    iptables -t nat -I POSTROUTING -o eth1 \
          -s 192.168.0.0/24 -j MASQUERADE

```

Again, these changes are only temporary.  If you reboot your box, these rules will be cleared out.  Please read the documentation to your distribution on how to save the iptables configuration.  In worst case you can also use ''iptables-save'' and ''iptables-restore'' to dump and restore the iptables configuration to/from a file.

```txt
    # Save the iptables setup
    [root@host ~] # iptables-save > iptables-dump.ipt

    # Restore the iptables setup
    [root@host ~] # iptables-restore < iptables-dump.ipt
```

''(This iptables dump can also easily be edited manually if you want to do bigger changes in one go.  Just use iptables-restore on the modified file to activate your new iptables configuration.)''

In the openvpn server config you will need these lines:

```txt
    dev tun
    topology subnet
    server 10.8.0.0 255.255.255.0
    push "route 192.168.0.0 255.255.255.0"
```

''(this is not a complete configuration file, but it should cover the network part of the configuration)''

This will provide the needed route for all VPN clients to the internal LAN.  If you want to all your VPN clients to send all the internet traffic via the VPN as well (so it looks like they sit behind the LAN when surfing the net), you need this line in addition:

```txt
    push "redirect-gateway def1"
```

And that's basically it.  Not much more extra trickery.  Routing setups are often much easier than people generally believe.  The firewall is generally a bit more tricky, but bridging doesn't make that easier.

= Using routing and OpenVPN not running on the default gateway =
This setup have much of the same requirements as the previous example.  But there are a few minor modifications you need to make.

```txt
                          +-------------------------+
               (public IP)|                         |
  {INTERNET}=============={     Router              |
                          |                         |
                          |         LAN switch      |
                          +------------+------------+
                                       | (192.168.0.1)
                                       |
                                       |              +-----------------------+
                                       |              |                       |
                                       |              |        OpenVPN        |  eth0: 192.168.0.10/24
                                       +--------------{eth0    server         |  tun0: 10.8.0.1/24
                                       |              |                       |
                                       |              |           {tun0}      |
                                       |              +-----------------------+
                                       |
                              +--------+-----------+
                              |                    |
                              |  Other LAN clients |
                              |                    |
                              |   192.168.0.0/24   |
                              |   (internal net)   |
                              +--------------------+

```

The Router needs to have a port forwarding for the port you want to use for OpenVPN and forward that port to 192.168.0.10, which is the IP address of the OpenVPN on the internal network.

The next thing you need to do on the router is to add a route for your VPN subnet.  In the routing table on your Router, add 10.8.0.0/24 to be sent via 192.168.0.10.  This is needed for the traffic from your LAN clients to be able to find their way back to the VPN clients.  If this is not possible, you need add such routes explicitly on all the LAN clients you want to access via the VPN.

The firewall rules will also need to be different, and less extensive.  Here you just need to add rules which opens up traffic from the VPN subnet and into your local LAN.

```txt
    # Allow traffic initiated from VPN to access LAN
    iptables -I FORWARD -i tun0 -o eth0 \
         -s 10.8.0.0/24 -d 192.168.0.0/24 \
         -m conntrack --ctstate NEW -j ACCEPT

    # Allow established traffic to pass back and forth
    iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED \
         -j ACCEPT
```

If you also want your VPN clients to access the complete Internet, just remove the ''-d 192.168.0.0/24'' part from the first iptables example above.

The rest of the configuration will be as the very first routing example.  You need to set net.ipv4.ip_forward=1 and you need the extracts for the OpenVPN configuration as indicated.


''(If others see obvious mistakes, typos, or there are important details which are missing, please correct my errors.)''
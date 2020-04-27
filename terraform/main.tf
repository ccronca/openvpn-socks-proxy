
variable project_id {}
variable gce_ssh_pub_key_file {}

locals {
  region                  = "us-central1"
  zone                    = "${local.region}-a"
  image                   = "debian-cloud/debian-9"
  machine_type            = "f1-micro"
  metadata_startup_script = "sudo apt-get update; sudo apt-get install -yq tcpdump vim traceroute openvpn"
  sites                   = ["site-a", "site-b"]
}

data "google_client_openid_userinfo" "me" {
}

resource "google_os_login_ssh_public_key" "cache" {
  user = data.google_client_openid_userinfo.me.email
  key  = file(var.gce_ssh_pub_key_file)
}

data "google_project" "openvpn_socks_proxy_prj" {
  project_id = var.project_id
}

module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "8.0.0"

  project_id = data.google_project.openvpn_socks_proxy_prj.project_id
  activate_apis = [
    "compute.googleapis.com",
    "oslogin.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]

  disable_services_on_destroy = false
  disable_dependent_services  = false
}

resource "google_compute_network" "sites_vpcs" {
  count                   = length(local.sites)
  name                    = local.sites[count.index]
  project                 = data.google_project.openvpn_socks_proxy_prj.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "sites_subnets" {
  count         = length(local.sites)
  name          = local.sites[count.index]
  ip_cidr_range = "10.${count.index}.0.0/16"
  region        = local.region
  network       = google_compute_network.sites_vpcs[count.index].self_link
  project       = data.google_project.openvpn_socks_proxy_prj.project_id
}


resource "google_compute_instance" "socks_proxy" {
  name         = "socks-proxy"
  project      = data.google_project.openvpn_socks_proxy_prj.project_id
  machine_type = local.machine_type
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  tags = ["ssh", "socks"]

  metadata_startup_script = local.metadata_startup_script

  metadata = {
    enable-oslogin = "TRUE"
  }

  network_interface {
    network = "default"

    access_config {
    }
  }
  depends_on = [google_compute_firewall.allow-proxy]
}

resource "google_compute_instance" "sites" {
  count        = length(local.sites)
  name         = "openvpn-${local.sites[count.index]}"
  project      = data.google_project.openvpn_socks_proxy_prj.project_id
  machine_type = local.machine_type
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = local.image
    }
  }

  metadata_startup_script = "${local.metadata_startup_script}; echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward"
  can_ip_forward          = true

  tags = ["ssh", "openvpn", local.sites[count.index]]

  metadata = {
    enable-oslogin = "TRUE"
  }

  network_interface {
    network    = google_compute_network.sites_vpcs[count.index].self_link
    subnetwork = google_compute_subnetwork.sites_subnets[count.index].self_link

    access_config {

    }
  }

  depends_on = [google_compute_firewall.allow-sites]

}

resource "google_compute_firewall" "allow-sites" {
  count   = length(local.sites)
  name    = "allow-sites-${local.sites[count.index]}"
  project = data.google_project.openvpn_socks_proxy_prj.project_id
  network = google_compute_network.sites_vpcs[count.index].self_link

  allow {
    protocol = "tcp"
    ports    = ["22", "1194"]
  }

  allow {
    protocol = "icmp"
  }

}

resource "google_compute_route" "site-to-site" {
  count       = length(local.sites)
  name        = "site-to-site-${local.sites[count.index]}"
  project     = data.google_project.openvpn_socks_proxy_prj.project_id
  dest_range  = "10.${count.index + 1 % 2}.0.0/16"
  network     = google_compute_network.sites_vpcs[count.index].self_link
  next_hop_ip = google_compute_instance.sites[count.index].network_interface[0].network_ip
  priority    = 100
}

resource "google_compute_firewall" "allow-proxy" {
  name    = "allow-proxy"
  project = data.google_project.openvpn_socks_proxy_prj.project_id
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  allow {
    protocol = "icmp"
  }

}

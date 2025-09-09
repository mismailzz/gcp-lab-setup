data "google_client_config" "provider" {}

provider "google" {
  project = var.project_id
  zone    = var.zone
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  name                     = "my-gke-cluster"
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }
}

# Node Pool (fixed size, no autoscaling beyond 1)
resource "google_container_node_pool" "primary_nodes" {
  name     = "my-node-pool"
  cluster  = google_container_cluster.primary.name
  location = var.zone

  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 1
  }
}

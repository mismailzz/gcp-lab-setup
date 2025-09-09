output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "zone" {
  value = var.zone
}

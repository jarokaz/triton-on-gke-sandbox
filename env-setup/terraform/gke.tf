# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# google_client_config and kubernetes provider must be explicitly specified like the following.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  project_id                 = data.google_project.project.project_id
  name                       = var.cluster_name
  release_channel            = "REGULAR"
  regional                   = false 
  zones                      = [var.zone]
  network                    = google_compute_network.cluster_network.name
  subnetwork                 = google_compute_subnetwork.cluster_subnetwork.name
  ip_range_pods              = google_compute_subnetwork.cluster_subnetwork.secondary_ip_range.1.range_name
  ip_range_services          = google_compute_subnetwork.cluster_subnetwork.secondary_ip_range.0.range_name
  default_max_pods_per_node  = var.max_pods_per_node
  initial_node_count         = var.default_pool_node_count
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  create_service_account     = true 
  grant_registry_access      = true  
  identity_namespace         = "${data.google_project.project.project_id}.svc.id.goog" 

  monitoring_enable_managed_prometheus = true 
  
  cluster_resource_labels = { "mesh_id" : "proj-${data.google_project.project.number}" }

  node_pools = [
    {
      name                      = "triton-node-pool" 
      machine_type              = var.machine_type 
      node_locations            = var.zone
      min_count                 = var.triton_node_count
      max_count                 = var.triton_node_count
      local_ssd_count           = 0
      spot                      = false
      disk_size_gb              = var.disk_size_gb
      disk_type                 = var.disk_type
      image_type                = "COS_CONTAINERD"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      preemptible               = false
    },
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    triton-node-pool = [
        "https://www.googleapis.com/auth/cloud-platform", 
    ]
  }

  node_pools_taints = {
    all = []

    triton-node-pool = [
      {
        key    = "triton-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }
}


resource "kubernetes_namespace" "triton_namespace" {
  metadata {
    name = var.triton_namespace
  }
}


module "triton_workload_identity" {
  source       = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  project_id   = data.google_project.project.project_id
  name         = var.triton_sa_name 
  namespace    = kubernetes_namespace.triton_namespace.metadata[0].name 
  roles        = var.triton_sa_roles
}


module "asm" {
  source                    = "terraform-google-modules/kubernetes-engine/google//modules/asm"
  project_id                = data.google_project.project.project_id
  cluster_name              = module.gke.name
  cluster_location          = module.gke.location
  enable_cni                = false
  enable_fleet_registration = true
  enable_mesh_feature       = false 
}



